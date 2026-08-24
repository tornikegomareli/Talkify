import Foundation
import Testing
@testable import Talkify

/// The rules Dictate and Translate follows before and around a translation.
/// None of these touch Apple's translator: the point of the Client seam is
/// that the decisions are testable and the framework call is not the decision.
struct TranslationServiceTests {
  private let pair = TranslationPair(
    source: Locale.Language(identifier: "en"),
    target: Locale.Language(identifier: "es")
  )

  /// Records what the service asked for, and answers however a test needs.
  private final class Spy: @unchecked Sendable {
    private let lock = NSLock()
    private var translateCalls = 0
    private var prepareCalls = 0
    private var retained: [TranslationPair?] = []

    var availability: TranslationAvailability = .installed
    var prepareError: (any Error)?
    var answer = "traducido"
    /// Set to hang the translator, so the timeout is the only way out.
    var neverAnswers = false
    /// Set to hang the availability probe instead, which is the other call a
    /// finish waits on.
    var availabilityNeverAnswers = false
    var candidates: [Locale.Language] = []
    /// Flips availability to installed once this many checks have happened,
    /// standing in for a download finishing.
    var installsAfterChecks: Int?
    /// Availability per language code, for the catalog tests.
    var perLanguage: [String: TranslationAvailability] = [:]

    private var availabilityCalls = 0
    var availabilityCount: Int { lock.withLock { availabilityCalls } }
    var translateCount: Int { lock.withLock { translateCalls } }
    var prepareCount: Int { lock.withLock { prepareCalls } }
    var retainedPairs: [TranslationPair?] { lock.withLock { retained } }

    func client() -> TranslationService.Client {
      TranslationService.Client(
        availability: { [self] pair in
          let checks = lock.withLock { () -> Int in
            availabilityCalls += 1
            return availabilityCalls
          }
          if availabilityNeverAnswers { try? await Task.sleep(for: .seconds(3600)) }
          if let installsAfterChecks, checks >= installsAfterChecks { return .installed }
          return perLanguage[pair.target.languageCode?.identifier ?? ""] ?? availability
        },
        prepare: { [self] _ in
          lock.withLock { prepareCalls += 1 }
          if let prepareError { throw prepareError }
        },
        translate: { [self] _, _ in
          lock.withLock { translateCalls += 1 }
          if neverAnswers { try await Task.sleep(for: .seconds(3600)) }
          return answer
        },
        candidateTargets: { [self] in candidates },
        retain: { [self] pair in lock.withLock { retained.append(pair) } },
        shutDown: {}
      )
    }
  }

  private struct Boom: Error {}

  @Test func aTranslationReplacesTheWordsSpoken() async throws {
    let spy = Spy()
    let service = TranslationService(client: spy.client())

    let out = try await service.translate("the words", with: pair)

    #expect(out == "traducido")
    #expect(spy.translateCount == 1)
  }

  /// A session that heard only silence must not show an error. Apple's
  /// translator reports empty input as a failure; this returns it unchanged.
  @Test func emptyAndBlankTextComeBackUntouchedWithoutTranslating() async throws {
    let spy = Spy()
    let service = TranslationService(client: spy.client())

    #expect(try await service.translate("", with: pair) == "")
    #expect(try await service.translate("   \n\t ", with: pair) == "   \n\t ")
    #expect(spy.translateCount == 0)
  }

