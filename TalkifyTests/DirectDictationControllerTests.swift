import Foundation
import Testing
@testable import Talkify

/// The controller's language preparation, driven through the speech seam.
///
/// The rules under test are ones the controller states in comments and nothing
/// pinned: which locales stay reserved, that the primary is warmed, and that a
/// second language that cannot be warmed does not take the first down with it.
@MainActor
struct DirectDictationControllerTests {
  /// Records what the controller asked for, and can be told to fail on cue.
  private actor SpyRecognizer: SpeechRecognizing {
    enum Call: Equatable {
      case resolveLocale(String?)
      case supportedLocale(String)
      case prewarm(String)
      case retainOnly([String])
      case cancel
      case shutDown
    }

    private(set) var calls: [Call] = []
    private var resolved: Locale
    private var supported: Locale?
    private var prewarmFailures: Set<String>

    init(
      resolved: Locale = Locale(identifier: "en_US"),
      supported: Locale? = nil,
      prewarmFailures: Set<String> = []
    ) {
      self.resolved = resolved
      self.supported = supported
      self.prewarmFailures = prewarmFailures
    }

    struct Failure: Error {}

    func setDownloadHandler(
      _ handler: @escaping @Sendable (SpeechRecognitionService.ModelDownload) -> Void
    ) {}

    func resolveLocale(identifier: String?) async throws -> Locale {
      calls.append(.resolveLocale(identifier))
      return resolved
    }

    func supportedLocale(identifier: String) async -> Locale? {
      calls.append(.supportedLocale(identifier))
      return supported
    }

    func prewarm(locale: Locale) async throws {
      calls.append(.prewarm(locale.identifier))
      if prewarmFailures.contains(locale.identifier) { throw Failure() }
    }

    func retainOnly(locales: [Locale]) async {
      calls.append(.retainOnly(locales.map(\.identifier)))
    }

    func start(
      locale: Locale,
      updateHandler: @escaping @Sendable (SpeechRecognitionService.Update) -> Void,
      failureHandler: @escaping @Sendable (String) -> Void,
      levelHandler: (@Sendable (Float) -> Void)?
    ) async throws {}

    func finish() async throws -> String { "" }
    func cancel() async { calls.append(.cancel) }
    func shutDown() async { calls.append(.shutDown) }

    /// Waits for a call to arrive rather than for a fixed time. A sleep long
    /// enough to pass alone is not long enough under a loaded runner, and the
    /// suite already has a history of tests that measured the machine.
    func wait(for call: Call, within timeout: Duration = .seconds(5)) async -> Bool {
      let deadline = ContinuousClock().now + timeout
      while ContinuousClock().now < deadline {
        if calls.contains(call) { return true }
        try? await Task.sleep(for: .milliseconds(5))
      }
      return calls.contains(call)
    }
  }

  private func makeSettings() -> AppSettings {
    let name = "DirectDictationControllerTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return AppSettings(defaults: defaults)
  }

  private func makeController(
    settings: AppSettings,
    speech: SpyRecognizer
  ) -> DirectDictationController {
    let stage = HUDStage(settings: settings)
    return DirectDictationController(
      settings: settings,
      hudController: DictationHUDController(stage: stage, settings: settings),
      usageTracker: UsageTracker(
        store: UsageStore(
          fileURL: URL.temporaryDirectory
            .appending(path: "TalkifyTests-usage-\(UUID().uuidString).json")
        )
      ),
      speechService: speech
    )
  }

  /// Only the languages actually bound to a key stay reserved. Anything else
  /// holds a model reservation nothing can reach.
  @Test func onlyBoundLanguagesStayReserved() async {
    let settings = makeSettings()
    let speech = SpyRecognizer(
      resolved: Locale(identifier: "en_US"),
      supported: Locale(identifier: "de_DE")
    )
    settings.secondaryRecognitionLocaleIdentifier = "de_DE"
    let controller = makeController(settings: settings, speech: speech)

    controller.applyLanguages()

    #expect(await speech.wait(for: .retainOnly(["en_US", "de_DE"])))
    #expect(await speech.wait(for: .prewarm("en_US")))
    #expect(await speech.wait(for: .prewarm("de_DE")))
  }

  /// With no second language chosen, the second slot is never resolved and
  /// never reserved.
  @Test func oneLanguageReservesOnlyItself() async {
    let settings = makeSettings()
    let speech = SpyRecognizer(resolved: Locale(identifier: "en_US"))
    let controller = makeController(settings: settings, speech: speech)

    controller.applyLanguages()

    #expect(await speech.wait(for: .retainOnly(["en_US"])))
    let calls = await speech.calls
    #expect(!calls.contains { if case .supportedLocale = $0 { true } else { false } })
  }

  /// The documented rule: a second language whose model still needs
  /// downloading must not delay or fail the primary key.
  @Test func aSecondLanguageThatCannotWarmDoesNotTakeTheFirstDown() async {
    let settings = makeSettings()
    let speech = SpyRecognizer(
      resolved: Locale(identifier: "en_US"),
      supported: Locale(identifier: "de_DE"),
      prewarmFailures: ["de_DE"]
    )
    settings.secondaryRecognitionLocaleIdentifier = "de_DE"
    let controller = makeController(settings: settings, speech: speech)

    controller.applyLanguages()

    #expect(await speech.wait(for: .prewarm("en_US")))
    #expect(await speech.wait(for: .prewarm("de_DE")))
  }

  /// A second language equal to the first is not a second language: it would
  /// put one language behind two keys and reserve it twice.
  @Test func aSecondLanguageEqualToTheFirstIsDropped() async {
    let settings = makeSettings()
    let speech = SpyRecognizer(
      resolved: Locale(identifier: "en_US"),
      supported: Locale(identifier: "en_US")
    )
    settings.secondaryRecognitionLocaleIdentifier = "en_US"
    let controller = makeController(settings: settings, speech: speech)

    controller.applyLanguages()

    #expect(await speech.wait(for: .retainOnly(["en_US"])))
  }

  /// Teardown shuts the speech service down rather than leaving an analyzer
  /// holding the microphone.
  @Test func stoppingShutsTheSpeechServiceDown() async {
    let settings = makeSettings()
    let speech = SpyRecognizer()
    let controller = makeController(settings: settings, speech: speech)

    controller.stop()

    #expect(await speech.wait(for: .shutDown))
  }
}
