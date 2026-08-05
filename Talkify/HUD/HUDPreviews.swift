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
/// levels, like the debug demo does. Tweak the arguments per preview.
struct HUDShellPreviewHarness: View {
    var screen = HUDPreviewScreen.notched
    var text = "Draft text arrives and keeps updating while you speak"
    /// nil = no voice visual (plain message/draft state).
    var visual: HUDVoiceVisualStyle?
    var waveformStyle = HUDWaveformStyle.silver
    var longDraft = HUDLongDraftStyle.growDown
    /// false previews the dead-microphone state.
    var micAlive = true

    @State private var content = DictationHUDContent()

    var body: some View {
        DictationHUDShellView(screen: screen, content: content)
            .frame(width: 700, height: 280, alignment: .top)
            .background { HUDPreviewScreen.wallpaper }
            .task {
                content.text = text
                content.longDraftStyle = longDraft
                content.isRevealed = true
                guard let visual else { return }
                content.voiceVisualStyle = visual
                content.waveformStyle = waveformStyle
                content.showsVoiceVisual = true
                content.isAudioAlive = micAlive
                guard micAlive else { return }

                // Syllable bursts over a quiet noise floor, like the demo.
                var t = 0.0
                while !Task.isCancelled {
                    let burst = max(0, sin(t * 5.6))
                    let raw = 0.05 + burst * (0.3 + 0.35 * Double.random(in: 0...1))
                    content.audioLevel = max(raw, content.audioLevel * 0.88)
                    t += 0.022
                    try? await Task.sleep(for: .milliseconds(22))
                }
            }
    }
}

#Preview("Edge Glow · notched") {
    HUDShellPreviewHarness(visual: .glow)
}

#Preview("Edge Glow · dead mic") {
    HUDShellPreviewHarness(visual: .glow, micAlive: false)
}

#Preview("Waveform · notched") {
    HUDShellPreviewHarness(visual: .waveform)
}

#Preview("Waveform · dead mic") {
    HUDShellPreviewHarness(visual: .waveform, micAlive: false)
}

#Preview("Draft · grow down") {
    HUDShellPreviewHarness(
        text: "A long draft that outgrows a single line wraps and grows the "
            + "shape downward, capped at four lines, so the newest words stay visible"
    )
}

#Preview("Message · simulated notch") {
    HUDShellPreviewHarness(screen: HUDPreviewScreen.external, text: "Secure field")
}
