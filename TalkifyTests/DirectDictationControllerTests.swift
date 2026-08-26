import Foundation
import os
import Testing
@testable import Talkify

/// Pins the controller's impure half through its Dependencies seam: the
/// begin guards, the finish outcome routing, and the cancellation races
/// that the pure machine tests cannot reach.
@MainActor
struct DirectDictationControllerTests {
  /// Every MainActor boundary call the controller makes, in order, plus
  /// the arguments the routing decisions carry.
  /// One history write, as the dependency saw it.
  private struct HistoryEntry: Sendable {
    let text: String
    let translation: DictationHistoryStore.Translation?
    let source: String?
    let folder: URL
  }

  @MainActor
  private final class Recorder {
    var events: [String] = []
    var messages: [String] = []
    var listeningLatched: [Bool] = []
    var listeningTags: [String?] = []
    var insertedTexts: [String] = []
    var insertedDestinations: [InsertionDestination] = []
    var recordedSessions: [(wordCount: Int, speakingDuration: TimeInterval)] = []
    var accessibilityAlerts = 0

    func count(of event: String) -> Int {
      events.filter { $0 == event }.count
    }
  }

  private struct FinishError: LocalizedError {
    var errorDescription: String? { "finish failed" }
  }

  private func freshDefaults() -> UserDefaults {
    let name = "DirectDictationControllerTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  private static func makeTarget(
    isSecure: Bool = false,
    applicationName: String? = nil
  ) -> TextInsertionService.Target {
    TextInsertionService.Target(
      element: nil,
      processIdentifier: 1,
      isSecure: isSecure,
      displayID: nil,
      applicationName: applicationName
    )
  }

  /// Builds fake dependencies around the recorder. The Sendable speech
  /// closures report through lock-guarded counters because they cannot
  /// touch the MainActor recorder synchronously.
  private func makeDependencies(
    recorder: Recorder,
    prewarmed: OSAllocatedUnfairLock<Bool> = .init(initialState: false),
    startEntries: OSAllocatedUnfairLock<Int> = .init(initialState: 0),
    cancelCount: OSAllocatedUnfairLock<Int> = .init(initialState: 0),
    hasAccessibilityAccess: @escaping @MainActor () -> Bool = { true },
    captureFocusedTarget: @escaping @MainActor () -> TextInsertionService.Target?
      = { DirectDictationControllerTests.makeTarget() },
    startRecognitionBody: (@Sendable (Locale) async throws -> Void)? = nil,
    finishRecognition: @escaping @Sendable () async throws -> String = { "" },
    shutDownRecognition: @escaping @Sendable () async -> Void = {},
    historyEntries: OSAllocatedUnfairLock<[HistoryEntry]>
      = .init(initialState: []),
    translationAvailability: TranslationAvailability = .installed,
    translationReady: Bool = true,
    translationPrepareHangs: Bool = false,
    translateBody: (@Sendable (String) async throws -> String)? = nil,
    retainedPairs: OSAllocatedUnfairLock<[TranslationPair?]> = .init(initialState: []),
    insertOutcome: TextInsertionService.InsertionOutcome = .inserted
  ) -> DirectDictationController.Dependencies {
    DirectDictationController.Dependencies(
      setDownloadHandler: { _ in },
      resolveLocale: { _ in Locale(identifier: "en_US") },
      supportedLocale: { _ in nil },
      retainOnly: { _ in },
      prewarm: { _ in prewarmed.withLock { $0 = true } },
      startRecognition: { locale, _, _, _ in
        startEntries.withLock { $0 += 1 }
        try await startRecognitionBody?(locale)
      },
      finishRecognition: finishRecognition,
      cancelRecognition: { cancelCount.withLock { $0 += 1 } },
      shutDownRecognition: shutDownRecognition,
      // The real service over a faked framework, rather than a second set of
      // stubs: its rules are the ones a session depends on.
      translation: TranslationCoordinator(
        service: TranslationService(
          client: TranslationService.Client(
            availability: { _ in translationAvailability },
            prepare: { _ in
              if translationPrepareHangs { try await Task.sleep(for: .seconds(3600)) }
              guard translationReady else { throw TranslationFailure.unsupported }
            },
            translate: { _, text in
              if let translateBody { return try await translateBody(text) }
              return "translated: \(text)"
            },
            candidateTargets: { [] },
            retain: { pair in retainedPairs.withLock { $0.append(pair) } },
            shutDown: {}
          )
        )
      ),
      captureFocusedTarget: captureFocusedTarget,
      insertText: { text, _, destination in
        recorder.events.append("insertText")
        recorder.insertedTexts.append(text)
        recorder.insertedDestinations.append(destination)
        return insertOutcome
      },
      requestMicrophoneAccess: { true },
      requestSpeechAccess: { true },
      requestAccessibilityAccess: {},
      hasAccessibilityAccess: hasAccessibilityAccess,
      isPermissionAlertPresenting: { false },
      showAccessibilitySetupAlert: {
        recorder.events.append("showAccessibilitySetupAlert")
        recorder.accessibilityAlerts += 1
      },
      showRelaunchAlert: { recorder.events.append("showRelaunchAlert") },
      showListening: { _, isLatched, _, languageTag in
        recorder.events.append("showListening")
        recorder.listeningLatched.append(isLatched)
        recorder.listeningTags.append(languageTag)
      },
      showLatched: { recorder.events.append("showLatched") },
      showLiveText: { _ in recorder.events.append("showLiveText") },
      showFinalizing: { recorder.events.append("showFinalizing") },
      showMessage: { message, _ in
        recorder.events.append("showMessage")
        recorder.messages.append(message)
      },
      showModelDownload: { _ in },
      showAudioLevel: { _ in },
      hideHUD: { recorder.events.append("hideHUD") },
      playPasteSound: { recorder.events.append("playPasteSound") },
      recordSession: { wordCount, speakingDuration in
        recorder.events.append("recordSession")
        recorder.recordedSessions.append((wordCount, speakingDuration))
      },
      recordHistory: { text, translation, source, folder in
        historyEntries.withLock {
          $0.append(HistoryEntry(text: text, translation: translation, source: source, folder: folder))
        }
      }
    )
  }

