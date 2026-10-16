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
  /// Space between the row's three parts.
  static let spacing: CGFloat = 10
  /// Room after the voice indicator, at the trailing edge.
  static let trailingInset: CGFloat = 16
  /// From the line's leading edge back to the center's middle: how far the
  /// line fades past its edge as the center takes the words in.
  static let feedReach = iconReserve + spacing - HUDIntelligenceOrbView.restingInset

  /// The line's width in a shape `width` wide.
  static func lineRoom(shapeWidth width: CGFloat, scale: CGFloat) -> CGFloat {
    width - (iconReserve + 2 * spacing + HUDIntelligenceWaveView.width + trailingInset) * scale
  }

  let content: DictationHUDContent
  let palette: HUDGlowPalette
  let scale: CGFloat
  /// The recent-word line's colors, leading to trailing.
  let textColors: [Color]
  /// Off, the row keeps saying Listening while words arrive.
  var showsDraft = true
  /// The stage's height, to find the center's middle beside the line.
  var stageHeight: CGFloat = 0

  /// When speech ends the draft leaves first, before the center flies home.
  private var hasDraft: Bool {
    showsDraft
      && !content.isFinalizing
      && (!content.text.isEmpty || !content.volatileText.isEmpty)
  }

  var body: some View {
    HStack(spacing: Self.spacing * scale) {
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
            tint: textColors,
            // The center's middle, from the line's leading center: back past
            // the edge, and down to the stage's center line.
            feed: CGSize(
              width: -Self.feedReach * scale,
              height: stageHeight / 2 - (3 + Self.draftLineHeight / 2) * scale
            )
          )
          .frame(height: Self.draftLineHeight * scale)
          .frame(maxHeight: .infinity, alignment: .top)
          .padding(.top, 3 * scale)
          .transition(.blurReplace)
        } else if !showsDraft, content.showsVoiceVisual {
          // With the draft off nothing else names the state, so it says so.
          // With the draft on the row stays empty until the first word.
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
    .padding(.trailing, Self.trailingInset * scale)
  }
}
