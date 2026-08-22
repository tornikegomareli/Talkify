import Foundation
import Testing
@testable import Talkify

/// What the coordinator reports, which is what both Settings and the translate
/// key act on. The framework is faked at `TranslationService.Client`, so these
/// are the rules and not Apple's behaviour.
@MainActor
struct TranslationCoordinatorTests {
  private let source = Locale(identifier: "en_US")
  private let pair = TranslationPair(
    source: Locale.Language(identifier: "en"),
    target: Locale.Language(identifier: "es")
  )

  /// Answers however a test needs, and counts what was asked.
  private final class Fake: @unchecked Sendable {
    private let lock = NSLock()
    private var prepareCalls = 0
    private var availabilityCalls = 0

    var availability: TranslationAvailability = .installed
    var prepareError: (any Error)?
    /// Flips availability to installed after this many checks, standing in for
    /// a download finishing.
    var installsAfterChecks: Int?
    /// Held before each prepare answers, so two applies can be in flight at
    /// once and finish out of order.
    var prepareDelay: Duration = .zero
    /// Set to hang the translator, so the timeout is the only way out.
    var translateNeverAnswers = false

    var prepareCount: Int { lock.withLock { prepareCalls } }

    func service() -> TranslationService {
      var service = TranslationService(
        client: TranslationService.Client(
          availability: { [self] _ in
            let checks = lock.withLock { () -> Int in
              availabilityCalls += 1
              return availabilityCalls
            }
            if let installsAfterChecks, checks >= installsAfterChecks { return .installed }
            return availability
          },
          prepare: { [self] _ in
            lock.withLock { prepareCalls += 1 }
            if prepareDelay != .zero { try? await Task.sleep(for: prepareDelay) }
            if let prepareError { throw prepareError }
          },
          translate: { [self] _, text in
            if translateNeverAnswers { try await Task.sleep(for: .seconds(3600)) }
            return "traducido: \(text)"
          },
          candidateTargets: { [] },
          retain: { _ in },
          shutDown: {}
        )
      )
      service.installPollInterval = .milliseconds(1)
      return service
    }
  }

  private struct Boom: Error {}

