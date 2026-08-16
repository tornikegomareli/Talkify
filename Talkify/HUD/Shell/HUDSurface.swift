import SwiftUI

/// The HUD's black shape and its reveal, shared by every surface that descends
/// from the notch: the dictation shell, the Drop Transcription target, and the
/// finished transcript card.
///
/// This exists so the rules that break on real hardware live in one file.
/// Bounce is expressed only in top-anchored scale, never in position, because a
/// position overshoot lifts the shape off the screen edge and opens a visible
/// gap. Fillets exist only where there is a physical housing to flare into. The
/// host window never resizes, so the shape top-aligns inside whatever frame it
/// is handed.
struct HUDSurface<Content: View, Overlays: View>: View {
  /// With Reduce Motion every style collapses to a quiet fade.
  static var reducedMotionFade: Animation { .easeOut(duration: 0.12) }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let screen: HUDScreenSnapshot
  let metrics: HUDMetrics
  let revealStyle: HUDRevealStyle
  let isRevealed: Bool
  let size: CGSize
  /// Bumped to fire the one-shot ripple across the housing; ignored when the
  /// ripple is disabled.
  var rippleTrigger: Int = 0
  var rippleEnabled: Bool = false
  @ViewBuilder let content: Content
  @ViewBuilder let overlays: Overlays

  private var filletSize: CGFloat {
    HUDNotchGeometry.filletSize(for: screen)
  }

  private var housingShape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      bottomLeadingRadius: metrics.bottomCornerRadius,
      bottomTrailingRadius: metrics.bottomCornerRadius,
      style: .continuous
    )
  }

  var body: some View {
    content
      .frame(width: size.width)
      .frame(minHeight: size.height, alignment: .top)
      .background { housing }
      .overlay { overlays }
      .overlay(alignment: .topLeading) { fillet(.leading) }
      .overlay(alignment: .topTrailing) { fillet(.trailing) }
      .opacity(revealOpacity)
      .scaleEffect(x: revealScale.x, y: revealScale.y, anchor: .top)
      .offset(y: revealOffset)
      .animation(revealAnimation, value: isRevealed)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var isParked: Bool {
    !isRevealed && !reduceMotion
  }

  /// Where position moves at all, hidden means at or above the window's top
  /// edge — never below — so no style can open a gap against the screen edge.
  private var revealOffset: CGFloat {
    guard isParked else { return 0 }
    switch revealStyle {
    case .slide: return -(size.height + 20)
    case .unfurl, .bloom: return 0
    case .drift: return -14
    }
  }

  private var revealScale: (x: CGFloat, y: CGFloat) {
    guard isParked else { return (1, 1) }
    switch revealStyle {
    case .slide, .drift: return (1, 1)
    case .unfurl: return (1, 0.001)
    case .bloom: return (0.55, 0.55)
    }
  }

  private var revealOpacity: Double {
    if reduceMotion {
      return isRevealed ? 1 : 0
    }
    switch revealStyle {
    case .slide, .unfurl: return 1
    case .bloom, .drift: return isRevealed ? 1 : 0
    }
  }

  /// Bounce lives only in top-anchored scale (unfurl, bloom); the styles that
  /// move position (slide, drift) stay bounce-free, because a position
  /// overshoot would detach the shape from the screen edge.
  private var revealAnimation: Animation {
    if reduceMotion {
      return Self.reducedMotionFade
    }
    if isRevealed {
      switch revealStyle {
      case .slide: return .spring(duration: 0.4, bounce: 0)
      case .unfurl: return .spring(duration: 0.45, bounce: 0.3)
      case .bloom: return .spring(duration: 0.4, bounce: 0.25)
      case .drift: return .easeOut(duration: 0.24)
      }
    }
    switch revealStyle {
    case .slide, .unfurl, .bloom: return .spring(duration: 0.28, bounce: 0)
    case .drift: return .easeIn(duration: 0.18)
    }
  }

  /// The ripple sits between the clip and the shadow: it displaces the
  /// housing's pixels, and the shadow outside the effect stays still instead of
  /// shimmering with the wave.
  private var housing: some View {
    // Plain values for the @Sendable keyframeAnimator content closure.
    let rippleOrigin = CGPoint(
      x: size.width / 2,
      y: HUDNotchGeometry.closedSize(for: screen).height
    )
    let ripplePlays = !reduceMotion && rippleEnabled
    return Color.black
      .clipShape(housingShape)
      .keyframeAnimator(
        initialValue: 0.0,
        trigger: rippleTrigger
      ) { view, elapsed in
        view.modifier(
          HUDRippleModifier(
            origin: rippleOrigin,
            elapsedTime: elapsed,
            isEnabled: ripplePlays
          )
        )
      } keyframes: { _ in
        MoveKeyframe(0.0)
        LinearKeyframe(
          HUDRippleModifier.duration,
          duration: HUDRippleModifier.duration
        )
      }
      .shadow(color: .black.opacity(0.35), radius: 11 * metrics.scale, y: 4 * metrics.scale)
  }

  /// Sits alongside the body rather than inside it. Absent on a display with no
  /// notch: the flare exists to meet a housing (ADR-0001).
  @ViewBuilder
  private func fillet(_ side: HorizontalEdge) -> some View {
    if filletSize > 0 {
      Color.black
        .frame(width: filletSize, height: filletSize)
        .clipShape(NotchFilletShape(side: side))
        .offset(x: side == .leading ? -filletSize : filletSize)
    }
  }
}

extension HUDSurface where Overlays == EmptyView {
  init(
    screen: HUDScreenSnapshot,
    metrics: HUDMetrics,
    revealStyle: HUDRevealStyle,
    isRevealed: Bool,
    size: CGSize,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      screen: screen,
      metrics: metrics,
      revealStyle: revealStyle,
      isRevealed: isRevealed,
      size: size,
      content: content,
      overlays: { EmptyView() }
    )
  }
}