  private func makeController(
    settings: AppSettings? = nil,
    dependencies: DirectDictationController.Dependencies
  ) -> DirectDictationController {
    DirectDictationController(
      settings: settings ?? AppSettings(defaults: freshDefaults()),
      dependencies: dependencies
    )
  }

  /// Polls the condition until it holds, or records a failure after ~1 s.
  /// The sleeps yield the main actor so the controller's tasks can run.
  private func waitUntil(
    _ comment: Comment,
    _ condition: @MainActor () -> Bool
  ) async {
    for _ in 0..<200 {
      if condition() { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record(comment)
  }

  /// Prepares the controller through applyLanguages, then lets the
  /// preparation task run to completion past the prewarm it signals.
  private func prepare(
    _ controller: DirectDictationController,
    prewarmed: OSAllocatedUnfairLock<Bool>
  ) async {
    controller.applyLanguages()
    await waitUntil("Preparation never reached prewarm") {
      prewarmed.withLock { $0 }
    }
    // Wait for the state, not for a duration: preparation resolves and warms
    // a translation pair after the speech prewarm, and a fixed sleep that is
    // long enough on an idle machine is not long enough on a loaded one.
    await waitUntil("Preparation never finished") { controller.isPreparedForTesting }
  }

  /// Prepares, and waits for the translation pair to be ready too.
  private func prepareWithTranslation(
    _ controller: DirectDictationController,
    prewarmed: OSAllocatedUnfairLock<Bool>
  ) async {
    await prepare(controller, prewarmed: prewarmed)
    await waitUntil("Translation never became ready") {
      controller.isTranslationReadyForTesting
    }
  }

  @Test func triggerBeforePreparationShowsPreparingAndStaysIdle() {
    let recorder = Recorder()
    let startEntries = OSAllocatedUnfairLock(initialState: 0)
    let controller = makeController(
      dependencies: makeDependencies(recorder: recorder, startEntries: startEntries)
    )

    controller.handle(.triggerPressed(.primary))

    #expect(controller.sessionStateForTesting == .idle)
    #expect(recorder.messages == ["Preparing speech…"])
    #expect(startEntries.withLock { $0 } == 0)
  }

  @Test func missingAccessibilityAccessShowsSetupAlertAndStaysIdle() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        hasAccessibilityAccess: { false }
      )
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.toggleFromMenu()

    #expect(controller.sessionStateForTesting == .idle)
    #expect(recorder.accessibilityAlerts == 1)
    controller.stop()
  }

