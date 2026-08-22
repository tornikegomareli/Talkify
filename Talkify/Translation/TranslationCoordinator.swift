import Foundation

/// Everything Dictate and Translate keeps between sessions: which pair the
/// translate key would run, whether it can run right now, and how a missing
/// model is installed.
///
/// It exists so neither of its two callers has to carry the other's business.
/// Dictation asks it two questions, the pair for a session and the translation
/// of a draft, and Settings drives the install and reads the state straight
/// off it, rather than through callbacks the controller forwards.
///
/// The seam is `TranslationService.Client`, one layer down. Wrapping a seam in
/// another seam would only mean two fakes for one framework.
@MainActor
final class TranslationCoordinator {
  /// Every language the source can reach, and the language they are measured
  /// from. Settings needs the source to name a pair, and this is the only
  /// place it is resolved.
  /// The list, and the language it was measured from. Both go empty while a
  /// new source is resolving, because a target chosen against the old list
  /// would install a model for a language that is no longer the source.
  var onTargetsChange: (([TranslationTarget], Locale.Language?) -> Void)?
  var onStateChange: ((TranslationModelState) -> Void)?

  /// The pair the translate key would run, or nil while no target is chosen.
  private(set) var pair: TranslationPair?
  /// Whether that pair can translate now. False while a model is missing,
  /// which refuses the translate key rather than letting someone speak into
  /// a rescue path.
  private(set) var isReady = false

  /// How an install ended, which is not a yes or no: a language change while
  /// the model downloaded makes it nobody's business what the setting says.
  enum InstallOutcome: Equatable {
    case installed
    /// The model never arrived.
    case unavailable
    /// A language change replaced the pair while this ran.
    case superseded
  }

  private let service: TranslationService
  /// The language the current targets were measured from, so an install can
  /// re-resolve without being told the source again.
  private var source: Locale?
  /// The pair being installed. Choosing a downloadable target starts an
  /// install and changes the setting that re-resolves the languages, so an
  /// `apply` runs alongside it: without this it reports the model as missing
  /// over the download already fetching it, and Settings offers a second one.
  private var installing: TranslationPair?
  /// Which install the `installing` marker belongs to. Two installs of the
  /// same pair cannot be told apart by pair alone, and a cancelled one resumes
  /// after its replacement has already claimed the marker: it would then
  /// report a missing model over the replacement's download and clear a marker
  /// that is no longer its own.
  private var installGeneration = 0
  /// The wait in flight, so it can be abandoned from anywhere. Apple reports
  /// nothing when its download sheet is dismissed without downloading, and the
  /// view that started the wait is replaced by leaving the Language section,
  /// so a handle held there would be gone exactly when it was needed.
  private var installTask: Task<InstallOutcome, Never>?
  /// Which request the published state belongs to. Two language changes in
  /// quick succession run two `apply` calls, and the first can finish last:
  /// without this, the older one reports readiness for a pair nobody chose
  /// and the translate key is accepted or refused against the wrong model.
  private var request = 0

  init(service: TranslationService) {
    self.service = service
  }

  /// Drops the pair until the next `apply`.
  ///
  /// Called before the languages are re-resolved. The resolved dictation
  /// locale changes before the pair does, and in between the two the old pair
  /// is still ready: a translate key pressed there would dictate in the new
  /// language and translate as though it were the old one. There is genuinely
  /// no pair while the source is being resolved, so this says so.
  ///
  /// Nothing is reported: the state is about to be replaced by the `apply`
  /// that follows, and announcing an interim `none` only blinks the Settings
  /// row on every language change.
  /// - Returns: the number the reload that follows must carry, so a reload
  ///   that overtook a newer one cannot publish as though it were the newest.
  @discardableResult
  func invalidate() -> Int {
    request += 1
    pair = nil
    isReady = false
    onTargetsChange?([], nil)
    return request
  }

