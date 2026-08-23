import Foundation
import os
import Testing
@testable import Talkify

@MainActor
struct DictionaryAppleOnlyRegressionTests {
  private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "AppleOnlyRegression-\(UUID().uuidString).txt")
  }

  @Test func appleOnlySettingsHaveNoSpeechModel() {
    #expect(!SettingsSection.allCases.contains { $0.rawValue == "speechModel" })
  }

  @Test func fileFormatPreservesDisabledEntries() async {
    let url = tempURL()
    let store = DictionaryStore(fileURL: url, watchFile: false)
    store.add(.term("Anthropic"))
    store.add(.correction(hear: "cloud code", write: "Claude Code"))
    var disabled = DictionaryEntry.term("OldTerm")
    disabled.isEnabled = false
    store.add(disabled)
    var disabledCorrection = DictionaryEntry.correction(hear: "whisper flow", write: "Wispr Flow")
    disabledCorrection.isEnabled = false
    store.add(disabledCorrection)
    let text = try? String(contentsOf: url, encoding: .utf8)
    #expect(text?.contains("Anthropic") == true)
    #expect(text?.contains("cloud code -> Claude Code") == true)
    #expect(text?.contains("# off: OldTerm") == true)
    #expect(text?.contains("# off: whisper flow -> Wispr Flow") == true)
    let reloaded = DictionaryStore(fileURL: url, watchFile: false)
    #expect(reloaded.entries.count == 4)
    #expect(reloaded.entries.filter(\.isEnabled).count == 2)
  }

  @Test func correctorIsDeterministicAndLongestFirst() {
    let entries = [
      DictionaryEntry.correction(hear: "cloud", write: "Claude"),
      DictionaryEntry.correction(hear: "cloud code", write: "Claude Code"),
    ]
    let corrector = DictionaryCorrector(entries: entries)
    let (first, _) = corrector.apply(to: "please open cloud code")
    let (second, _) = corrector.apply(to: "please open cloud code")
    #expect(first == second)
    #expect(first == "please open Claude Code")
    let (third, applied) = corrector.apply(to: "cloud code and cloud")
    #expect(third == "Claude Code and Claude")
    #expect(applied.count == 2)
  }

  @Test func correctedTextIsInsertedWhileHistoryKeepsRaw() async {
    let recorder = RecordingBridge()
    let history = OSAllocatedUnfairLock<[(text: String, source: String?, folder: URL)]>(initialState: [])
    let rawText = "cloud code"
    let apply: @Sendable (String) -> (corrected: String, applied: [AppliedCorrection], raw: String) = { text in
      let (corrected, applied) = DictionaryCorrector(entries: [
        .correction(hear: "cloud code", write: "Claude Code")
      ]).apply(to: text)
      return (corrected, applied, text)
    }
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let controller = DirectDictationController(
      settings: Self.settingsWithHistoryOn(),
      dependencies: Self.makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        history: history,
        applyDictionary: apply,
        finishText: rawText
      )
    )
    controller.applyLanguages()
    await Self.waitUntil { prewarmed.withLock { $0 } }
    try? await Task.sleep(for: .milliseconds(20))
    controller.toggleFromMenu()
    await Self.waitUntil { controller.sessionStateForTesting == .recording(.latched) }
    controller.toggleFromMenu()
    await Self.waitUntil { !recorder.insertedTexts.isEmpty }
    #expect(recorder.insertedTexts == ["Claude Code"])
    #expect(history.withLock { $0 }.map(\.text) == [rawText])
    controller.stop()
  }

  @Test func biasPhrasesAreForwardedToRecognition() async {
    let captured = OSAllocatedUnfairLock<[[String]]>(initialState: [])
    let recorder = RecordingBridge()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let controller = DirectDictationController(
      settings: AppSettings(defaults: Self.freshDefaults()),
      dependencies: Self.makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        biasPhrases: ["Anthropic", "Claude Code"],
        capturedBias: captured,
        finishText: ""
      )
    )
    controller.applyLanguages()
    await Self.waitUntil { prewarmed.withLock { $0 } }
    try? await Task.sleep(for: .milliseconds(20))
    controller.toggleFromMenu()
    await Self.waitUntil { controller.sessionStateForTesting == .recording(.latched) }
    let biases = captured.withLock { $0 }
    #expect(biases.first == ["Anthropic", "Claude Code"])
    controller.stop()
  }

  @Test func learningIgnoresPunctuationOnlyChange() {
    let entries = DictionaryLearning.learnableEntries(
      rawText: "hello world",
      editedText: "hello, world!"
    )
    #expect(entries.isEmpty)
  }

  @Test func learningDeduplicatesExistingEntries() {
    let existing = [DictionaryEntry.correction(hear: "cloud code", write: "Claude Code")]
    let entries = DictionaryLearning.learnableEntries(
      rawText: "cloud code",
      editedText: "Claude Code",
      existing: existing
    )
    #expect(entries.isEmpty)
  }

  @Test func hudEditPathLearnsCorrection() async {
    let learnCaptured = OSAllocatedUnfairLock<[(String, String, String)]>(initialState: [])
    let recorder = RecordingBridge()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let rawText = "clowd code"
    let controller = DirectDictationController(
      settings: AppSettings(defaults: Self.freshDefaults()),
      dependencies: Self.makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        learnCaptured: learnCaptured,
        finishText: rawText
      )
    )
    controller.applyLanguages()
    await Self.waitUntil { prewarmed.withLock { $0 } }
    try? await Task.sleep(for: .milliseconds(20))
    controller.toggleFromMenu()
    await Self.waitUntil { controller.sessionStateForTesting == .recording(.latched) }
    controller.toggleFromMenu()
    await Self.waitUntil { !recorder.insertedTexts.isEmpty }
    controller.handleHUDDraftEdited("Claude Code")
    let captured = learnCaptured.withLock { $0 }
    #expect(captured.count == 1)
    #expect(captured.first?.0 == rawText)
    #expect(captured.first?.1 == rawText)
    #expect(captured.first?.2 == "Claude Code")
    controller.stop()
  }

  @Test func hudEditViaControllerCallbackLearns() async {
    let learnCaptured = OSAllocatedUnfairLock<[(String, String, String)]>(initialState: [])
    let recorder = RecordingBridge()
    let prewarmed = OSAllocatedUnfairLock<Bool>(initialState: false)
    let stage = HUDStage(settings: AppSettings(defaults: Self.freshDefaults()))
    let hud = DictationHUDController(stage: stage, settings: AppSettings(defaults: Self.freshDefaults()))
    let controller = DirectDictationController(
      settings: AppSettings(defaults: Self.freshDefaults()),
      dependencies: Self.makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        learnCaptured: learnCaptured,
        finishText: "clowd code"
      )
    )
    controller.attachHUD(hud)
    controller.applyLanguages()
    await Self.waitUntil { prewarmed.withLock { $0 } }
    try? await Task.sleep(for: .milliseconds(20))
    controller.toggleFromMenu()
    await Self.waitUntil { controller.sessionStateForTesting == .recording(.latched) }
    controller.toggleFromMenu()
    await Self.waitUntil { !recorder.insertedTexts.isEmpty }
    hud.commitEditedDraft("Claude Code")
    let direct = learnCaptured.withLock { $0 }
    #expect(direct.count == 1)
    #expect(direct.first?.2 == "Claude Code")
    controller.stop()
  }

  // Helpers

  @MainActor
  private final class RecordingBridge {
    var insertedTexts: [String] = []
    var events: [String] = []
  }

  private static func freshDefaults() -> UserDefaults {
    let name = "AppleOnlyRegression-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  private static func settingsWithHistoryOn() -> AppSettings {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    settings.dictationHistoryEnabled = true
    settings.dictationHistoryFolder = URL(filePath: "/tmp/TalkifyTests-history-\(UUID().uuidString)")
    return settings
  }

  private static func makeDependencies(
    recorder: RecordingBridge,
    prewarmed: OSAllocatedUnfairLock<Bool>,
    history: OSAllocatedUnfairLock<[(text: String, source: String?, folder: URL)]> = .init(initialState: []),
    biasPhrases: [String] = [],
    capturedBias: OSAllocatedUnfairLock<[[String]]>? = nil,
    applyDictionary: (@Sendable (String) -> (corrected: String, applied: [AppliedCorrection], raw: String))? = nil,
    learnCaptured: OSAllocatedUnfairLock<[(String, String, String)]>? = nil,
    finishText: String
  ) -> DirectDictationController.Dependencies {
    DirectDictationController.Dependencies(
      setDownloadHandler: { _ in },
      resolveLocale: { _ in Locale(identifier: "en_US") },
      supportedLocale: { _ in nil },
      retainOnly: { _ in },
      prewarm: { _ in prewarmed.withLock { $0 = true } },
      startRecognition: { _, phrases, _, _, _ in
        if let capturedBias { capturedBias.withLock { $0.append(phrases) } }
      },
      finishRecognition: { finishText },
      cancelRecognition: {},
      shutDownRecognition: {},
      dictionaryBiasPhrases: { biasPhrases },
      applyDictionary: { text in
        if let applyDictionary { return applyDictionary(text) }
        return (text, [], text)
      },
      learnFromEdit: { raw, corrected, edited in
        learnCaptured?.withLock { $0.append((raw, corrected, edited)) }
      },
      captureFocusedTarget: {
        TextInsertionService.Target(
          element: nil,
          processIdentifier: 1,
          isSecure: false,
          displayID: nil,
          applicationName: nil
        )
      },
      insertText: { text, _, _ in
        recorder.insertedTexts.append(text)
        return .inserted
      },
      requestMicrophoneAccess: { true },
      requestSpeechAccess: { true },
      requestAccessibilityAccess: {},
      hasAccessibilityAccess: { true },
      isPermissionAlertPresenting: { false },
      showAccessibilitySetupAlert: {},
      showRelaunchAlert: {},
      showListening: { _, _, _, _ in },
      showLatched: {},
      showLiveText: { _ in },
      showFinalizing: {},
      showMessage: { _, _ in },
      showModelDownload: { _ in },
      showAudioLevel: { _ in },
      hideHUD: { recorder.events.append("hideHUD") },
      playPasteSound: {},
      recordSession: { _, _ in },
      recordHistory: { text, source, folder in
        history.withLock { $0.append((text, source, folder)) }
      }
    )
  }

  private static func waitUntil(
    _ condition: @MainActor () -> Bool
  ) async {
    for _ in 0..<200 {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }
}