  @Test func secureFocusedFieldShowsSecureFieldAndStaysIdle() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        captureFocusedTarget: { Self.makeTarget(isSecure: true) }
      )
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.toggleFromMenu()

    #expect(controller.sessionStateForTesting == .idle)
    #expect(recorder.messages == ["Secure field"])
    controller.stop()
  }

  @Test func approvedMenuToggleBeginsALatchedRecording() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let controller = makeController(
      dependencies: makeDependencies(recorder: recorder, prewarmed: prewarmed)
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }

    #expect(recorder.listeningLatched == [true])
    controller.stop()
  }

  @Test func insertedFinishPlaysPasteSoundAndRecordsUsage() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "hello world" }
      )
    )
    await prepare(controller, prewarmed: prewarmed)
    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }

    controller.toggleFromMenu()
    await waitUntil("Usage was never recorded") {
      recorder.recordedSessions.count == 1
    }

    #expect(controller.sessionStateForTesting == .idle)
    #expect(recorder.insertedTexts == ["hello world"])
    #expect(recorder.recordedSessions.first?.wordCount == 2)
    #expect((recorder.recordedSessions.first?.speakingDuration ?? -1) >= 0)
    let hideIndex = recorder.events.firstIndex(of: "hideHUD")
    let soundIndex = recorder.events.firstIndex(of: "playPasteSound")
    #expect(hideIndex != nil && soundIndex != nil)
    if let hideIndex, let soundIndex {
      #expect(hideIndex < soundIndex)
    }
    controller.stop()
  }

  @Test func enabledFillerWordFilteringRemovesFillersBeforeInsertion() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "Uhmm, write the note mhmm" }
      )
    )
    await prepare(controller, prewarmed: prewarmed)
    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }

    controller.toggleFromMenu()
    await waitUntil("Finish never delivered") { !recorder.insertedTexts.isEmpty }

    #expect(recorder.insertedTexts == ["Write the note"])
    controller.stop()
  }

  @Test func disabledFillerWordFilteringPreservesRecognizedText() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    settings.fillerWordFilteringEnabled = false
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "Uhmm, write the note" }
      )
    )
    await prepare(controller, prewarmed: prewarmed)
    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }

    controller.toggleFromMenu()
    await waitUntil("Finish never delivered") { !recorder.insertedTexts.isEmpty }

    #expect(recorder.insertedTexts == ["Uhmm, write the note"])
    controller.stop()
  }

  @Test func clipboardFallbackStillPlaysPasteSoundAndRecordsUsage() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "hello world" },
        insertOutcome: .copiedToClipboard
      )
    )
    await prepare(controller, prewarmed: prewarmed)
    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }

    controller.toggleFromMenu()
    await waitUntil("Usage was never recorded") {
      recorder.recordedSessions.count == 1
    }

    #expect(controller.sessionStateForTesting == .idle)
    #expect(recorder.count(of: "playPasteSound") == 1)
    controller.stop()
  }

  @Test func unavailableInsertionShowsMessageWithoutSoundOrUsage() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "hello world" },
        insertOutcome: .unavailable
      )
    )
    await prepare(controller, prewarmed: prewarmed)
    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }

    controller.toggleFromMenu()
    await waitUntil("Insertion failure message never shown") {
      recorder.messages.contains("Couldn't insert text")
    }

    #expect(controller.sessionStateForTesting == .idle)
    #expect(recorder.count(of: "playPasteSound") == 0)
    #expect(recorder.recordedSessions.isEmpty)
    controller.stop()
  }

  @Test func finishFailureShowsTheErrorAndInsertsNothing() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { throw FinishError() }
      )
    )
    await prepare(controller, prewarmed: prewarmed)
    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }

    controller.toggleFromMenu()
    await waitUntil("Finish failure message never shown") {
      recorder.messages.contains("finish failed")
    }

    #expect(controller.sessionStateForTesting == .idle)
    #expect(recorder.insertedTexts.isEmpty)
    controller.stop()
  }

  @Test func escapeWhileStartingHidesTheHUDAndInsertsNothing() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let startEntries = OSAllocatedUnfairLock(initialState: 0)
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        startEntries: startEntries,
        startRecognitionBody: { _ in
          // Held open until the controller cancels the start task; the
          // CancellationError propagates as the torn-down start.
          try await Task.sleep(for: .seconds(10))
        }
      )
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.toggleFromMenu()
    await waitUntil("Recognition start was never entered") {
      startEntries.withLock { $0 } >= 1
    }
    controller.handle(.cancelPressed)
    await waitUntil("Cancelled start never reset to idle") {
      controller.sessionStateForTesting == .idle
    }

    #expect(recorder.count(of: "hideHUD") == 1)
    #expect(recorder.insertedTexts.isEmpty)
    controller.stop()
  }

  @Test func escapeWhileRecordingCancelsRecognitionAndHidesTheHUD() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let cancelCount = OSAllocatedUnfairLock(initialState: 0)
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        cancelCount: cancelCount
      )
    )
    await prepare(controller, prewarmed: prewarmed)
    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }

    controller.handle(.cancelPressed)
    await waitUntil("Cancelled recording never reset to idle") {
      controller.sessionStateForTesting == .idle
    }

    #expect(cancelCount.withLock { $0 } >= 1)
    #expect(recorder.count(of: "hideHUD") == 1)
    #expect(recorder.insertedTexts.isEmpty)
    controller.stop()
  }

  @Test func emptyFinishTextStillRecordsAZeroWordSession() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "" }
      )
    )
    await prepare(controller, prewarmed: prewarmed)
    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }

    controller.toggleFromMenu()
    await waitUntil("Usage was never recorded") {
      recorder.recordedSessions.count == 1
    }

    #expect(controller.sessionStateForTesting == .idle)
    #expect(recorder.insertedTexts == [""])
    #expect(recorder.recordedSessions.first?.wordCount == 0)
    controller.stop()
  }

  /// stop() during an in-flight finish must wait for the finish before
  /// shutting the speech service down: shutting down beside it made a
  /// scheduler race decide whether the last words were inserted or dropped.
  @Test func stopDuringFinishInsertsTheTextBeforeShutDown() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let order = OSAllocatedUnfairLock<[String]>(initialState: [])
    let finishEntered = OSAllocatedUnfairLock(initialState: false)
    let finishReleased = OSAllocatedUnfairLock(initialState: false)
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: {
          finishEntered.withLock { $0 = true }
          while !finishReleased.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(5))
          }
          order.withLock { $0.append("finish") }
          return "held words"
        },
        shutDownRecognition: { order.withLock { $0.append("shutDown") } }
      )
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.toggleFromMenu()
    await waitUntil("Finish never began") { finishEntered.withLock { $0 } }

    controller.stop()
    finishReleased.withLock { $0 = true }
    await waitUntil("Shut down never ran") {
      order.withLock { $0.contains("shutDown") }
    }

    #expect(recorder.insertedTexts == ["held words"])
    #expect(order.withLock { $0 } == ["finish", "shutDown"])
  }

  /// The destination rides in the session snapshot: a Settings change made
  /// mid-session must not redirect the finish already under way.
  @Test func finishDeliversWithTheDestinationCapturedAtSessionStart() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    settings.insertionDestination = .clipboardOnly
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "captured words" }
      )
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    settings.insertionDestination = .both
    controller.toggleFromMenu()
    await waitUntil("Finish never delivered") {
      controller.sessionStateForTesting == .idle && !recorder.insertedTexts.isEmpty
    }

    #expect(recorder.insertedDestinations == [.clipboardOnly])
    controller.stop()
  }

  /// History off — the default — writes nothing, whatever the session says.
  @Test func finishWritesNoHistoryWhileTheSettingIsOff() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let historyEntries = OSAllocatedUnfairLock<[HistoryEntry]>(
      initialState: []
    )
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "spoken words" },
        historyEntries: historyEntries
      )
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.toggleFromMenu()
    await waitUntil("Finish never delivered") { !recorder.insertedTexts.isEmpty }

    #expect(historyEntries.withLock { $0 }.isEmpty)
    controller.stop()
  }

  /// History on writes the finished text to the session's captured folder,
  /// before the insertion outcome can lose it.
  @Test func finishWritesHistoryToTheCapturedFolderWhileOn() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let historyEntries = OSAllocatedUnfairLock<[HistoryEntry]>(
      initialState: []
    )
    let folder = URL(filePath: "/tmp/TalkifyTests-history-\(UUID().uuidString)")
    let settings = AppSettings(defaults: freshDefaults())
    settings.dictationHistoryEnabled = true
    settings.dictationHistoryFolder = folder
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "spoken words" },
        historyEntries: historyEntries,
        insertOutcome: .unavailable
      )
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.toggleFromMenu()
    await waitUntil("Finish never delivered") { !recorder.insertedTexts.isEmpty }

    let entries = historyEntries.withLock { $0 }
    #expect(entries.map(\.text) == ["spoken words"])
    #expect(entries.map(\.folder) == [folder])
    controller.stop()
  }

  /// The feature: a translate session inserts the translation, not the words.
  /// The target is the one thing the user cannot check anywhere else before
  /// speaking, and a wrong one only shows up after the text lands. With a
  /// single dictation language the HUD used to name nothing at all.
  @Test func aTranslateSessionNamesThePairInTheHUD() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(recorder: recorder, prewarmed: prewarmed)
    )
    await prepareWithTranslation(controller, prewarmed: prewarmed)

    controller.handle(.triggerPressed(.translate))
    await waitUntil("Never showed listening") {
      recorder.events.contains("showListening")
    }

    #expect(recorder.listeningTags == ["EN → ES"])
  }

  /// A plain session in the only configured language names nothing: there is
  /// no second language to tell it apart from.
  @Test func aPlainSingleLanguageSessionNamesNothing() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let controller = makeController(
      dependencies: makeDependencies(recorder: recorder, prewarmed: prewarmed)
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.handle(.triggerPressed(.primary))
    await waitUntil("Never showed listening") {
      recorder.events.contains("showListening")
    }

    #expect(recorder.listeningTags == [nil])
  }

  @Test func aTranslateSessionInsertsTheTranslationRatherThanWhatWasSpoken() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "spoken words" }
      )
    )
    await prepareWithTranslation(controller, prewarmed: prewarmed)

    // Press and release with no wait is a quick tap, which latches; the next
    // press is what finishes. Latching rather than sleeping past the 250ms
    // hold threshold keeps this test off the clock.
    controller.handle(.triggerPressed(.translate))
    controller.handle(.triggerReleased(.translate))
    await waitUntil("Session never latched") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.handle(.triggerPressed(.translate))
    await waitUntil("Finish never delivered") { !recorder.insertedTexts.isEmpty }

    #expect(recorder.insertedTexts == ["translated: spoken words"])
    controller.stop()
  }

  /// A translation model that will not load must not hold plain dictation
  /// behind it. Preparation returning is what installs the event tap, so
  /// awaiting the model there disables the key the user actually pressed.
  @Test func aHangingTranslationModelStillLeavesDictationPrepared() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        translationPrepareHangs: true
      )
    )

    controller.applyLanguages()
    await waitUntil("Never prepared") { controller.isPreparedForTesting }

    #expect(!controller.isTranslationReadyForTesting)
    controller.stop()
  }

  /// A menu-started session owns the primary key, whatever the last session
  /// owned. Without that, a rebind during it pins the tap to a key the user
  /// cannot press while refusing the one they can.
  @Test func aMenuStartedSessionOwnsThePrimaryKey() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(recorder: recorder, prewarmed: prewarmed)
    )
    await prepareWithTranslation(controller, prewarmed: prewarmed)

    // A translate session first, so a stale binding exists to inherit.
    controller.handle(.triggerPressed(.translate))
    controller.handle(.triggerReleased(.translate))
    await waitUntil("Session never latched") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    #expect(controller.activeBindingForTesting == settings.translateTriggerBinding)
    controller.handle(.triggerPressed(.translate))
    await waitUntil("Session never ended") {
      controller.sessionStateForTesting == .idle
    }

    controller.toggleFromMenu()

    #expect(controller.activeBindingForTesting == settings.dictationTriggerBinding)
    controller.stop()
  }

  /// Changing a language drops the old pair before the reload is even
  /// scheduled. A translate key already queued on this actor would otherwise
  /// find the old pair ready and snapshot it, and insert the language the user
  /// just stopped choosing (ADR-0004).
  @Test func changingLanguagesDropsTheOldPairAtOnce() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(recorder: recorder, prewarmed: prewarmed)
    )
    await prepareWithTranslation(controller, prewarmed: prewarmed)
    #expect(controller.isTranslationReadyForTesting)

    // Synchronous: nothing is awaited between here and the assertion, so the
    // reload's own task cannot have run yet.
    controller.applyLanguages()

    #expect(!controller.isTranslationReadyForTesting)
    controller.stop()
  }

  /// A session keeps the key it started with. Rebinding mid-gesture would
  /// otherwise take that key away and the release would land on nothing: the
  /// session records until Escape (CONTEXT.md).
  @Test func aSessionsSlotKeepsTheKeyItStartedWith() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    let started = settings.translateTriggerBinding
    settings.translateTriggerBinding = .optionEscape

    let bindings = DirectDictationController.triggerBindings(
      settings: settings,
      sessionSlot: .translate,
      sessionBinding: started
    )

    #expect(bindings.translate == started)
    // Only the busy slot is pinned; the rest follow the preferences.
    #expect(bindings.trigger == settings.dictationTriggerBinding)
  }

  /// Turning a language off mid-session cannot take its key either.
  @Test func aSessionsSlotSurvivesItsLanguageBeingTurnedOff() {
    let settings = AppSettings(defaults: freshDefaults())
    let started = settings.translateTriggerBinding

    let bindings = DirectDictationController.triggerBindings(
      settings: settings,
      sessionSlot: .translate,
      sessionBinding: started
    )

    #expect(!settings.isTranslationEnabled)
    #expect(bindings.translate == started)
  }

  /// With no session, every slot follows the preferences, and a slot with no
  /// language is not installed at all.
  @Test func anIdleTapFollowsThePreferences() {
    let settings = AppSettings(defaults: freshDefaults())

    let bindings = DirectDictationController.triggerBindings(
      settings: settings,
      sessionSlot: nil,
      sessionBinding: nil
    )

    #expect(bindings.trigger == settings.dictationTriggerBinding)
    #expect(bindings.secondary == nil)
    #expect(bindings.translate == nil)
  }

  /// The clipboard rescue can be refused too, while a read holds its lease.
  /// Saying only that the translation failed would promise words that are not
  /// anywhere the user can reach.
  @Test func aTranslationFailureSaysSoWhenTheClipboardRefusesAsWell() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "spoken words" },
        translateBody: { _ in throw TranslationFailure.timedOut },
        insertOutcome: .unavailable
      )
    )
    await prepareWithTranslation(controller, prewarmed: prewarmed)

    controller.handle(.triggerPressed(.translate))
    controller.handle(.triggerReleased(.translate))
    await waitUntil("Session never latched") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.handle(.triggerPressed(.translate))
    await waitUntil("Never reported") {
      recorder.messages.contains { $0.hasPrefix("Couldn't translate") }
    }

    #expect(recorder.messages.contains("Couldn't translate or copy"))
    controller.stop()
  }

  /// Insights counts the words that were spoken. Speaking duration is measured
  /// on the source side, so counting a translation's words against it would
  /// divide one language's count by another's minutes.
  @Test func aTranslatedSessionCountsTheWordsThatWereSpoken() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "one two three" },
        // Six words out for three words in, which is the whole point.
        translateBody: { _ in "uno dos tres cuatro cinco seis" }
      )
    )
    await prepareWithTranslation(controller, prewarmed: prewarmed)

    controller.handle(.triggerPressed(.translate))
    controller.handle(.triggerReleased(.translate))
    await waitUntil("Session never latched") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.handle(.triggerPressed(.translate))
    await waitUntil("Never recorded") { !recorder.recordedSessions.isEmpty }

    #expect(recorder.recordedSessions.map(\.0) == [3])
    controller.stop()
  }

  /// A translation that comes back unchanged still ran, so the entry still
  /// names both languages. Names, URLs and numbers translate to themselves.
  @Test func anUnchangedTranslationStillLabelsBothLanguages() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let historyEntries = OSAllocatedUnfairLock<[HistoryEntry]>(initialState: [])
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    settings.dictationHistoryEnabled = true
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "Talkify" },
        historyEntries: historyEntries,
        translateBody: { $0 }
      )
    )
    await prepareWithTranslation(controller, prewarmed: prewarmed)

    controller.handle(.triggerPressed(.translate))
    controller.handle(.triggerReleased(.translate))
    await waitUntil("Session never latched") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.handle(.triggerPressed(.translate))
    await waitUntil("Finish never delivered") { !recorder.insertedTexts.isEmpty }

    let entries = historyEntries.withLock { $0 }
    #expect(entries.first?.translation?.spokenTag == "EN")
    #expect(entries.first?.translation?.text == "Talkify")
    controller.stop()
  }

  /// History keeps what was said, not only what was delivered: a failed
  /// insertion must not be able to lose the spoken half (ADR-0007), and it is
  /// the only half that cannot be produced again.
  @Test func aTranslatedSessionRecordsTheSpokenWordsAndTheTranslation() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let historyEntries = OSAllocatedUnfairLock<[HistoryEntry]>(initialState: [])
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    settings.dictationHistoryEnabled = true
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "spoken words" },
        historyEntries: historyEntries
      )
    )
    await prepareWithTranslation(controller, prewarmed: prewarmed)

    controller.handle(.triggerPressed(.translate))
    controller.handle(.triggerReleased(.translate))
    await waitUntil("Session never latched") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.handle(.triggerPressed(.translate))
    await waitUntil("Finish never delivered") { !recorder.insertedTexts.isEmpty }

    let entries = historyEntries.withLock { $0 }
    #expect(entries.map(\.text) == ["spoken words"])
    #expect(entries.first?.translation?.text == "translated: spoken words")
    #expect(entries.first?.translation?.spokenTag == "EN")
    #expect(entries.first?.translation?.deliveredTag == "ES")
    controller.stop()
  }

  /// A failed translation delivers nothing and rescues the words to the
  /// clipboard: the wrong language in someone else's document is worse than a
  /// paste the user has to make themselves.
  @Test func aFailedTranslationInsertsNothingAndCopiesWhatWasSpoken() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "spoken words" },
        translateBody: { _ in throw TranslationFailure.timedOut }
      )
    )
    await prepareWithTranslation(controller, prewarmed: prewarmed)

    controller.handle(.triggerPressed(.translate))
    controller.handle(.triggerReleased(.translate))
    await waitUntil("Session never latched") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.handle(.triggerPressed(.translate))
    await waitUntil("Rescue never happened") { !recorder.insertedTexts.isEmpty }

    #expect(recorder.insertedTexts == ["spoken words"])
    #expect(recorder.insertedDestinations == [.clipboardOnly])
    #expect(recorder.messages.contains("Couldn't translate"))
    // A rescue is not a delivery.
    #expect(recorder.count(of: "playPasteSound") == 0)
    #expect(recorder.recordedSessions.isEmpty)
    controller.stop()
  }

  /// The trap: routing the failure through fail() would drive the machine to
  /// cancelling and cancel a session that has already finished.
  @Test func aFailedTranslationEndsTheSessionRatherThanCancellingIt() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let cancelCount = OSAllocatedUnfairLock(initialState: 0)
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        cancelCount: cancelCount,
        finishRecognition: { "spoken words" },
        translateBody: { _ in throw TranslationFailure.timedOut }
      )
    )
    await prepareWithTranslation(controller, prewarmed: prewarmed)

    controller.handle(.triggerPressed(.translate))
    controller.handle(.triggerReleased(.translate))
    await waitUntil("Session never latched") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.handle(.triggerPressed(.translate))
    await waitUntil("Session never ended") { controller.sessionStateForTesting == .idle }

    #expect(cancelCount.withLock { $0 } == 0)
    controller.stop()
  }

  /// A plain trigger in the same app still inserts what was said.
  @Test func aPlainSessionIsUntouchedWhileTranslationIsConfigured() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "spoken words" }
      )
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.toggleFromMenu()
    await waitUntil("Finish never delivered") { !recorder.insertedTexts.isEmpty }

    #expect(recorder.insertedTexts == ["spoken words"])
    controller.stop()
  }

  /// The rule that protects plain dictation: a translation model that will not
  /// load leaves dictation prepared and only the translate key refused.
  @Test func aTranslationPrewarmFailureStillLeavesDictationWorking() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    settings.translationTargetIdentifier = "es"
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "spoken words" },
        translationReady: false
      )
    )
    await prepare(controller, prewarmed: prewarmed)
    // Preparation does not wait for the translation model, so the pair may not
    // be resolved yet even though dictation is ready. Pressing before it is
    // says "No translation language", which is a different refusal.
    await waitUntil("Translation pair never resolved") {
      controller.translationPairForTesting != nil
    }

    controller.handle(.triggerPressed(.translate))
    #expect(controller.sessionStateForTesting == .idle)
    #expect(recorder.messages.contains("Translation not ready"))

    // And plain dictation still works.
    controller.toggleFromMenu()
    await waitUntil("Plain session never started") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.stop()
  }

  /// The regression: a target chosen after launch has to reach the pair.
  /// Preparation resolves it, so anything that changes the target must re-run
  /// preparation, or the trigger is installed with nothing to translate into
  /// and refuses every press with "No translation language".
  @Test func aTargetChosenAfterLaunchResolvesOnceLanguagesAreReapplied() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let settings = AppSettings(defaults: freshDefaults())
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "spoken words" }
      )
    )
    // Prepared with translation off, exactly as a launch with no target.
    await prepare(controller, prewarmed: prewarmed)
    controller.handle(.triggerPressed(.translate))
    #expect(recorder.messages.contains("No translation language"))

    // Now a target is chosen and the languages are reapplied.
    settings.translationTargetIdentifier = "es"
    await prepareWithTranslation(controller, prewarmed: prewarmed)

    controller.handle(.triggerPressed(.translate))
    controller.handle(.triggerReleased(.translate))
    await waitUntil("Session never latched") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.handle(.triggerPressed(.translate))
    await waitUntil("Finish never delivered") { !recorder.insertedTexts.isEmpty }

    #expect(recorder.insertedTexts == ["translated: spoken words"])
    controller.stop()
  }

  /// A day file that says only what you said is harder to use later than one
  /// that says where you were saying it, so the entry names the application
  /// that held focus when the session started.
  @Test func historyNamesTheApplicationTheTextWasAimedAt() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let historyEntries = OSAllocatedUnfairLock<[HistoryEntry]>(
      initialState: []
    )
    let settings = AppSettings(defaults: freshDefaults())
    settings.dictationHistoryEnabled = true
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        captureFocusedTarget: { Self.makeTarget(applicationName: "Ghostty") },
        finishRecognition: { "spoken words" },
        historyEntries: historyEntries
      )
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.toggleFromMenu()
    await waitUntil("Finish never delivered") { !recorder.insertedTexts.isEmpty }

    #expect(historyEntries.withLock { $0 }.map(\.source) == ["Ghostty"])
    controller.stop()
  }

  /// Clipboard-only never aims at an application, so naming whichever one
  /// happened to hold focus would put a lie in the file.
  @Test func clipboardOnlyHistoryNamesTheClipboardRatherThanAnApplication() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let historyEntries = OSAllocatedUnfairLock<[HistoryEntry]>(
      initialState: []
    )
    let settings = AppSettings(defaults: freshDefaults())
    settings.dictationHistoryEnabled = true
    settings.insertionDestination = .clipboardOnly
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        captureFocusedTarget: { Self.makeTarget(applicationName: "Ghostty") },
        finishRecognition: { "spoken words" },
        historyEntries: historyEntries,
        insertOutcome: .copiedToClipboard
      )
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.toggleFromMenu()
    await waitUntil("Finish never delivered") { !recorder.insertedTexts.isEmpty }

    #expect(historyEntries.withLock { $0 }.map(\.source) == ["Clipboard"])
    controller.stop()
  }
}