  @Test func anInstalledPairIsReady() async {
    let fake = Fake()
    let coordinator = TranslationCoordinator(service: fake.service())
    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }

    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    #expect(coordinator.isReady)
    #expect(reported == [.ready])
  }

  /// The rule that kept the app usable: a missing model is reported, never
  /// prepared. Preparing one wants Apple's download sheet, and with no window
  /// to present it the call never returns.
  @Test func aMissingModelIsReportedRatherThanPrepared() async {
    let fake = Fake()
    fake.availability = .downloadable
    let coordinator = TranslationCoordinator(service: fake.service())
    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }

    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    #expect(!coordinator.isReady)
    #expect(reported == [.needsDownload])
    #expect(fake.prepareCount == 0)
  }

  /// An installed model that will not load is a different answer from one that
  /// is not here yet: only the second is worth offering a download for.
  @Test func anInstalledModelThatWillNotLoadReportsFailed() async {
    let fake = Fake()
    fake.prepareError = Boom()
    let coordinator = TranslationCoordinator(service: fake.service())
    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }

    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    #expect(!coordinator.isReady)
    #expect(reported == [.failed])
  }

  @Test func noTargetIsNotAFailure() async {
    let fake = Fake()
    let coordinator = TranslationCoordinator(service: fake.service())
    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }

    await coordinator.apply(nil, from: source, request: coordinator.invalidate())

    #expect(coordinator.pair == nil)
    #expect(reported == [.none])
  }

  /// An install waits for the model, then goes through the same path a launch
  /// takes, so the two cannot drift apart.
  @Test func anInstallEndsReadyOnceTheModelLands() async {
    let fake = Fake()
    fake.availability = .downloadable
    let coordinator = TranslationCoordinator(service: fake.service())
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }
    fake.installsAfterChecks = 3

    #expect(await coordinator.install(pair) == .installed)
    #expect(coordinator.isReady)
    #expect(reported.first == .downloading)
    #expect(reported.last == .ready)
  }

  /// A model that never arrives leaves the state where it was, so Settings can
  /// offer the download again rather than claiming a failure it cannot fix.
  @Test func anInstallThatNeverLandsGoesBackToNeedsDownload() async {
    let fake = Fake()
    fake.availability = .downloadable
    var service = fake.service()
    service.installBudget = .milliseconds(5)
    let coordinator = TranslationCoordinator(service: service)
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }

    #expect(await coordinator.install(pair) == .unavailable)
    #expect(reported == [.downloading, .needsDownload])
  }

  /// Installing before a source is known cannot resolve anything, and must not
  /// claim it did.
  @Test func anInstallWithoutASourceRefuses() async {
    let coordinator = TranslationCoordinator(service: Fake().service())

    #expect(await coordinator.install(pair) == .unavailable)
  }

  /// A target chosen while a model downloads owns the state. Applying the
  /// finished one anyway would run the translate key on a language Settings no
  /// longer shows.
  @Test func anInstallSupersededByANewTargetIsDropped() async {
    let fake = Fake()
    fake.availability = .downloadable
    let coordinator = TranslationCoordinator(service: fake.service())
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    let installing = Task { await coordinator.install(pair) }
    // Chosen while that install runs, exactly as picking another language does.
    let other = TranslationPair(
      source: Locale.Language(identifier: "en"),
      target: Locale.Language(identifier: "de")
    )
    fake.availability = .installed
    await coordinator.apply(other, from: source, request: coordinator.invalidate())
    fake.installsAfterChecks = 1

    #expect(await installing.value == .superseded)
    #expect(coordinator.pair == other)
  }

  /// The resolved dictation locale changes before the pair does. In between,
  /// a translate key must not be served the pair that is already replaced: it
  /// would dictate in the new language and translate as though it were the old.
  @Test func invalidatingLeavesNothingForTheTranslateKey() async {
    let fake = Fake()
    let coordinator = TranslationCoordinator(service: fake.service())
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())
    #expect(coordinator.isReady)

    coordinator.invalidate()

    #expect(!coordinator.isReady)
    #expect(coordinator.pair == nil)
  }

  /// A retry that works has to say so, or Settings keeps offering a download
  /// for a model the translate key is already using.
  @Test func aRetryThatWorksReportsItself() async {
    let fake = Fake()
    fake.availability = .downloadable
    let coordinator = TranslationCoordinator(service: fake.service())
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }
    // Installed outside Talkify, which is what makes a refused press worth
    // retrying at all.
    fake.availability = .installed
    coordinator.retry()
    await waitUntil { coordinator.isReady }

    #expect(reported == [.ready])
  }

  /// A retry that fails changes nothing, so it reports nothing.
  @Test func aRetryThatFailsStaysQuiet() async {
    let fake = Fake()
    fake.availability = .downloadable
    let coordinator = TranslationCoordinator(service: fake.service())
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }
    coordinator.retry()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(!coordinator.isReady)
    #expect(reported.isEmpty)
  }

  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  /// Choosing a downloadable target starts an install and changes the setting
  /// that re-resolves the languages, so an apply runs alongside it. It must not
  /// report the model as missing over the download already fetching it, or
  /// Settings offers a second Download while the first poll runs.
  @Test func anApplyDuringAnInstallDoesNotOfferTheDownloadAgain() async {
    let fake = Fake()
    fake.availability = .downloadable
    var service = fake.service()
    // Generous, so the install is still waiting when the apply lands. A sleep
    // in its place failed under a loaded machine and passed on its own.
    service.installBudget = .seconds(5)
    let coordinator = TranslationCoordinator(service: service)
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }
    let installTask = Task { await coordinator.install(pair) }
    await waitUntil { reported.contains(.downloading) }

    reported.removeAll()
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())
    #expect(reported == [.downloading])

    coordinator.stopInstalling()
    _ = await installTask.value
  }

  /// Apple reports nothing when its download sheet is dismissed without
  /// downloading, so the wait has to be abandonable. It lands on the same
  /// answer as a model that never arrived.
  @Test func aStoppedInstallEndsAsUnavailable() async {
    let fake = Fake()
    fake.availability = .downloadable
    var service = fake.service()
    service.installBudget = .seconds(30)
    let coordinator = TranslationCoordinator(service: service)
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }
    let installTask = Task { await coordinator.install(pair) }
    await waitUntil { reported.contains(.downloading) }

    coordinator.stopInstalling()

    #expect(await installTask.value == .unavailable)
    #expect(reported == [.downloading, .needsDownload])
  }

  /// One wait at a time, and the replaced one says nothing.
  ///
  /// The handle is the only way to reach a wait, so a second install has to end
  /// the first or it polls out its whole budget with Stop unable to reach it.
  /// And two installs of the same pair cannot be told apart by pair alone: the
  /// cancelled one resumes after its replacement claimed the marker, and would
  /// report a missing model over the download that replaced it.
  @Test func aSecondInstallEndsTheFirstOneQuietly() async {
    let fake = Fake()
    fake.availability = .downloadable
    var service = fake.service()
    service.installBudget = .seconds(30)
    let coordinator = TranslationCoordinator(service: service)
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }
    let first = Task { await coordinator.install(pair) }
    await waitUntil { reported.contains(.downloading) }

    // Timed, not counted: an orphaned wait reaches the same answer eventually,
    // when its thirty-second budget runs out. How long it took is the only
    // thing that says whether it was ended or merely forgotten.
    let started = ContinuousClock.now
    let second = Task { await coordinator.install(pair) }
    let outcome = await first.value
    let elapsed = ContinuousClock.now - started

    // Superseded rather than unavailable: it was replaced, not refused, and
    // the caller must not revert the pick over it.
    #expect(outcome == .superseded)
    #expect(elapsed < .seconds(3), "waited \(elapsed) for a wait that was replaced")
    #expect(!reported.contains(.needsDownload))

    coordinator.stopInstalling()
    _ = await second.value
  }

  /// A wait for a pair nobody is asking for any more must end when the new
  /// pair resolves, not poll out its whole budget first while the Settings row
  /// stands there claiming a download.
  @Test func resolvingADifferentPairEndsAWaitForTheOldOne() async {
    let fake = Fake()
    fake.availability = .downloadable
    var service = fake.service()
    service.installBudget = .seconds(30)
    let coordinator = TranslationCoordinator(service: service)
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }
    let installTask = Task { await coordinator.install(pair) }
    await waitUntil { reported.contains(.downloading) }

    // The dictation language changed, so the pair being installed is not the
    // pair anyone wants.
    let other = TranslationPair(
      source: Locale.Language(identifier: "fr"),
      target: Locale.Language(identifier: "es")
    )
    await coordinator.apply(other, from: Locale(identifier: "fr_FR"), request: coordinator.invalidate())

    #expect(await installTask.value == .superseded)
  }

  /// A timed-out translation leaves the pair usable. Which session gets thrown
  /// away is decided inside the live client, below this seam, so that part is
  /// not what this pins: only that a timeout is survivable and the next
  /// translation on the same pair still works.
  @Test func aTimedOutTranslationLeavesThePairUsable() async throws {
    let fake = Fake()
    var service = fake.service()
    service.timeout = .milliseconds(20)
    let coordinator = TranslationCoordinator(service: service)
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())

    fake.translateNeverAnswers = true
    await #expect(throws: TranslationFailure.timedOut) {
      _ = try await coordinator.translate("hola", with: pair)
    }

    // The pair is still prepared: a session was thrown away, not the pair.
    fake.translateNeverAnswers = false
    let again = try await coordinator.translate("hola", with: pair)
    #expect(again == "traducido: hola")
  }

  /// Two settings changed in quick succession run two reloads, and the older
  /// one can finish last. It carries the number its own invalidate handed out,
  /// so finishing late is not the same as being newest.
  @Test func anOlderReloadCannotPublishOverANewerOne() async {
    let fake = Fake()
    let coordinator = TranslationCoordinator(service: fake.service())

    let stale = coordinator.invalidate()
    let current = coordinator.invalidate()

    await coordinator.apply(pair, from: source, request: stale)
    #expect(!coordinator.isReady)
    #expect(coordinator.pair == nil)

    await coordinator.apply(pair, from: source, request: current)
    #expect(coordinator.isReady)
    #expect(coordinator.pair == pair)
  }

  /// A new source makes the published list wrong, not merely stale: a target
  /// chosen against it would install a model for the language that just
  /// stopped being the source.
  @Test func invalidatingEmptiesThePublishedTargets() async {
    let fake = Fake()
    let coordinator = TranslationCoordinator(service: fake.service())
    var reported: [(targets: [TranslationTarget], source: Locale.Language?)] = []
    coordinator.onTargetsChange = { reported.append((targets: $0, source: $1)) }

    coordinator.invalidate()

    #expect(reported.count == 1)
    #expect(reported.first?.targets.isEmpty == true)
    #expect(reported.first?.source == nil)
  }

  /// Two language changes in quick succession run two applies. Whichever
  /// finishes last, the state must belong to the later request.
  @Test func anOlderApplyFinishingLastDoesNotOverwriteTheNewerOne() async {
    let fake = Fake()
    fake.prepareDelay = .milliseconds(60)
    let coordinator = TranslationCoordinator(service: fake.service())
    var reported: [TranslationModelState] = []
    coordinator.onStateChange = { reported.append($0) }

    let first = Task { await coordinator.apply(pair, from: source, request: coordinator.invalidate()) }
    // Long enough to be inside the first prepare, short enough to precede it.
    try? await Task.sleep(for: .milliseconds(20))
    fake.prepareError = Boom()
    await coordinator.apply(pair, from: source, request: coordinator.invalidate())
    await first.value

    // The second request said failed, and the first must not undo it.
    #expect(!coordinator.isReady)
    #expect(reported == [.failed])
  }
}
