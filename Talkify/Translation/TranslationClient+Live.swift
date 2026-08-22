import Foundation
import Translation

/// The one file that imports Translation. Everything above it works in
/// `TranslationPair` and `TranslationAvailability`, so the framework can be
/// faked at the seam and cannot leak into the rest of the app.
extension TranslationService.Client {
  static var live: Self {
    let translator = LiveTranslator()
    return Self(
      availability: { await translator.availability(of: $0) },
      prepare: { try await translator.prepare($0) },
      translate: { try await translator.translate($1, with: $0) },
      candidateTargets: { await supportedTargetLanguages() },
      retain: { await translator.retain($0) },
      shutDown: { await translator.shutDown() }
    )
  }
}

/// Read outside any actor on purpose. `supportedLanguages` is a nonisolated
/// async property on a non-Sendable class, so reading it from inside an actor
/// is a Swift 6 error: the class would have to leave that actor's isolation.
/// The same shape blocks `TranslationSession.isReady`, which is why nothing
/// here uses it.
private func supportedTargetLanguages() async -> [Locale.Language] {
  await LanguageAvailability().supportedLanguages
}

/// Holds the prewarmed sessions.
///
/// An actor because `TranslationSession` is not Sendable: it never leaves this
/// actor's isolation, and the box below exists only so a `Task` can carry one
/// between two points inside it.
private actor LiveTranslator {
  /// `Task` requires a Sendable success value. The session inside never
  /// crosses an isolation boundary, so the box is a compiler formality rather
  /// than a claim about the session. Same box, same reason, as
  /// `SpeechRecognitionService.PreparedSession`.
  private struct Held: @unchecked Sendable {
    let session: TranslationSession
  }

  private var sessions: [TranslationPair: Held] = [:]
  /// The one pair worth holding on to. A session that finishes on a pair
  /// Settings has already moved past still needs its translation, but caching
  /// it would leave that model resident with no later retain to evict it.
  private var retained: TranslationPair?
  /// In-flight builds, so pressing the translate key while a model downloads
  /// joins that download instead of starting a second install of the same pair.
  private var buildTasks: [TranslationPair: Task<Held, any Error>] = [:]

  func availability(of pair: TranslationPair) async -> TranslationAvailability {
    switch await LanguageAvailability().status(from: pair.source, to: pair.target) {
    case .installed: .installed
    case .supported: .downloadable
    case .unsupported: .unsupported
    @unknown default: .unsupported
    }
  }

  func prepare(_ pair: TranslationPair) async throws {
    _ = try await held(for: pair)
  }

  func translate(_ text: String, with pair: TranslationPair) async throws -> String {
    let held = try await held(for: pair)
    return try await withTaskCancellationHandler {
      try await held.session.translate(text).targetText
    } onCancel: {
      // Cancelling is not free: a cancelled session throws alreadyCancelled
      // from then on, so it has to be thrown away rather than reused. This one
      // and no other: by the time a timed-out translation unwinds, the target
      // may have moved away and back, and a newer session for the same pair
      // would then be the one thrown away.
      Task { await self.discard(held.session, for: pair) }
      held.session.cancel()
    }
  }

  /// Drops every held pair but this one, without cancelling what it drops.
  ///
  /// Dropping, not cancelling, because a session this actor no longer wants
  /// can still be translating for a dictation session that snapshotted it at
  /// its start (ADR-0004). Cancelling would fail that translation and send the
  /// user's words to the rescue path over a Settings change they made after
  /// they finished speaking. Releasing the reference lets the session
  /// deallocate once the translation using it returns, and a build task that
  /// completes after being dropped no longer owns its slot, so it cannot
  /// reinstall itself.
  func retain(_ pair: TranslationPair?) async {
    retained = pair
    sessions = sessions.filter { $0.key == pair }
    buildTasks = buildTasks.filter { $0.key == pair }
  }

  /// Cancels everything, because the process is going away and there is no
  /// later translation left to protect.
  func shutDown() async {
    for held in sessions.values { held.session.cancel() }
    sessions.removeAll()
    for task in buildTasks.values { task.cancel() }
    buildTasks.removeAll()
  }

  /// Drops one session, and only if it is still the one held for its pair.
  ///
  /// Nothing is done about builds in flight: a build for this pair started
  /// after this session was cancelled is newer work, and cancelling it would
  /// leave the current target with no model at all.
  private func discard(_ session: TranslationSession, for pair: TranslationPair) {
    guard sessions[pair]?.session === session else { return }
    sessions[pair] = nil
  }

  /// Waits for a build while staying cancellable.
  ///
  /// `await task.value` ignores the cancellation of whoever is awaiting it, so
  /// a translation that hit its timeout went on waiting here for the
  /// preparation, and its task group could not return until the preparation
  /// finished. The six-second budget bounded nothing.
  private func value(of task: Task<Held, any Error>) async throws -> Held {
    try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  /// One build per pair, however many callers arrive. `prepareTranslation()`
  /// suspends while a model downloads, and this actor is reentrant across that
  /// suspension, so without the task table two presses start two installs.
  private func held(for pair: TranslationPair) async throws -> Held {
    if let existing = sessions[pair] { return existing }
    if let building = buildTasks[pair] { return try await value(of: building) }

    let task = Task<Held, any Error> {
      let session = TranslationSession(installedSource: pair.source, target: pair.target)
      try await session.prepareTranslation()
      return Held(session: session)
    }
    buildTasks[pair] = task

    do {
      let built = try await value(of: task)
      // Only the build that still owns the slot may claim it: a retain that
      // dropped this pair mid-build must not have its decision undone.
      if buildTasks[pair] == task {
        buildTasks[pair] = nil
        // Built for the pair still wanted: keep it. Built for one a language
        // change has passed: hand it back and hold nothing, or the model stays
        // loaded until the next target change or the quit.
        if retained == pair { sessions[pair] = built }
      }
      return built
    } catch {
      if buildTasks[pair] == task { buildTasks[pair] = nil }
      throw error
    }
  }
}
