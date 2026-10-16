import SwiftUI

/// Intelligence's row under the housing: room for the orb or ghost at the
/// leading edge, "Listening" until the first word and then the live
/// recent-word line, and the voice indicator at the trailing edge. The shell
/// widens the island when the first word arrives, so the line has the room
/// "Listening" did not need.
struct HUDIntelligenceStageView: View {
  /// Width kept clear for the orb or ghost, from the stage's leading edge.
  static let iconReserve = HUDIntelligenceOrbView.restingInset + HUDIntelligenceOrbView.restingRadius + 8

  /// The recent-word line's box: its 24-point type and a little air.
  static let draftLineHeight: CGFloat = 30

  let content: DictationHUDContent
  let palette: HUDGlowPalette
  let scale: CGFloat
  /// The recent-word line's colors, leading to trailing.
  let textColors: [Color]
  /// Off, the row keeps saying Listening while words arrive.
  var showsDraft = true

  private var hasDraft: Bool {
    showsDraft && (!content.text.isEmpty || !content.volatileText.isEmpty)
  }

  var body: some View {
    HStack(spacing: 10 * scale) {
      Color.clear
        .frame(width: Self.iconReserve * scale)
      ZStack(alignment: .leading) {
        if hasDraft {
          // In the stage's upper part, above the orb's center line, so the
          // oldest words never run into it.
          HUDRecentDraftText(
            committed: content.text,
            volatile: content.volatileText,
            scale: scale,
            tint: textColors
          )
          .frame(height: Self.draftLineHeight * scale)
          .frame(maxHeight: .infinity, alignment: .top)
          .padding(.top, 3 * scale)
          .transition(.blurReplace)
        } else if content.showsVoiceVisual {
          // Part of the visual, not a placeholder draft: it names the state
          // until there are words to show, and never returns once there are.
          Text("Listening")
            .font(.system(size: 15 * scale, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .transition(.blurReplace)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .animation(.easeOut(duration: 0.3), value: hasDraft)
      HUDIntelligenceWaveView(content: content, palette: palette, scale: scale)
    }
    .padding(.trailing, 16 * scale)
  }
}
