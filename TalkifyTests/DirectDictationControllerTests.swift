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
  @MainActor
  private final class Recorder {
    var events: [String] = []
    var messages: [String] = []
    var listeningLatched: [Bool] = []
    var insertedTexts: [String] = []
    var insertedDestinations: [InsertionDestination] = []
    var recordedSessions: [(wordCount: Int, speakingDuration: TimeInterval)] = []
    var accessibilityAlerts = 0

    func count(of event: String) -> Int {
      events.filter { $0 == event }.count
    }
  }

  /// Records capture calls so the wiring tests can pin what the controller
  /// hands to the MyVoice seam. Lock-guarded because the protocol
  /// conformance is nonisolated.
  private final class RecordingMyVoice: MyVoiceCaptureServicing, @unchecked Sendable {
    struct Call {
      let raw: String
      let corrected: String
      let startedAt: Date
      let stoppedAt: Date
      let locale: String
    }

    private let storage = OSAllocatedUnfairLock<[Call]>(initialState: [])

    var calls: [Call] { storage.withLock { $0 } }

    func capture(
      rawTranscript: String,
      correctedText: String,
      audioURL: URL?,
      startedAt: Date,
      stoppedAt: Date,
      localeIdentifier: String
    ) {
      storage.withLock {
        $0.append(
          Call(
            raw: rawTranscript, corrected: correctedText, startedAt: startedAt,
            stoppedAt: stoppedAt, locale: localeIdentifier
          )
        )
      }
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
    historyEntries: OSAllocatedUnfairLock<[(text: String, source: String?, folder: URL)]>
      = .init(initialState: []),
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
      showListening: { _, isLatched, _, _ in
        recorder.events.append("showListening")
        recorder.listeningLatched.append(isLatched)
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
      recordHistory: { text, source, folder in
        historyEntries.withLock { $0.append((text, source, folder)) }
      }
    )
  }

  private func makeController(
    settings: AppSettings? = nil,
    dependencies: DirectDictationController.Dependencies,
    myVoiceService: MyVoiceCaptureServicing? = nil
  ) -> DirectDictationController {
    DirectDictationController(
      settings: settings ?? AppSettings(defaults: freshDefaults()),
      dependencies: dependencies,
      myVoiceService: myVoiceService
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
    try? await Task.sleep(for: .milliseconds(20))
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
    let historyEntries = OSAllocatedUnfairLock<[(text: String, source: String?, folder: URL)]>(
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
    let historyEntries = OSAllocatedUnfairLock<[(text: String, source: String?, folder: URL)]>(
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

  /// A day file that says only what you said is harder to use later than one
  /// that says where you were saying it, so the entry names the application
  /// that held focus when the session started.
  @Test func historyNamesTheApplicationTheTextWasAimedAt() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let historyEntries = OSAllocatedUnfairLock<[(text: String, source: String?, folder: URL)]>(
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
    let historyEntries = OSAllocatedUnfairLock<[(text: String, source: String?, folder: URL)]>(
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

  /// The release path hands the finished session's words to the MyVoice
  /// seam when the flag is on, with the session-snapshot locale.
  @Test func myVoiceCaptureFiresOnInsertedFinishWhenEnabled() async throws {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let myVoice = RecordingMyVoice()
    let settings = AppSettings(defaults: freshDefaults())
    settings.myvoiceCaptureEnabled = true
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "hello world" }
      ),
      myVoiceService: myVoice
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

    let call = try #require(myVoice.calls.first)
    #expect(myVoice.calls.count == 1)
    #expect(call.raw == "hello world")
    #expect(call.corrected == "hello world")
    #expect(call.locale == "en_US")
    #expect(call.startedAt <= call.stoppedAt)
    controller.stop()
  }

  /// The flag is captured into the session snapshot at start, so a session
  /// that began while it was off never sends a candidate.
  @Test func myVoiceCaptureStaysQuietWhileTheFlagIsOff() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let myVoice = RecordingMyVoice()
    let controller = makeController(
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "hello world" }
      ),
      myVoiceService: myVoice
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

    #expect(myVoice.calls.isEmpty)
    controller.stop()
  }

  /// The sample is the words, not their delivery: an insertion that could
  /// not land still saves the transcript once the flag is on.
  @Test func myVoiceCaptureStillSavesWhenInsertionIsUnavailable() async {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let myVoice = RecordingMyVoice()
    let settings = AppSettings(defaults: freshDefaults())
    settings.myvoiceCaptureEnabled = true
    let controller = makeController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: { "spoken words" },
        insertOutcome: .unavailable
      ),
      myVoiceService: myVoice
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

    #expect(myVoice.calls.count == 1)
    #expect(myVoice.calls.first?.raw == "spoken words")
    controller.stop()
  }

  /// Return on a reviewed editable draft: the candidate carries the first
  /// round's raw ASR next to the corrected draft, and Insights records the
  /// accumulated speech duration across the review's rounds instead of a
  /// zeroed session.
  @Test func editableDraftReturnCapturesRawAndRecordsTheAccumulatedDuration() async throws {
    let recorder = Recorder()
    let prewarmed = OSAllocatedUnfairLock(initialState: false)
    let myVoice = RecordingMyVoice()
    let settings = AppSettings(defaults: freshDefaults())
    settings.draftStyle = .editableDraft
    settings.myvoiceCaptureEnabled = true
    let hud = DictationHUDController(stage: HUDStage(settings: settings), settings: settings)
    let roundNumber = OSAllocatedUnfairLock<Int>(initialState: 0)
    let controller = DirectDictationController(
      settings: settings,
      dependencies: makeDependencies(
        recorder: recorder,
        prewarmed: prewarmed,
        finishRecognition: {
          let round = roundNumber.withLock { $0 += 1; return $0 }
          return round == 1 ? "first words" : "second words"
        }
      ),
      hudController: hud,
      myVoiceService: myVoice
    )
    await prepare(controller, prewarmed: prewarmed)

    controller.toggleFromMenu()
    await waitUntil("Session never reached recording") {
      controller.sessionStateForTesting == .recording(.latched)
    }
    controller.toggleFromMenu()
    await waitUntil("Draft never reached review") {
      controller.sessionStateForTesting == .reviewing
    }

    controller.handle(.triggerPressed(.primary))
    await waitUntil("Replacement round never began") {
      recorder.count(of: "showListening") == 2
    }
    try? await Task.sleep(for: .milliseconds(300))
    controller.handle(.triggerReleased(.primary))
    await waitUntil("Replacement words never committed") {
      hud.draftText == "first wordssecond words"
    }
    controller.handle(.returnPressed)
    await waitUntil("Usage was never recorded") {
      recorder.recordedSessions.count == 1
    }

    let call = try #require(myVoice.calls.first)
    #expect(myVoice.calls.count == 1)
    #expect(call.raw == "first words")
    #expect(call.corrected == "first wordssecond words")
    #expect((recorder.recordedSessions.first?.speakingDuration ?? 0) > 0)
    controller.stop()
  }
}
