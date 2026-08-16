import SwiftUI

/// The Compact visual's voice indicator: a tiny five-bar equalizer beside
/// the draft text, after iOS's Dynamic Island sound dots. Each bar rides the
/// microphone level with its own phase so the cluster reads as sound rather
/// than a meter; silence settles the bars into resting dots, and a dead
/// microphone freezes them amber (CONTEXT.md: dead ≠ silent).
struct HUDCompactIndicatorView: View {
  private static let barCount = 5
  private static let restingHeight: CGFloat = 3

  let content: DictationHUDContent
  /// The session's HUD size. The indicator is already small, so it shrinks
  /// with the shape rather than growing proportionally louder inside it.
  var scale: CGFloat = 1

  var body: some View {
    let live = content.showsVoiceVisual && content.isAudioAlive
    TimelineView(.animation(paused: !live)) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      let level = content.audioLevel
      let alive = content.isAudioAlive
      HStack(spacing: 2.5 * scale) {
        ForEach(0..<Self.barCount, id: \.self) { index in
          Capsule()
            .fill(alive ? Color.white.opacity(0.9) : .orange.opacity(0.6))
            .frame(
              width: 2.5 * scale,
              height: barHeight(
                index: index,
                time: time,
                level: level,
                live: live
              )
            )
        }
      }
      .frame(height: 14 * scale)
      .opacity(content.showsVoiceVisual ? 1 : 0.45)
    }
    // Eases the bars down to resting dots when listening ends, instead
    // of freezing them mid-wobble.
    .animation(.easeOut(duration: 0.25), value: content.showsVoiceVisual)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func barHeight(
    index: Int,
    time: TimeInterval,
    level: Double,
    live: Bool
  ) -> CGFloat {
    guard live else { return Self.restingHeight * scale }
    // Per-bar phase offsets keep neighbors out of sync, so the cluster
    // shimmers with speech instead of pumping as one block.
    let wobble = 0.5 + 0.5 * sin(time * 9 + Double(index) * 1.7)
    return (Self.restingHeight + CGFloat(level * wobble) * 11) * scale
  }
}

#Preview("Compact") {
  HUDShellPreviewHarness(visual: .compact)
}

#Preview("Compact · dead mic") {
  HUDShellPreviewHarness(visual: .compact, micAlive: false)
}
