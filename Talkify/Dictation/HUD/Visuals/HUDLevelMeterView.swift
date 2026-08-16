import SwiftUI

/// The Reduce Motion voice visual: a quiet horizontal level bar in the band
/// between the housing and the draft text (CONTEXT.md: Reduce Motion replaces
/// the animated visual with a quiet level meter). A dead microphone turns the
/// bar amber; silence just sits near empty.
struct HUDLevelMeterView: View {
  let content: DictationHUDContent

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.15))
        Capsule()
          .fill(content.isAudioAlive ? Color.white.opacity(0.85) : .orange.opacity(0.6))
          .frame(width: max(6, proxy.size.width * CGFloat(content.audioLevel)))
      }
      .frame(height: 4)
      .frame(maxHeight: .infinity)
    }
    .padding(.horizontal, 60)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