  /// Resolves a pair and readies it, reporting what it can do.
  ///
  /// Never throws, and never refuses. A translation model that will not load
  /// must not fail the preparation plain dictation depends on: the user may
  /// never press the translate key at all, and refusing to dictate because of
  /// it would be the wrong trade.
  func apply(_ pair: TranslationPair?, from source: Locale, request: Int) async {
    // Numbered by the invalidate that opened this reload, not here: two
    // reloads overlap whenever two settings change in quick succession, and
    // the older one finishing last would otherwise take the newer number and
    // publish a pair nobody chose.
    guard request == self.request else { return }
    self.source = source
    self.pair = pair
    // A wait for a model nobody is asking for any more would poll out its
    // whole budget before noticing, and hold the Settings row while it did.
    if let installing, installing != pair {
      stopInstalling()
    }
    await service.retain(pair)
    guard request == self.request else { return }
    discoverTargets(from: source, for: request)

    guard let pair else {
      isReady = false
      onStateChange?(.none)
      return
    }
    // A missing model is not something this can wait for. Apple installs one
    // only from a View modifier, so the answer here is that Settings has to
    // do it, not a prewarm that throws at once.
    let availability = await service.availability(of: pair)
    guard request == self.request else { return }
    guard availability == .installed else {
      isReady = false
      onStateChange?(installing == pair ? .downloading : .needsDownload)
      return
    }
    let isPrepared = await service.prewarm(pair)
    guard request == self.request else { return }
    isReady = isPrepared
    onStateChange?(isPrepared ? .ready : .failed)
  }

  /// Probes the target list without being waited on.
  ///
  /// The list exists for the Settings picker alone, and building it asks Apple
  /// about every supported language one at a time. Dictation's readiness, and
  /// with it the trigger, must not stand behind that.
  private func discoverTargets(from source: Locale, for request: Int) {
    Task { [weak self] in
      guard let targets = await self?.service.targets(from: source) else { return }
      guard let self, request == self.request else { return }
      onTargetsChange?(targets, source.language)
    }
  }

  /// Waits for a model Settings asked Apple to install, then readies it.
  func install(_ pair: TranslationPair) async -> InstallOutcome {
    // One wait at a time. The handle below is the only way to reach a wait, so
    // replacing it without cancelling would leave the old one polling out its
    // whole budget with nothing able to stop it.
    installTask?.cancel()
    // Numbered here, not inside the task. A replacement that starts running
    // before the task it cancelled would otherwise take the lower number, and
    // the cancelled one would outrank it: it would clear the replacement's
    // marker and leave Settings downloading a model nobody is preparing.
    installGeneration += 1
    let generation = installGeneration
    // Run through a task this holds, so `stopInstalling` can reach it. Awaiting
    // its value ignores this caller's own cancellation, which is what is wanted
    // here: the wait outlives whichever view started it.
    let task = Task { await performInstall(pair, generation: generation) }
    installTask = task
    defer { if installTask == task { installTask = nil } }
    return await task.value
  }

  /// Abandons the wait, which lands on the same answer as a model that never
  /// arrived.
  func stopInstalling() {
    installTask?.cancel()
  }

  private func performInstall(
    _ pair: TranslationPair,
    generation: Int
  ) async -> InstallOutcome {
    // Superseded before it even started, if its replacement got here first.
    guard installGeneration == generation else { return .superseded }
    guard source != nil else { return .unavailable }
    installing = pair
    defer { if installGeneration == generation { installing = nil } }

    onStateChange?(.downloading)
    let didInstall = await service.awaitInstall(pair)
    // A newer install of the same pair, or a language change, owns the state
    // now. Reporting this one's result would put a missing model over the
    // download replacing it, or leave the translate key running a language
    // Settings no longer shows.
    guard installGeneration == generation else { return .superseded }
    guard self.pair == pair, let source else { return .superseded }
    guard didInstall else {
      onStateChange?(.needsDownload)
      return .unavailable
    }
    // The same path a launch takes, so an install cannot drift from it.
    await apply(pair, from: source, request: self.request)
    // The model arrived. Whether it then loaded is a different problem, and
    // the state callback has already said which — reporting this as a failed
    // download would revert the pick and hide the retry the failure needs.
    return .installed
  }

  /// Tries the pair again after the key was refused, so one press while a
  /// model was still arriving does not stay dead until Settings is touched.
  func retry() {
    guard let pair, !isReady else { return }
    let request = request
    Task { [weak self] in
      guard let self else { return }
      let isPrepared = await service.prewarm(pair)
      // Only a retry that worked is worth reporting: a failed one leaves
      // everything exactly as the last apply already described it.
      guard request == self.request, self.pair == pair, isPrepared else { return }
      isReady = true
      onStateChange?(.ready)
      // A model installed outside Talkify makes its whole row stale, not just
      // this pair's state.
      if let source { discoverTargets(from: source, for: request) }
    }
  }

  func translate(_ text: String, with pair: TranslationPair) async throws -> String {
    try await service.translate(text, with: pair)
  }

  func shutDown() async {
    await service.shutDown()
  }
}
