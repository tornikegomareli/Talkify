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
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Live preview")
            .font(.system(size: 14, weight: .semibold))
          Text("Changes appear here immediately")
            .font(.caption)
            .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.48))
        }
        Spacer()
        Circle()
          .fill(SettingsTheme.accent)
          .frame(width: 7, height: 7)
          .shadow(color: SettingsTheme.accent, radius: reduceMotion ? 0 : 7)
      }

      ZStack(alignment: .top) {
        LinearGradient(
          colors: [Color(red: 0.055, green: 0.065, blue: 0.09), .black],
          startPoint: .top,
          endPoint: .bottom
        )

        simulatedMenuBar

        DictationHUDShellView(
          screen: HUDPreviewScreen.notched,
          settings: settings.sessionSettings,
          content: content
        )
        .scaleEffect(0.48, anchor: .top)
        .frame(width: 300, height: 105, alignment: .top)
        .clipped()
      }
      .frame(height: 118)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(.white.opacity(contrast == .increased ? 0.2 : 0.07), lineWidth: 1)
      }
    }
    .padding(16)
    .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(.white.opacity(contrast == .increased ? 0.22 : 0.1), lineWidth: 1)
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

  /// A simulated menu bar strip so the shape reads as a notch at the top
  /// of a display: matches the housing strip's scaled height, with the
  /// Talkify ghost among the status items. The shell's black housing
  /// draws over its center.
  private var simulatedMenuBar: some View {
    HStack(spacing: 0) {
      HStack(spacing: 7) {
        Image(systemName: "apple.logo")
          .font(.system(size: 8))
        Text("Finder")
          .font(.system(size: 8.5, weight: .semibold))
      }
      Spacer()
      HStack(spacing: 8) {
        Image("MenuBarIcon")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(height: 8.5)
        Image(systemName: "wifi")
          .font(.system(size: 8))
        Text("11:41")
          .font(.system(size: 8.5, weight: .medium))
      }
    }
    .foregroundStyle(.white.opacity(0.55))
    .padding(.horizontal, 10)
    .frame(height: 15.4)
    .background(.white.opacity(0.05))
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
