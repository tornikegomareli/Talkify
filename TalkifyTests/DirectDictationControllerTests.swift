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
    translationAvailability: TranslationAvailability = .installed,
    translationReady: Bool = true,
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
      translationAvailability: { _ in translationAvailability },
      prewarmTranslation: { _ in translationReady },
      retainTranslation: { pair in retainedPairs.withLock { $0.append(pair) } },
      translateText: { text, _ in
        if let translateBody { return try await translateBody(text) }
        return "translated: \(text)"
      },
      shutDownTranslation: {},
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

  /// The feature: a translate session inserts the translation, not the words.
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
}
