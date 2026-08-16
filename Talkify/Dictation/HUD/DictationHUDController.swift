import AppKit

/// What the HUD says during a Direct Dictation session: listening, the live
/// draft, finalizing, and the session's sounds.
///
/// It owns none of the window. `HUDStage` decides where the shape is and who
/// holds it; this decides what dictation puts in it.
@MainActor
final class DictationHUDController {
  private static let latchedText = "Listening (latched)"
  private static let listeningText = "Listening…"
  /// Levels stopping for this long while listening means the microphone is
  /// dead, which must look different from silence (CONTEXT.md).
  private static let deadMicrophoneAfter = Duration.milliseconds(600)

  private let stage: HUDStage
  private var sessionSettings: DictationSessionSettings
  /// Remembered so a download line can restore the right session text.
  private var sessionIsLatched = false
  private var lastLevelAt = ContinuousClock.now
  private var micWatchdogTask: Task<Void, Never>?
  private var hasPlayedBeginSound = false

  private var content: DictationHUDContent { stage.dictationContent }
  private var isListening: Bool { stage.occupant == .dictation }

  init(stage: HUDStage, settings: AppSettings) {
    self.stage = stage
    sessionSettings = settings.sessionSettings
  }

  /// Live microphone level, 0–1, ~46 Hz while listening. Smoothed with a
  /// fast attack and slow release, appended raw to the waveform history,
  /// and marks the microphone alive for the dead-mic watchdog.
  func showAudioLevel(_ level: Float) {
    guard content.showsVoiceVisual else { return }
    if !hasPlayedBeginSound {
      hasPlayedBeginSound = true
      stage.sounds.playBegin(using: sessionSettings.sounds)
    }
    content.audioLevel = max(Double(level), content.audioLevel * 0.88)
    content.levelHistory.removeFirst()
    // Light EMA against the previous bar calms per-tick jitter without
    // dulling the speech rhythm.
    let lastBar = content.levelHistory.last ?? 0
    content.levelHistory.append(0.6 * level + 0.4 * lastBar)
    lastLevelAt = ContinuousClock.now
    content.isAudioAlive = true
  }

  /// Played when finalized text lands in the target, after a finished
  /// session's insertion.
  func playPasteSound() {
    stage.sounds.playPaste(using: sessionSettings.sounds)
  }

  func showMessage(_ text: String, on displayID: CGDirectDisplayID? = nil) {
    stopVoiceVisual()
    stage.showMessage(text, on: displayID)
  }

  func showListening(
    on displayID: CGDirectDisplayID?,
    isLatched: Bool,
    settings: DictationSessionSettings,
    languageTag: String? = nil
  ) {
    guard let screen = stage.screen(preferring: displayID) else { return }
    sessionSettings = settings
    hasPlayedBeginSound = false
    content.languageTag = languageTag
    sessionIsLatched = isLatched
    // Dictation outranks a file job for the shape: the user is speaking now,
    // and the transcription keeps running with the status item carrying it.
    stage.claim(.dictation, on: screen, rendering: settings)
    startVoiceVisual()
    content.text = isLatched ? Self.latchedText : Self.listeningText
    stage.revealDictation()
  }

  func showLatched() {
    guard isListening else { return }
    content.text = Self.latchedText
  }

  /// A session waiting on its language model. The band says what it is waiting
  /// for instead of sitting on "Listening…" while nothing arrives; passing nil
  /// restores whatever the session was saying before.
  func showModelDownload(_ text: String?) {
    guard isListening else { return }
    content.text = text ?? (sessionIsLatched ? Self.latchedText : Self.listeningText)
  }

  func showLiveText(_ text: String) {
    guard isListening, !text.isEmpty else { return }
    content.text = text
  }

  func showFinalizing() {
    guard isListening else { return }
    stopVoiceVisual()
    content.text = "Finalizing…"
  }

  func hide() {
    stage.cancelMessageDismiss()
    if isListening {
      stage.sounds.playEnd(using: sessionSettings.sounds)
    }
    stopVoiceVisual()
    stage.retract()
  }

  /// Resets the visual to a live-and-silent baseline and arms the dead-mic
  /// watchdog.
  private func startVoiceVisual() {
    content.sessionEpoch += 1
    content.showsVoiceVisual = true
    content.audioLevel = 0
    content.levelHistory = [Float](repeating: 0, count: HUDWaveformView.barCount)
    content.isAudioAlive = true
    lastLevelAt = ContinuousClock.now

    micWatchdogTask?.cancel()
    micWatchdogTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(300))
        guard let self, !Task.isCancelled else { return }
        if lastLevelAt.duration(to: .now) > Self.deadMicrophoneAfter {
          content.isAudioAlive = false
        }
      }
    }
  }

  private func stopVoiceVisual() {
    micWatchdogTask?.cancel()
    micWatchdogTask = nil
    content.showsVoiceVisual = false
  }
}
