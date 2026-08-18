import SwiftUI

/// The HUD's black shape and its reveal, shared by every surface that descends
/// from the notch: the dictation shell, the Drop Transcription target, and the
/// finished transcript card.
///
/// This exists so the rules that break on real hardware live in one file.
/// Bounce is expressed only in bottom-anchored scale, never in position,
/// because a position overshoot lifts the shape off the screen edge and opens a
/// visible gap. Fillets exist only where there is a physical housing to flare
/// into. The host window never resizes, so the shape bottom-aligns inside
/// whatever frame it is handed — the HUD floats at the bottom of the display,
/// its housing cap hugging the bottom edge.
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
  /// Grows the shape out of the housing instead of moving a full-size shape
  /// into place, and overrides `revealStyle` entirely where it is on.
  ///
  /// This is how Drop Transcription opens and closes, after NotchDrop: closed,
  /// the black really is the size of the housing; open, it is the full shape;
  /// and a spring with overshoot carries it between the two. It belongs to the
  /// drop surfaces alone — dictation is a status surface, not a target, and
  /// keeps the reveal styles the user picks between.
  var growsFromHousing: Bool = false
  /// Clips the content to the shape.
  ///
  /// Off by default: the dictation visuals bloom past the silhouette on
  /// purpose. The Drop Transcription surfaces want the opposite — their well
  /// and its border are laid out against a width that is still animating, and
  /// without this they can be drawn outside the black for a frame or two,
  /// which reads as a glitch on a shape whose whole job is to look like
  /// hardware.
  var clipsContent: Bool = false
  @ViewBuilder let content: Content
  @ViewBuilder let overlays: Overlays

  private var filletSize: CGFloat {
    HUDNotchGeometry.filletSize(for: screen)
  }

  private var housingShape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      bottomLeadingRadius: cornerRadius,
      bottomTrailingRadius: cornerRadius,
      style: .continuous
    )
  }

  /// Collapsed into the housing, the corners are nearly square (NotchDrop:
  /// 8 closed, 32 open).
  private var cornerRadius: CGFloat {
    isCollapsedIntoHousing ? 8 : metrics.bottomCornerRadius
  }

  private var isCollapsedIntoHousing: Bool {
    growsFromHousing && !isRevealed
  }

  private var renderedSize: CGSize {
    isCollapsedIntoHousing ? HUDNotchGeometry.closedSize(for: screen) : size
  }

  /// Growing from the housing, the content exists only while the shape is open
  /// and flies in from behind it, which is NotchDrop's transition exactly.
  @ViewBuilder
  private var contentLayer: some View {
    if growsFromHousing {
      Group {
        if isRevealed { content }
      }
      .transition(
        .scale
          .combined(with: .opacity)
          .combined(with: .offset(y: size.height / 2))
      )
    } else {
      content
    }
  }

  var body: some View {
    contentLayer
      .frame(width: renderedSize.width)
      .frame(minHeight: renderedSize.height, alignment: .bottom)
      .clipShape(clipsContent ? AnyShape(housingShape) : AnyShape(Rectangle()))
      .background { housing }
      .overlay { overlays }
      .overlay(alignment: .bottomLeading) { fillet(.leading) }
      .overlay(alignment: .bottomTrailing) { fillet(.trailing) }
      .opacity(revealOpacity)
      .scaleEffect(x: revealScale.x, y: revealScale.y, anchor: .bottom)
      .offset(y: revealOffset)
      .animation(revealAnimation, value: isRevealed)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
  }

  /// Growing from the housing never parks: there is no transform to hide the
  /// shape with, because the shape itself is the animation.
  private var isParked: Bool {
    !isRevealed && !reduceMotion && !growsFromHousing
  }

  /// Where position moves at all, hidden means at or below the window's
  /// bottom edge — never above — so no style can open a gap against the
  /// screen edge.
  private var revealOffset: CGFloat {
    guard isParked else { return 0 }
    switch revealStyle {
    case .slide: return size.height + 20
    case .unfurl, .bloom: return 0
    case .drift: return 14
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
    // Growing from the housing never fades: the shape is always there, it is
    // just the size of the housing when closed, which is what makes it read as
    // the notch itself.
    if growsFromHousing { return 1 }
    switch revealStyle {
    case .slide, .unfurl: return 1
    case .bloom, .drift: return isRevealed ? 1 : 0
    }
  }

  /// Bounce lives only in bottom-anchored scale (unfurl, bloom) or in the
  /// shape's own size (growing from the housing); the styles that move
  /// position (slide, drift) stay bounce-free, because a position overshoot
  /// would detach the shape from the screen edge.
  private var revealAnimation: Animation {
    if reduceMotion {
      return Self.reducedMotionFade
    }
    // NotchDrop's spring, verbatim, in both directions — it is symmetric there.
    if growsFromHousing {
      return .interactiveSpring(duration: 0.5, extraBounce: 0.25, blendDuration: 0.125)
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
      y: size.height - HUDNotchGeometry.closedSize(for: screen).height
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
    growsFromHousing: Bool = false,
    clipsContent: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      screen: screen,
      metrics: metrics,
      revealStyle: revealStyle,
      isRevealed: isRevealed,
      size: size,
      growsFromHousing: growsFromHousing,
      clipsContent: clipsContent,
      content: content,
      overlays: { EmptyView() }
    )
  }
}
