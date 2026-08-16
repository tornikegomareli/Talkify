import SwiftUI

/// Fixtures and a live harness so every HUD state can be tinkered with in
/// the Xcode canvas — change a parameter in DictationHUDShellView (or the
/// harness arguments below) and watch it re-render, no app relaunch.
enum HUDPreviewScreen {
  /// A 14" MacBook Pro: real notch, so fillets render.
  static let notched = HUDScreenSnapshot(
    id: 1,
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    safeAreaTop: 32,
    auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663.5, height: 32),
    auxiliaryTopRightArea: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
  )

  /// An external display: simulated notch footprint, no fillets.
  static let external = HUDScreenSnapshot(
    id: 2,
    frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
    safeAreaTop: 0,
    auxiliaryTopLeftArea: nil,
    auxiliaryTopRightArea: nil
  )

  static var wallpaper: some View {
    LinearGradient(
      colors: [Color(red: 0.25, green: 0.4, blue: 0.8), Color(red: 0.1, green: 0.15, blue: 0.35)],
      startPoint: .top,
      endPoint: .bottom
    )
  }
}

/// Hosts the shell against a wallpaper and feeds it synthesized speech-like
/// levels. Tweak the arguments per preview. Settings live in a volatile
/// UserDefaults suite so canvas tinkering never touches real preferences.
struct HUDShellPreviewHarness: View {
  var screen = HUDPreviewScreen.notched
  var text = "Draft text arrives and keeps updating while you speak"
  /// nil = no voice visual (plain message/draft state).
  var visual: HUDVoiceVisualStyle?
  var waveformStyle = HUDWaveformStyle.chartLine
  var glowCenter = HUDGlowCenterStyle.particles
  var longDraft = HUDLongDraftStyle.growDown
  /// The HUD size, as a fraction of the standard shape.
  var hudScale = 1.0
  /// false previews the dead-microphone state.
  var micAlive = true
  /// true toggles the session on and off every ~3 seconds so the canvas
  /// exercises the bloom-in/drain-out ramps and the text band's return.
  var simulatesSessionCycle = false

  @State private var settings = AppSettings.previewStore()
  @State private var content = DictationHUDContent()

  var body: some View {
    DictationHUDShellView(
      screen: screen,
      settings: settings.sessionSettings,
      content: content
    )
      .frame(width: 700, height: 280, alignment: .top)
      .background { HUDPreviewScreen.wallpaper }
      .task {
        content.text = text
        settings.longDraftStyle = longDraft
        settings.hudScale = hudScale
        content.isRevealed = true
        guard let visual else { return }
        settings.voiceVisual = visual
        settings.waveformStyle = waveformStyle
        settings.glowCenter = glowCenter
        content.showsVoiceVisual = true
        content.isAudioAlive = micAlive
        guard micAlive else { return }

        // Syllable bursts over a quiet noise floor.
        var t = 0.0
        while !Task.isCancelled {
          if simulatesSessionCycle {
            let listening = Int(t / 3.0).isMultiple(of: 2)
            if listening != content.showsVoiceVisual {
              content.showsVoiceVisual = listening
              if listening { content.sessionEpoch += 1 }
            }
          }
          let burst = max(0, sin(t * 5.6))
          let raw = 0.05 + burst * (0.3 + 0.35 * Double.random(in: 0...1))
          content.audioLevel = max(raw, content.audioLevel * 0.88)
          t += 0.022
          try? await Task.sleep(for: .milliseconds(22))
        }
      }
  }
}

extension AppSettings {
  /// A store backed by a cleared volatile suite, for previews only.
  static func previewStore() -> AppSettings {
    let suiteName = "com.tgomareli.Talkify.preview"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    return AppSettings(defaults: defaults)
  }
}

#Preview("Edge Glow · dead mic") {
  HUDShellPreviewHarness(visual: .glow, micAlive: false)
}

#Preview("Waveform · dead mic") {
  HUDShellPreviewHarness(visual: .waveform, micAlive: false)
}

// Issue #24: the shape a user picks when the HUD is covering work rather
// than hardware. Side by side with the standard size on the same display.

#Preview("Smallest · external") {
  HUDShellPreviewHarness(screen: HUDPreviewScreen.external, visual: .waveform, hudScale: 0.6)
}

#Preview("Smallest · external · glow") {
  HUDShellPreviewHarness(screen: HUDPreviewScreen.external, visual: .glow, hudScale: 0.6)
}

#Preview("Smallest · external · compact") {
  HUDShellPreviewHarness(screen: HUDPreviewScreen.external, visual: .compact, hudScale: 0.6)
}
