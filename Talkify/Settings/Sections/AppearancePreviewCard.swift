import SwiftUI

/// The Appearance preview: the same HUD surface Direct Dictation uses,
/// against a simulated display with a menu bar strip, fed a bounded
/// microphone-level loop (CONTEXT.md: fixed notched reference geometry, a
/// labeled simulated listening state, quiet frame under Reduce Motion).
struct SettingsPreviewCard: View {
  let settings: AppSettings

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var content = DictationHUDContent()
  /// Runs the one-shot demos below; a new demo cancels the previous one.
  @State private var demoTask: Task<Void, Never>?

  var body: some View {
    SettingsPreviewStage(
      title: "Live preview",
      subtitle: "Changes appear here immediately"
    ) {
      DictationHUDShellView(
        screen: HUDPreviewScreen.notched,
        settings: settings.sessionSettings,
        content: content
      )
    }
    // The preview idles in a revealed listening state, where these two
    // picks have nothing to show: reveal style only exists during the
    // reveal transition, and long-draft behavior only exists while the
    // text band wraps. Changing either plays a short demo of it.
    .onChange(of: settings.revealStyle) {
      replayReveal()
    }
    .onChange(of: settings.longDraftStyle) {
      demoLongDraft()
    }
    .task(id: reduceMotion) {
      content.isRevealed = true
      content.showsVoiceVisual = true
      content.isAudioAlive = true
      content.text = "Direct Dictation preview"
      content.sessionEpoch += 1

      if reduceMotion {
        content.audioLevel = 0.2
        content.levelHistory = [Float](repeating: 0.2, count: HUDWaveformView.barCount)
        return
      }

      var time = 0.0
      while !Task.isCancelled {
        let level = 0.1 + max(0, sin(time * 4.8)) * 0.28
        content.audioLevel = level
        content.levelHistory.removeFirst()
        content.levelHistory.append(Float(level))
        time += 0.07
        try? await Task.sleep(for: .milliseconds(70))
      }
    }
  }

  /// Replays the reveal: retract, wait out the dismiss, descend again with
  /// the freshly picked style.
  private func replayReveal() {
    demoTask?.cancel()
    demoTask = Task { @MainActor in
      // A cancelled long-draft demo may have left its long text up.
      content.text = "Direct Dictation preview"
      content.showsVoiceVisual = true
      content.isRevealed = false
      try? await Task.sleep(for: .milliseconds(450))
      guard !Task.isCancelled else { return }
      content.isRevealed = true
    }
  }

  /// Shows the picked long-draft behavior: the text band only renders when
  /// no visual replaces it, so the visual steps aside while a long draft
  /// wraps, truncates, or shrinks, then listening resumes.
  private func demoLongDraft() {
    demoTask?.cancel()
    demoTask = Task { @MainActor in
      // A cancelled reveal replay may have left the shape retracted.
      content.isRevealed = true
      content.showsVoiceVisual = false
      let longDraft = "A long draft that outgrows a single line shows "
        + "how the HUD handles longer dictated text while you speak"
      content.text = longDraft
      try? await Task.sleep(for: .seconds(2.5))
      guard !Task.isCancelled else { return }
      content.text = "Direct Dictation preview"
      content.showsVoiceVisual = true
    }
  }
}
