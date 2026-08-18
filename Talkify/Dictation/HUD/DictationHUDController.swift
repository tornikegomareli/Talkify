import AppKit
import SwiftUI

/// What the HUD says during a Direct Dictation session: listening, the live
/// draft, finalizing, the editable-draft review, and the session's sounds.
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

  /// The HUD's current draft text. During Draft Review it is the editable
  /// field's content; before any words arrive it is the listening
  /// placeholder.
  var draftText: String { content.text }

  /// The editable field's selection as UTF-16 offsets into the draft, nil
  /// while nothing is selected (or the field is not up). A Replacement
  /// Dictation replaces exactly this range.
  var draftSelectionRange: NSRange? {
    guard let selection = content.selection else { return nil }
    switch selection.indices {
    case let .selection(indices):
      return NSRange(indices, in: content.text)
    case .multiSelection:
      return nil
    default:
      return nil
    }
  }

  /// Writes the draft back after a Replacement Dictation: the new text with
  /// the cursor placed after the inserted words, or the untouched draft
  /// when the round delivered nothing.
  func setDraft(_ text: String, selection: TextSelection? = nil) {
    content.text = text
    if let selection {
      content.selection = selection
    }
  }

  /// Recognition finished and the editable-draft variant holds its draft:
  /// the HUD swaps the read-only band for the editable field and the panel
  /// takes key, so the user can edit in place, start a Replacement
  /// Dictation with the trigger, Return to paste, or Escape to discard.
  /// The app never activates: the panel is non-activating, the previously
  /// focused control stays frontmost, and its window takes key back the
  /// moment the review ends.
  func showEditableDraft() {
    guard stage.occupant == .dictation else { return }
    stopWatchdog()
    content.showsVoiceVisual = false
    content.isAudioAlive = true
    content.audioLevel = 0
    content.isReviewing = true
    content.replacementHighlight = nil
    stage.enableDraftEditing()
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
    // A fresh round opens with the listening placeholder; a replacement
    // round under a held draft keeps the draft — the band's text stays what
    // the user was reading, and the live words splice into it as they
    // stream (DraftReplacement).
    if !content.isReviewing {
      content.text = placeholder
    }
    // A fresh round listens display-only, exactly like any dictation: the
    // review's key and mouse are re-armed only once the draft is held again
    // (showEditableDraft). `isReviewing` stays true through a replacement
    // round — the draft must never disappear while the review is up.
    stage.endDraftEditing()
    stage.revealDictation()
  }

  func showLatched() {
    guard isListening else { return }
    sessionIsLatched = true
    // A latched replacement round keeps the draft on screen too.
    if !content.isReviewing {
      content.text = placeholder
    }
  }

  /// Exposed so the placeholder rules can be asserted without a window.
  var textForTesting: String { content.text }

  /// What the band says before any words arrive.
  ///
  /// Empty for Compact: it is the one visual built around the live draft, so a
  /// placeholder there is words nobody spoke. Every path that would write one
  /// asks here, rather than each deciding for itself — which is how "Listening
  /// (latched)" kept coming back after the opening text was handled.
  private var placeholder: String {
    guard sessionSettings.voiceVisual != .compact else { return "" }
    return sessionIsLatched ? Self.latchedText : Self.listeningText
  }

  /// A session waiting on its language model. The band says what it is waiting
  /// for instead of sitting on "Listening…" while nothing arrives; passing nil
  /// restores whatever the session was saying before.
  func showModelDownload(_ text: String?) {
    // A download line must never clobber the draft being reviewed.
    guard isListening, !content.isReviewing else { return }
    content.text = text ?? placeholder
  }

  func showLiveText(_ text: String, replacementHighlight range: NSRange? = nil) {
    guard isListening, !text.isEmpty else { return }
    content.text = text
    content.replacementHighlight = range
  }

  /// Marks the selection a replacement round will overwrite, before any
  /// words arrive; `showLiveText` keeps it in sync as the words stream.
  func markReplacementSelection(_ range: NSRange) {
    content.replacementHighlight = range
  }

  /// Speech has stopped but the recognized text has not arrived yet.
  ///
  /// Nothing is written and nothing resizes. The watchdog stops, because the
  /// silence that follows the last word is not a dead microphone, and the level
  /// settles to zero so the visual comes to rest instead of freezing mid-wobble.
  func showFinalizing() {
    guard isListening else { return }
    stopWatchdog()
    content.isAudioAlive = true
    content.audioLevel = 0
  }

  func hide() {
    stage.cancelMessageDismiss()
    if isListening {
      stage.sounds.playEnd(using: sessionSettings.sounds)
    }
    // The shape retracts exactly as it stands. The visual stops reacting so a
    // glow can play its drain, but the bands are pinned and the text is left
    // alone: resizing or relabelling a shape that is already sliding away is
    // the jolt this avoids.
    stopWatchdog()
    content.isDismissing = true
    content.showsVoiceVisual = false
    content.isReviewing = false
    content.selection = nil
    content.replacementHighlight = nil
    stage.retract()
  }

  /// Resets the visual to a live-and-silent baseline and arms the dead-mic
  /// watchdog.
  private func startVoiceVisual() {
    content.isDismissing = false
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
    stopWatchdog()
    content.showsVoiceVisual = false
  }

  private func stopWatchdog() {
    micWatchdogTask?.cancel()
    micWatchdogTask = nil
  }
}
