import Observation
import SwiftUI

/// What the HUD currently says — the one mutable model shared between the
/// AppKit controller (which writes it) and the SwiftUI shell and visuals
/// (which observe it).
@MainActor
@Observable
final class DictationHUDContent {
  var text = ""
  /// True from recognition finishing until Return or Escape: the draft is
  /// held in the editable field of the editable-draft variant. Stays true
  /// through a replacement round — the shell keeps the text band visible
  /// and drops only the field while the round listens.
  var isReviewing = false
  /// The editable field's selection, written by the shell's TextEditor and
  /// read when a Replacement Dictation begins so the round knows exactly
  /// which range of the draft to replace.
  var selection: TextSelection?
  /// While a Replacement Dictation listens, the UTF-16 range in `text` that
  /// the band highlights as the landing zone: the selected words before any
  /// arrive, then the streaming words spliced over them. nil outside a
  /// listening replacement round.
  var replacementHighlight: NSRange?
  /// Drives the reveal/dismiss animation.
  var isRevealed = false
  /// True only while listening — the visuals react to the microphone, so
  /// they leave when it stops.
  var showsVoiceVisual = false
  /// Smoothed microphone level, 0–1.
  var audioLevel: Double = 0
  /// Raw recent levels, newest last, one per waveform bar.
  var levelHistory = [Float](repeating: 0, count: HUDWaveformView.barCount)
  /// False once levels stop arriving while listening: a dead microphone
  /// must look different from silence (CONTEXT.md).
  var isAudioAlive = true
  /// The session's language as a short tag ("DE"), or nil when only one
  /// language is set up. Recognition in the wrong language returns confident
  /// nonsense rather than an error, so a two-key setup says which is live.
  var languageTag: String?
  /// True from the moment the HUD starts retracting until it is off screen.
  /// The layout is pinned to whatever it was showing: the voice visual stops
  /// reacting so a glow can drain, but the bands must not resize underneath a
  /// shape that is already sliding away.
  var isDismissing = false
  /// Bumped once per session start; one-shot effects (the ripple) trigger
  /// on the change rather than on the listening state, so they never
  /// re-fire mid-session.
  var sessionEpoch = 0
}
