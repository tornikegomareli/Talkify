import AVFAudio
import Foundation
import Speech

actor SpeechRecognitionService {
  struct Update: Sendable {
    let finalizedText: String
    let volatileText: String

    var displayText: String {
      finalizedText + volatileText
    }
  }

  struct ResultAccumulator {
    private(set) var finalizedText = ""
    private(set) var volatileText = ""

    mutating func receive(_ text: String, isFinal: Bool) -> Update {
      if isFinal {
        finalizedText += text
        volatileText = ""
      } else {
        volatileText = text
      }

      return Update(
        finalizedText: finalizedText,
        volatileText: volatileText
      )
    }

    var completedText: String {
      finalizedText + volatileText
    }
  }

  enum RecognitionError: LocalizedError, Sendable {
    case unavailable
    case unsupportedLocale
    case missingAudioFormat
    case sessionAlreadyActive
    case noActiveSession
    /// Every language slot the system allows is already held by a language a
    /// key points at. The cap is device-dependent and can be 1.
    case tooManyLanguages(cap: Int)

    var errorDescription: String? {
      switch self {
      case .unavailable:
        "Apple Speech is unavailable on this Mac."
      case .unsupportedLocale:
        "The selected language is not supported by Apple Speech."
      case .missingAudioFormat:
        "Apple Speech did not provide a compatible audio format."
      case .sessionAlreadyActive:
        "A dictation session is already active."
      case .noActiveSession:
        "No dictation session is active."
      case let .tooManyLanguages(cap):
        cap == 1
          ? "This Mac can keep only one dictation language ready at a time."
          : "This Mac can keep only \(cap) dictation languages ready at a time."
      }
    }
  }

  /// A language model download in flight. `fraction` is 0…1 while it runs and
  /// nil once it finishes or fails, which is how the UI knows to stop showing
  /// it. Reported for the language being prepared, whichever key it belongs to.
  struct ModelDownload: Sendable {
    let locale: Locale
    let fraction: Double?
  }

  /// Foundation's `Progress` is documented as safe to read from any thread,
  /// but it is not `Sendable`; the box carries it into the reporting task.
  private struct ProgressBox: @unchecked Sendable {
    let progress: Progress
  }

  private struct PreparedSession: @unchecked Sendable {
    let locale: Locale
    let transcriber: SpeechTranscriber
    let analyzer: SpeechAnalyzer
    let audioFormat: AVAudioFormat
  }

  private struct ActiveSession {
    let prepared: PreparedSession
    let input: MicrophoneInput
    let continuation: AsyncStream<AnalyzerInput>.Continuation
    let resultTask: Task<String, any Error>
  }

  /// One warm session per language, keyed by locale: a second language is
  /// only worth having if it answers as fast as the first, and that means
  /// keeping its analyzer prepared rather than building it on the keypress.
  private var preparedSessions: [Locale: PreparedSession] = [:]
  private var activeSession: ActiveSession?
  /// Locales reserved with AssetInventory, oldest first. The system caps how
  /// many an app may hold (`maximumReservedLocales`), so the oldest is
  /// released when a new one would exceed it.
  private var reservedLocales: [Locale] = []
  /// Builds in flight, one per locale. Preparing a language suspends while
  /// its model downloads, and an actor is reentrant at a suspension point:
  /// without this, pressing the key mid-download starts a second install
  /// request for the same language. Both callers await the same build.
  private var buildTasks: [Locale: Task<PreparedSession, any Error>] = [:]
  private var downloadHandler: (@Sendable (ModelDownload) -> Void)?
  /// Locales a trigger key currently points at, set by `retainOnly`. These are
  /// protected from eviction: the whole point of keeping them reserved is that
  /// their key answers instantly.
  private var boundLocales: Set<Locale> = []

  /// The user's Vocabulary, as Apple Speech consumes it. Held here so a
  /// language warmed later is biased the same as one warmed at launch.
  private var contextualStrings: [String] = []

  /// Reports language model downloads, so a wait that can take minutes is
  /// visible instead of looking like a stall.
  func setDownloadHandler(_ handler: @escaping @Sendable (ModelDownload) -> Void) {
    downloadHandler = handler
  }

  /// Points every prepared analyzer at a new Vocabulary. Called when the
  /// section edits the list and once before the first prewarm — never on the
  /// keypress: `setContext` is async, and the whole point of the warm session
  /// is that pressing the key meets an analyzer with nothing left to do.
  ///
  /// A session already recording keeps the Vocabulary it started with, the way
  /// Dictation session settings snapshot the rest of its preferences.
  func setVocabulary(_ strings: [String]) async {
    guard strings != contextualStrings else { return }
    contextualStrings = strings

    for prepared in preparedSessions.values {
      await applyVocabulary(to: prepared.analyzer)
    }
  }

  /// Biasing is a hint, so a failure to apply it is not a reason to lose the
  /// session: the analyzer stays usable and transcribes unbiased, which is
  /// exactly the behavior of an empty Vocabulary.
  private func applyVocabulary(to analyzer: SpeechAnalyzer) async {
    let context = AnalysisContext()
    if !contextualStrings.isEmpty {
      context.contextualStrings = [.general: contextualStrings]
    }
    try? await analyzer.setContext(context)
  }

  /// Resolves a stored language identifier to a locale Apple Speech
  /// actually supports, falling back to the system language and then to
  /// English, the way a missing preference always behaved.
  func resolveLocale(identifier: String?) async throws -> Locale {
    if let identifier, let supported = await supportedLocale(identifier: identifier) {
      return supported
    }
    return try await defaultLocale()
  }

  /// Strict resolution: nil when the identifier names nothing Apple Speech
  /// supports. The second language must use this rather than falling back to
  /// the system default — a key silently dictating in a language the user never
  /// picked produces fluent nonsense instead of an error (CONTEXT.md).
  func supportedLocale(identifier: String) async -> Locale? {
    guard !identifier.isEmpty else { return nil }
    return await SpeechTranscriber.supportedLocale(
      equivalentTo: Locale(identifier: identifier)
    )
  }

  func prewarm(locale: Locale) async throws {
    try await ensureWarm(locale: locale)
  }

  /// Leaves a warm session for this locale in `preparedSessions`, building
  /// one only if no build is already under way. Exactly one path owns the
  /// cache, so two awaiters of the same build can never end up with the same
  /// analyzer, one using it while the other caches it as idle.
  private func ensureWarm(locale: Locale) async throws {
    if preparedSessions[locale] != nil { return }

    let task: Task<PreparedSession, any Error>
    if let existing = buildTasks[locale] {
      task = existing
    } else {
      task = Task { try await makePreparedSession(locale: locale) }
      buildTasks[locale] = task
    }

    do {
      let prepared = try await task.value
      // Every awaiter caches, not only whoever created the task. Continuations
      // resume in an unspecified order, so if only the creator wrote here a
      // waiter that resumed first would find an empty cache and report Apple
      // Speech as unavailable for what was really a race with a prewarm.
      if preparedSessions[locale] == nil {
        preparedSessions[locale] = prepared
      }
      clearBuildTask(task, for: locale)
    } catch {
      clearBuildTask(task, for: locale)
      throw error
    }
  }

  /// Clears the build slot only when it still holds this task. A discard can
  /// cancel one build while a later call installs another under the same
  /// locale; clearing blindly would drop the newer task's entry and let a third
  /// build start, which is exactly the duplicate install this map prevents.
  private func clearBuildTask(_ task: Task<PreparedSession, any Error>, for locale: Locale) {
    if buildTasks[locale] == task {
      buildTasks[locale] = nil
    }
  }

  /// Drops warm sessions and releases reservations for languages no longer
  /// bound to a key, so changing a language in Settings does not leak a
  /// reservation slot or keep a stale analyzer alive.
  func retainOnly(locales: [Locale]) async {
    let keep = Set(locales)
    boundLocales = keep
    for locale in Set(preparedSessions.keys).union(buildTasks.keys) where !keep.contains(locale) {
      discard(locale: locale)
    }
    for locale in reservedLocales where !keep.contains(locale) {
      await release(locale: locale)
    }
  }

  func start(
    locale: Locale,
    updateHandler: @escaping @Sendable (Update) -> Void,
    failureHandler: @escaping @Sendable (String) -> Void,
    levelHandler: (@Sendable (Float) -> Void)? = nil
  ) async throws {
    guard activeSession == nil else {
      throw RecognitionError.sessionAlreadyActive
    }

    let prepared = try await takePreparedSession(locale: locale)
    try Task.checkCancellation()
    let (stream, continuation) = AsyncStream.makeStream(
      of: AnalyzerInput.self,
      bufferingPolicy: .bufferingNewest(64)
    )

    let resultTask = Task { () throws -> String in
      var accumulator = ResultAccumulator()

      for try await result in prepared.transcriber.results {
        let text = String(result.text.characters)
        updateHandler(accumulator.receive(text, isFinal: result.isFinal))
      }

      return accumulator.completedText
    }

    let input = MicrophoneInput(
      analyzerContinuation: continuation,
      failureHandler: { error in
        failureHandler(error.localizedDescription)
      },
      levelHandler: levelHandler
    )

    activeSession = ActiveSession(
      prepared: prepared,
      input: input,
      continuation: continuation,
      resultTask: resultTask
    )

    do {
      // Start capturing before SpeechAnalyzer finishes attaching to the
      // stream. Bluetooth inputs can take hundreds of milliseconds to become
      // ready, and the stream keeps those early buffers until the analyzer
      // starts consuming them.
      try input.start(outputFormat: prepared.audioFormat)
      try Task.checkCancellation()
      try await prepared.analyzer.start(inputSequence: stream)
      try Task.checkCancellation()
    } catch {
      activeSession = nil
      continuation.finish()
      input.stop()
      await prepared.analyzer.cancelAndFinishNow()
      resultTask.cancel()
      throw error
    }
  }

  func finish() async throws -> String {
    guard let session = activeSession else {
      throw RecognitionError.noActiveSession
    }
    activeSession = nil

    session.input.stop()
    session.continuation.finish()

    do {
      try await session.prepared.analyzer.finalizeAndFinishThroughEndOfInput()
      let text = try await session.resultTask.value
      prewarmAfterSession(locale: session.prepared.locale)
      return text
    } catch {
      session.resultTask.cancel()
      prewarmAfterSession(locale: session.prepared.locale)
      throw error
    }
  }

  func cancel() async {
    guard let session = activeSession else { return }
    activeSession = nil

    session.input.stop()
    session.continuation.finish()
    await session.prepared.analyzer.cancelAndFinishNow()
    session.resultTask.cancel()
    prewarmAfterSession(locale: session.prepared.locale)
  }

  func shutDown() async {
    await cancel()
    for task in buildTasks.values { task.cancel() }
    buildTasks.removeAll()
    preparedSessions.removeAll()

    for locale in reservedLocales {
      await AssetInventory.release(reservedLocale: locale)
    }
    reservedLocales.removeAll()
  }

  /// Hands the session its analyzer. Cold or mid-download, it waits for the
  /// build already in flight rather than starting a rival one.
  private func takePreparedSession(locale: Locale) async throws -> PreparedSession {
    try await ensureWarm(locale: locale)

    guard let prepared = preparedSessions[locale] else {
      throw RecognitionError.unavailable
    }
    preparedSessions[locale] = nil
    return prepared
  }

  private func makePreparedSession(locale requestedLocale: Locale) async throws -> PreparedSession {
    guard SpeechTranscriber.isAvailable else {
      throw RecognitionError.unavailable
    }

    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
      throw RecognitionError.unsupportedLocale
    }

    try await reserve(locale: locale)

    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      // fastResults biases the transcriber towards responsiveness so
      // the live draft streams while the user is still speaking,
      // instead of appearing only at pauses.
      reportingOptions: [.volatileResults, .fastResults],
      attributeOptions: []
    )

    // Only a missing model produces a request, so this is the one branch that
    // can take real time. Everything else here is fast.
    if let installationRequest = try await AssetInventory.assetInstallationRequest(
      supporting: [transcriber]
    ) {
      let reporter = reportProgress(of: installationRequest.progress, for: locale)
      defer {
        reporter.cancel()
        downloadHandler?(ModelDownload(locale: locale, fraction: nil))
      }
      try await installationRequest.downloadAndInstall()
    }

    let modules: [any SpeechModule] = [transcriber]
    guard let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
      compatibleWith: modules
    ) else {
      throw RecognitionError.missingAudioFormat
    }

    let options = SpeechAnalyzer.Options(
      priority: .high,
      modelRetention: .lingering
    )
    let analyzer = SpeechAnalyzer(modules: modules, options: options)
    try await analyzer.prepareToAnalyze(in: audioFormat)
    // Biased here, while the session is still being built, so the keypress
    // path finds the Vocabulary already applied.
    await applyVocabulary(to: analyzer)

    return PreparedSession(
      locale: locale,
      transcriber: transcriber,
      analyzer: analyzer,
      audioFormat: audioFormat
    )
  }

  /// Polls the install request's progress rather than observing it: the value
  /// only feeds a label and a HUD line, so a few reads a second is plenty and
  /// it keeps KVO out of an actor.
  private func reportProgress(of progress: Progress, for locale: Locale) -> Task<Void, Never> {
    let box = ProgressBox(progress: progress)
    let handler = downloadHandler
    handler?(ModelDownload(locale: locale, fraction: 0))

    return Task { [box, handler] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        handler?(ModelDownload(locale: locale, fraction: box.progress.fractionCompleted))
      }
    }
  }

  /// The language to use when the user has never chosen one: the Mac's own,
  /// then English, then whatever Apple Speech supports at all.
  private func defaultLocale() async throws -> Locale {
    if let currentLocale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
      return currentLocale
    }

    if let englishLocale = await SpeechTranscriber.supportedLocale(
      equivalentTo: Locale(identifier: "en-US")
    ) {
      return englishLocale
    }

    guard let firstLocale = await SpeechTranscriber.supportedLocales.first else {
      throw RecognitionError.unsupportedLocale
    }
    return firstLocale
  }

  /// Reserves a locale, keeping every language bound to a key reserved at
  /// once. Only when the system cap would be exceeded is the oldest released,
  /// which also drops its warm session so the two never disagree.
  private func reserve(locale: Locale) async throws {
    if reservedLocales.contains(locale) { return }

    // The cap is device-dependent and can be as low as 1. Only locales that no
    // key points at any more may be evicted: releasing a bound one would drop
    // the language the user is about to press, cancel a download in flight, and
    // fail its awaiter with a cancellation.
    let cap = max(1, AssetInventory.maximumReservedLocales)
    var evictable = reservedLocales.filter { !boundLocales.contains($0) }
    while reservedLocales.count >= cap, let oldest = evictable.first {
      evictable.removeFirst()
      await release(locale: oldest)
    }

    guard reservedLocales.count < cap else {
      // Every slot is held by another bound language. Say so plainly rather
      // than evicting one and leaving two keys fighting over one slot.
      throw RecognitionError.tooManyLanguages(cap: cap)
    }

    _ = try await AssetInventory.reserve(locale: locale)
    reservedLocales.append(locale)
  }

  private func release(locale: Locale) async {
    await AssetInventory.release(reservedLocale: locale)
    reservedLocales.removeAll { $0 == locale }
    discard(locale: locale)
  }

  /// Forgets a language: drops its warm session and stops any build still
  /// running for it, so deselecting a language mid-download does not leave
  /// work in flight that would cache a session nothing can reach.
  private func discard(locale: Locale) {
    preparedSessions[locale] = nil
    buildTasks[locale]?.cancel()
    buildTasks[locale] = nil
  }

  private func prewarmAfterSession(locale: Locale) {
    Task { [weak self] in
      try? await self?.prewarm(locale: locale)
    }
  }
}