  /// A wedged translator must not hold the user's words forever.
  @Test func aTranslatorThatNeverAnswersTimesOut() async {
    let spy = Spy()
    spy.neverAnswers = true
    var service = TranslationService(client: spy.client())
    service.timeout = .milliseconds(50)

    await #expect(throws: TranslationFailure.timedOut) {
      try await service.translate("the words", with: pair)
    }
  }

  /// An impossible pair is refused before anything is asked of the translator.
  @Test func anUnsupportedPairIsRefusedWithoutTranslating() async {
    let spy = Spy()
    spy.availability = .unsupported
    let service = TranslationService(client: spy.client())

    await #expect(throws: TranslationFailure.unsupported) {
      try await service.translate("the words", with: pair)
    }
    #expect(spy.translateCount == 0)
  }

  /// The rule that protects plain dictation: a model that will not load leaves
  /// the translate key unready and everything else working.
  @Test func aPrewarmThatFailsReportsNotReadyRatherThanThrowing() async {
    let spy = Spy()
    spy.prepareError = Boom()
    let service = TranslationService(client: spy.client())

    #expect(await service.prewarm(pair) == false)
    #expect(spy.prepareCount == 1)
  }

  @Test func aPrewarmOfAnUnsupportedPairNeverAsksToPrepareIt() async {
    let spy = Spy()
    spy.availability = .unsupported
    let service = TranslationService(client: spy.client())

    #expect(await service.prewarm(pair) == false)
    #expect(spy.prepareCount == 0)
  }

  /// Preparing a pair whose model is missing does not fetch it. It waits for
  /// Apple's download sheet, and with no window to present one the call never
  /// returns, wedging the pair until the app is relaunched. So it is never made.
  @Test func aPairThatNeedsADownloadIsNeverPrepared() async {
    let spy = Spy()
    spy.availability = .downloadable
    let service = TranslationService(client: spy.client())

    #expect(await service.prewarm(pair) == false)
    #expect(spy.prepareCount == 0)
  }

  @Test func anInstalledPairIsPrepared() async {
    let spy = Spy()
    let service = TranslationService(client: spy.client())

    #expect(await service.prewarm(pair) == true)
    #expect(spy.prepareCount == 1)
  }

  /// The install call presents Apple's sheet and does not return when the
  /// download it started finishes, so availability is polled instead.
  @Test func waitingForAnInstallPollsUntilTheModelLands() async {
    let spy = Spy()
    spy.availability = .downloadable
    spy.installsAfterChecks = 3
    var service = TranslationService(client: spy.client())
    service.installPollInterval = .milliseconds(1)

    #expect(await service.awaitInstall(pair) == true)
    #expect(spy.availabilityCount >= 3)
  }

  @Test func waitingForAnInstallGivesUpOnItsBudget() async {
    let spy = Spy()
    spy.availability = .downloadable
    var service = TranslationService(client: spy.client())
    service.installPollInterval = .milliseconds(1)
    service.installBudget = .milliseconds(10)

    #expect(await service.awaitInstall(pair) == false)
  }

  /// The budget covers the whole finish, not only the translation. Asking
  /// whether a pair is supported is a call that can stall too, and a stall
  /// there used to leave the session unbounded with its HUD already hidden.
  @Test func aStalledAvailabilityProbeStillTimesOut() async {
    let spy = Spy()
    spy.availabilityNeverAnswers = true
    var service = TranslationService(client: spy.client())
    service.timeout = .milliseconds(30)

    await #expect(throws: TranslationFailure.timedOut) {
      _ = try await service.translate("hola", with: pair)
    }
  }

  /// One row per language, but the row must stand for the variant that
  /// actually answered: the preference stores this identifier and the pair is
  /// rebuilt from it, so recording a bare "zh" for an installed "zh-TW" would
  /// advertise a model that is not the one probed.
  @Test func aRowKeepsTheVariantThatAnsweredInstalled() async {
    let spy = Spy()
    spy.candidates = ["zh-TW", "zh-HK"].map { Locale.Language(identifier: $0) }
    spy.perLanguage = ["zh": .installed]
    let service = TranslationService(client: spy.client())

    let targets = await service.targets(from: Locale(identifier: "en_US"))

    #expect(targets.count == 1)
    #expect(targets.first?.id == "zh-TW")
    // Named for the language, not the variant, so one row does not read as a
    // region. Derived rather than written out: the name is localized.
    #expect(targets.first?.name == SpeechLanguageCatalog.shortName(for: Locale(identifier: "zh")))
  }

  /// Among variants that can do the same thing, the plain language wins, so a
  /// stored pick stays "es" rather than drifting to whichever region came back
  /// first.
  @Test func thePlainLanguageWinsOverItsRegionalVariants() async {
    let spy = Spy()
    spy.candidates = ["es-MX", "es", "es-US"].map { Locale.Language(identifier: $0) }
    spy.perLanguage = ["es": .installed]
    let service = TranslationService(client: spy.client())

    let targets = await service.targets(from: Locale(identifier: "en_US"))

    #expect(targets.map(\.id) == ["es"])
  }

  /// The picker's list: installed first because those work now, then
  /// alphabetically so sixteen entries stay scannable.
  @Test func targetsListInstalledFirstThenByName() async {
    let spy = Spy()
    spy.candidates = ["de", "es", "uk", "pl"].map { Locale.Language(identifier: $0) }
    spy.perLanguage = [
      "de": .installed, "es": .installed, "uk": .downloadable, "pl": .downloadable,
    ]
    let service = TranslationService(client: spy.client())

    let targets = await service.targets(from: Locale(identifier: "en_US"))

    // The names are localized, so the order they sort into is computed rather
    // than written out in English.
    let installed = ["de", "es"].sorted(by: byName)
    let downloadable = ["pl", "uk"].sorted(by: byName)
    #expect(targets.map(\.id) == installed + downloadable)
    #expect(targets.first?.availability == .installed)
    #expect(targets.last?.availability == .downloadable)
  }

  /// The order the service sorts by, so these tests hold on a Mac that is not
  /// running in English.
  private func byName(_ first: String, _ second: String) -> Bool {
    let firstName = SpeechLanguageCatalog.shortName(for: Locale(identifier: first))
    let secondName = SpeechLanguageCatalog.shortName(for: Locale(identifier: second))
    return firstName.localizedCaseInsensitiveCompare(secondName) == .orderedAscending
  }

  /// Never offer the source as its own target, and never offer a pair this Mac
  /// cannot do: a listed language that is then refused is worse than absence.
  @Test func theSourceAndUnsupportedPairsAreNotOffered() async {
    let spy = Spy()
    spy.candidates = ["en", "de", "xx"].map { Locale.Language(identifier: $0) }
    spy.perLanguage = ["de": .installed, "xx": .unsupported]
    let service = TranslationService(client: spy.client())

    let targets = await service.targets(from: Locale(identifier: "en_US"))

    #expect(targets.map(\.id) == ["de"])
  }

  /// A language needing a download says so in the picker, rather than looking
  /// identical to one that works and then not working.
  /// The regression: Apple offers regional variants separately, so listing
  /// every candidate gave three Spanishes and three Chineses that all stored
  /// the same value. One row per language.
  @Test func regionalVariantsCollapseToOneRowPerLanguage() async {
    let spy = Spy()
    spy.candidates = ["es-ES", "es-MX", "es-419", "zh-Hans-CN", "zh-Hant-TW", "de-DE"]
      .map { Locale.Language(identifier: $0) }
    spy.availability = .installed
    let service = TranslationService(client: spy.client())

    let targets = await service.targets(from: Locale(identifier: "en_US"))

    #expect(targets.map(\.id) == ["zh", "de", "es"].sorted(by: byName))
    #expect(targets.count == 3)
  }

  /// A language Apple offers both ways is offered as ready, not as a download.
  @Test func installedBeatsDownloadableForTheSameLanguage() async {
    let spy = Spy()
    spy.candidates = ["pt-BR", "pt-PT"].map { Locale.Language(identifier: $0) }
    spy.perLanguage = ["pt": .downloadable]
    let service = TranslationService(client: spy.client())

    var targets = await service.targets(from: Locale(identifier: "en_US"))
    #expect(targets.map(\.availability) == [.downloadable])

    // Now one of the two variants is installed.
    spy.perLanguage = [:]
    spy.availability = .installed
    targets = await service.targets(from: Locale(identifier: "en_US"))
    #expect(targets.map(\.availability) == [.installed])
  }

  @Test func aDownloadableTargetSaysSoInItsLabel() {
    let installed = TranslationTarget(id: "es", name: "Spanish", availability: .installed)
    let downloadable = TranslationTarget(id: "uk", name: "Ukrainian", availability: .downloadable)

    #expect(installed.label == "Spanish")
    #expect(downloadable.label == "Ukrainian — needs a download")
  }

  /// Changing the target has to drop the old pair, or the previous language's
  /// session stays warm and holds a model nothing will ask for again.
  @Test func retainingOnePairPassesThatPairDownToTheClient() async {
    let spy = Spy()
    let service = TranslationService(client: spy.client())

    await service.retain(pair)
    await service.retain(nil)

    #expect(spy.retainedPairs.count == 2)
    #expect(spy.retainedPairs.first == pair)
    #expect(spy.retainedPairs.last == .some(nil))
  }
}

/// The pure values the HUD and the history line share.
struct TranslationLanguageTests {
  @Test func aPairReadsAsItsTwoTags() {
    let pair = TranslationPair(
      source: Locale.Language(identifier: "en"),
      target: Locale.Language(identifier: "es")
    )
    #expect(pair.tag == "EN → ES")
  }

  /// The regression: `.prefix(2)` gave Cantonese the tag "YU", which is not a
  /// language, sitting next to Chinese as "ZH" in the same list.
  @Test func aThreeLetterLanguageKeepsAllThreeLetters() {
    #expect(Locale.Language(identifier: "yue").shortTag == "YUE")
    #expect(Locale.Language(identifier: "en").shortTag == "EN")
    #expect(SpeechLanguageCatalog.tag(for: Locale(identifier: "yue_CN")) == "YUE")
    #expect(SpeechLanguageCatalog.tag(for: Locale(identifier: "de_DE")) == "DE")
  }
}
