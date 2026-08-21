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
      retain: { await translator.retain($0) },
      shutDown: { await translator.shutDown() }
    )
  }
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
      // from then on, so it has to be thrown away rather than reused.
      Task { await self.discard(pair) }
      held.session.cancel()
    }
  }

  func retain(_ pair: TranslationPair?) async {
    for (held, value) in sessions where held != pair {
      value.session.cancel()
      sessions[held] = nil
    }
    for (held, task) in buildTasks where held != pair {
      task.cancel()
      buildTasks[held] = nil
    }
  }

  func shutDown() async {
    await retain(nil)
  }

  private func discard(_ pair: TranslationPair) {
    sessions[pair] = nil
    buildTasks[pair]?.cancel()
    buildTasks[pair] = nil
  }

  /// One build per pair, however many callers arrive. `prepareTranslation()`
  /// suspends while a model downloads, and this actor is reentrant across that
  /// suspension, so without the task table two presses start two installs.
  private func held(for pair: TranslationPair) async throws -> Held {
    if let existing = sessions[pair] { return existing }
    if let building = buildTasks[pair] { return try await building.value }

    let task = Task<Held, any Error> {
      let session = TranslationSession(installedSource: pair.source, target: pair.target)
      try await session.prepareTranslation()
      return Held(session: session)
    }
    buildTasks[pair] = task

    do {
      let built = try await task.value
      // Only the build that still owns the slot may claim it: a retain that
      // dropped this pair mid-build must not have its decision undone.
      if buildTasks[pair] == task {
        buildTasks[pair] = nil
        sessions[pair] = built
      }
      return built
    } catch {
      if buildTasks[pair] == task { buildTasks[pair] = nil }
      throw error
    }
  }
}
