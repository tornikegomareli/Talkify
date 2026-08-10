import Observation

/// What the HUD currently says — the one mutable model shared between the
/// AppKit controller (which writes it) and the SwiftUI shell and visuals
/// (which observe it).
@MainActor
@Observable
final class DictationHUDContent {
  var text = ""
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
  /// Bumped once per session start; one-shot effects (the ripple) trigger
  /// on the change rather than on the listening state, so they never
  /// re-fire mid-session.
  var sessionEpoch = 0
}
