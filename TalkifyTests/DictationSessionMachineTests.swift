import Testing
@testable import Talkify

/// Pins the session machine's gesture and race rules — the logic that used
/// to be testable only by holding Fn against a live microphone.
struct DictationSessionMachineTests {
  private typealias Machine = DictationSessionMachine

  private let t0 = ContinuousClock.now

  /// Drives a machine into `.recording` with the given gesture.
  private func recordingMachine(latched: Bool = false) -> Machine {
    var machine = Machine()
    if latched {
      _ = machine.reduce(.menuToggled(now: t0))
    } else {
      _ = machine.reduce(.triggerPressed(now: t0))
    }
    _ = machine.reduce(.beginApproved)
    _ = machine.reduce(.recognitionStarted(now: t0.advanced(by: .milliseconds(300))))
    return machine
  }

  @Test func pressBeginsAHeldSessionAfterApproval() {
    var machine = Machine()
    #expect(machine.reduce(.triggerPressed(now: t0)) == [.checkAndBegin])
    let effects = machine.reduce(.beginApproved)
    #expect(effects == [
      .setEscapeCapture(true),
      .showListening(latched: false),
      .notifyRecording(true),
      .beginRecognition,
    ])
    #expect(machine.state == .starting(.held(startedAt: t0)))
  }

  @Test func menuToggleBeginsALatchedSession() {
    var machine = Machine()
    #expect(machine.reduce(.menuToggled(now: t0)) == [.checkAndBegin])
    let effects = machine.reduce(.beginApproved)
    #expect(effects.contains(.showListening(latched: true)))
    #expect(machine.state == .starting(.latched))
  }

  @Test func rejectedBeginStaysIdle() {
    var machine = Machine()
    _ = machine.reduce(.triggerPressed(now: t0))
    #expect(machine.reduce(.beginRejected).isEmpty)
    #expect(machine.state == .idle)
    // A later approval without a pending gesture must do nothing.
    #expect(machine.reduce(.beginApproved).isEmpty)
    #expect(machine.state == .idle)
  }

  @Test func repeatedPressWhileHeldIsIgnored() {
    var machine = Machine()
    _ = machine.reduce(.triggerPressed(now: t0))
    _ = machine.reduce(.beginApproved)
    #expect(machine.reduce(.triggerPressed(now: t0.advanced(by: .milliseconds(50)))).isEmpty)
  }

  @Test func quickReleaseWhileStartingLatches() {
    var machine = Machine()
    _ = machine.reduce(.triggerPressed(now: t0))
    _ = machine.reduce(.beginApproved)
    let effects = machine.reduce(.triggerReleased(now: t0.advanced(by: .milliseconds(120))))
    #expect(effects == [.showLatched])
    #expect(machine.state == .starting(.latched))
  }

  @Test func quickReleaseWhileRecordingLatches() {
    var machine = recordingMachine()
    let effects = machine.reduce(.triggerReleased(now: t0.advanced(by: .milliseconds(180))))
    #expect(effects == [.showLatched])
    #expect(machine.state == .recording(.latched))
  }

  @Test func slowReleaseWhileRecordingFinishes() {
    var machine = recordingMachine()
    let effects = machine.reduce(.triggerReleased(now: t0.advanced(by: .seconds(3))))
    #expect(machine.state == .finishing)
    #expect(effects.contains(.showFinalizing))
    // Speaking time counts from recognition start (t0+300ms), not the press.
    #expect(effects.contains(.finishRecognition(speakingDuration: 2.7)))
  }

  @Test func pressWhileLatchedRecordingFinishes() {
    var machine = recordingMachine(latched: true)
    let effects = machine.reduce(.triggerPressed(now: t0.advanced(by: .seconds(5))))
    #expect(machine.state == .finishing)
    #expect(effects.contains(.showFinalizing))
  }

  @Test func releaseWhileStartingQueuesTheFinish() {
    var machine = Machine()
    _ = machine.reduce(.triggerPressed(now: t0))
    _ = machine.reduce(.beginApproved)
    // A slow release before recognition is ready cannot finish yet.
    #expect(machine.reduce(.triggerReleased(now: t0.advanced(by: .seconds(1)))).isEmpty)
    #expect(machine.state == .starting(.held(startedAt: t0)))

    // The queued finish fires the moment recognition starts.
    let effects = machine.reduce(.recognitionStarted(now: t0.advanced(by: .seconds(2))))
    #expect(machine.state == .finishing)
    #expect(effects.first == .startNoSpeechTimer)
    #expect(effects.contains(.finishRecognition(speakingDuration: 0)))
  }

  @Test func escapeWhileStartingCancelsTheStartTask() {
    var machine = Machine()
    _ = machine.reduce(.triggerPressed(now: t0))
    _ = machine.reduce(.beginApproved)
    let effects = machine.reduce(.escapePressed)
    #expect(effects == [
      .cancelStartTask,
      .stopNoSpeechTimer,
      .setEscapeCapture(false),
      .hideHUD,
    ])
    #expect(machine.state == .cancelling)

    // The torn-down start task reports back; the session resets quietly.
    let resetEffects = machine.reduce(.recognitionFailed(wasCancelled: true))
    #expect(resetEffects.contains(.notifyRecording(false)))
    #expect(machine.state == .idle)
  }

  @Test func recognitionStartingAfterEscapeStillCancels() {
    var machine = Machine()
    _ = machine.reduce(.triggerPressed(now: t0))
    _ = machine.reduce(.beginApproved)
    _ = machine.reduce(.escapePressed)
    // The recognizer won the race and started anyway: it must be
    // cancelled, and the state must not become .recording.
    let effects = machine.reduce(.recognitionStarted(now: t0.advanced(by: .seconds(1))))
    #expect(effects == [.cancelRecognition])
    #expect(machine.state == .cancelling)
  }

  @Test func escapeWhileRecordingCancels() {
    var machine = recordingMachine()
    let effects = machine.reduce(.escapePressed)
    #expect(effects == [
      .stopNoSpeechTimer,
      .setEscapeCapture(false),
      .hideHUD,
      .cancelRecognition,
    ])
    #expect(machine.state == .cancelling)
  }

  @Test func escapeWhileFinishingIsIgnored() {
    var machine = recordingMachine()
    _ = machine.reduce(.triggerReleased(now: t0.advanced(by: .seconds(2))))
    #expect(machine.reduce(.escapePressed).isEmpty)
    #expect(machine.state == .finishing)
  }

  @Test func silentSessionCancelsOnTimeout() {
    var machine = recordingMachine()
    let effects = machine.reduce(.noSpeechTimedOut)
    #expect(effects.contains(.hideHUD))
    #expect(machine.state == .cancelling)
  }

  @Test func speechKeepsTheSessionOpenPastTimeout() {
    var machine = recordingMachine()
    _ = machine.reduce(.updateReceived(hasVisibleText: true))
    #expect(machine.reduce(.noSpeechTimedOut).isEmpty)
    #expect(machine.state == .recording(.held(startedAt: t0)))
  }

  @Test func visibleTextStopsTheNoSpeechTimer() {
    var machine = recordingMachine()
    let effects = machine.reduce(.updateReceived(hasVisibleText: true))
    #expect(effects == [.stopNoSpeechTimer, .showLiveText])
  }

  @Test func updatesDuringFinishingNeverShowTheDraft() {
    var machine = recordingMachine()
    _ = machine.reduce(.triggerReleased(now: t0.advanced(by: .seconds(2))))
    let effects = machine.reduce(.updateReceived(hasVisibleText: true))
    #expect(!effects.contains(.showLiveText))
  }

  @Test func updatesWhileIdleAreIgnored() {
    var machine = Machine()
    #expect(machine.reduce(.updateReceived(hasVisibleText: true)).isEmpty)
  }

  @Test func readAloudFiresOnlyWhileIdle() {
    var machine = Machine()
    #expect(machine.reduce(.readAloudPressed) == [.triggerReadAloud])

    machine = recordingMachine()
    #expect(machine.reduce(.readAloudPressed).isEmpty)
  }

  @Test func failureWhileRecordingCancelsRecognition() {
    var machine = recordingMachine()
    let effects = machine.reduce(.recognitionFailed(wasCancelled: false))
    #expect(effects == [
      .stopNoSpeechTimer,
      .setEscapeCapture(false),
      .cancelRecognition,
    ])
    #expect(machine.state == .cancelling)
  }

  @Test func sessionEndedResetsEverything() {
    var machine = recordingMachine()
    _ = machine.reduce(.updateReceived(hasVisibleText: true))
    let effects = machine.reduce(.sessionEnded)
    #expect(effects == [
      .stopNoSpeechTimer,
      .setEscapeCapture(false),
      .notifyRecording(false),
    ])
    #expect(machine.state == .idle)
    // The next session must not inherit the previous session's speech.
    _ = machine.reduce(.triggerPressed(now: t0))
    _ = machine.reduce(.beginApproved)
    _ = machine.reduce(.recognitionStarted(now: t0))
    let cancelEffects = machine.reduce(.noSpeechTimedOut)
    #expect(cancelEffects.contains(.hideHUD))
  }

  @Test func menuToggleFinishesALatchedRecording() {
    var machine = recordingMachine(latched: true)
    let effects = machine.reduce(.menuToggled(now: t0.advanced(by: .seconds(4))))
    #expect(machine.state == .finishing)
    #expect(effects.contains(.showFinalizing))
  }
}
