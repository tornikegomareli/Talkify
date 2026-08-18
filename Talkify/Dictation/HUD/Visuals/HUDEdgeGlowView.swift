import SwiftUI

/// The Edge Glow beam, built the way the article's gist builds it: the open
/// silhouette (down the left flank, across the bottom, up the right flank —
/// never the hidden top edge) is stroked with an angular palette gradient
/// three times — a crisp line and two blurred copies — and the shader
/// (EdgeGlow.metal) masks that picture by distance from the origin.
///
/// The article moves the origin with the user's finger; the HUD has no
/// finger, so the origin sweeps the silhouette instead — corner to notch and
/// back, eased at the turnarounds — starting from under the housing at each
/// session start. The mask blooms in on session start, breathes with the
/// microphone level, and drains back when the session ends. A dead microphone
/// swaps the palette for a motionless amber (CONTEXT.md: dead ≠ silent).
///
/// The view stays mounted while the glow variant is selected — the session
/// ramp must keep rendering after `showsVoiceVisual` flips false or the
/// drain-out never plays; the shader is disabled once the ramp reaches zero.
struct HUDEdgeGlowView: View {
  /// Room the blurred strokes get beyond the shape's border.
  nonisolated static let spill: CGFloat = 28
  /// Duration of the bloom-in and drain-out ramps.
  nonisolated static let rampDuration: TimeInterval = 0.4
  /// Stroke width: crisp line at half this, blurred copies at full. The
  /// gist uses 4 on a 240pt capsule; our shape is wider and the mask eats
  /// brightness, so the strokes need more body to read as a beam.
  nonisolated static let lineWidth: Double = 6
  /// Blur of the outer halo stroke (the inner copy runs at half).
  nonisolated static let blurRadius: Double = 12
  /// Seconds for one end-to-end sweep of the silhouette.
  nonisolated static let sweepDuration: TimeInterval = 4.0

  let content: DictationHUDContent
  let settings: DictationSessionSettings
  let metrics: HUDMetrics
  let topFilletRadius: CGFloat

  /// The beam's own dimensions follow the HUD size: the same 6pt stroke and
  /// 28pt spill read as a much heavier beam once the shape is smaller.
  private var spill: CGFloat { Self.spill * metrics.scale }

  /// Reset on every session start so the sweep begins at bottom-center,
  /// directly under the housing.
  @State private var sweepStart = Date()

  /// Mirrors `content.showsVoiceVisual` for the ramp's keyframe trigger.
  /// The trigger must *change* for the keyframes to play; a view mounted
  /// while listening is already true (the Settings preview switching back
  /// to Edge Glow) would otherwise stay at progress 0 forever. The mirror
  /// starts false and flips on mount, so mounting mid-session blooms too.
  @State private var ramped = false

  var body: some View {
    GeometryReader { proxy in
      let listening = content.showsVoiceVisual
      TimelineView(.animation(paused: !listening)) { context in
        // Plain values for the @Sendable keyframeAnimator content
        // closure; the body re-evaluates on every level tick and
        // timeline frame, so they stay fresh.
        let size = proxy.size
        let alive = content.isAudioAlive
        let level = content.audioLevel
        // The voice shows in two registers (the feel-test pick):
        // brightness — resting near the gist's constant 3.0 so the
        // halo never starves, flaring with speech — and body, the
        // strokes swelling up to double.
        let amplitude = alive ? 1.8 + 1.2 * level : 1.5
        let lineWidth = Self.lineWidth * Double(metrics.scale) * (1 + level)
        let blurRadius = Self.blurRadius * Double(metrics.scale) * (1 + 0.5 * level)
        let origin = Self.sweepOrigin(
          at: context.date.timeIntervalSince(sweepStart),
          in: size,
          cornerRadius: metrics.bottomCornerRadius,
          topFilletRadius: topFilletRadius,
          inset: spill
        )
        HUDGlowSilhouetteShape(
          cornerRadius: metrics.bottomCornerRadius,
          topFilletRadius: topFilletRadius,
          inset: spill
        )
        .glow(
          fill: alive
            ? settings.glowPalette.stroke
            : AnyShapeStyle(HUDVisualTokens.deadMicAmber),
          lineWidth: lineWidth,
          blurRadius: blurRadius
        )
        .keyframeAnimator(
          initialValue: 0.0,
          trigger: ramped
        ) { view, progress in
          view.colorEffect(
            ShaderLibrary.edgeGlow(
              .float2(origin),
              .float2(size),
              .float(amplitude),
              .float(progress)
            ),
            isEnabled: progress > 0 || listening
          )
        } keyframes: { _ in
          // No MoveKeyframe: the track starts from the current
          // value, so a session ending mid-bloom reverses smoothly.
          if ramped {
            LinearKeyframe(1.0, duration: Self.rampDuration)
          } else {
            LinearKeyframe(0.0, duration: Self.rampDuration)
          }
        }
      }
    }
    .padding(.horizontal, -spill)
    .padding(.top, -spill)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onChange(of: content.sessionEpoch) {
      sweepStart = .now
    }
    .onChange(of: content.showsVoiceVisual, initial: true) { _, listening in
      ramped = listening
    }
  }

  /// The eased ping-pong position along the silhouette at time `t` (left
  /// tip → bottom → right tip → back), phase-shifted so t = 0 lands at
  /// bottom-center. Shared with the particle cloud so the motes chase the
  /// same point the beam highlights.
  nonisolated static func sweepFraction(at t: TimeInterval) -> Double {
    let phase = ((t / sweepDuration) + 0.5)
      .truncatingRemainder(dividingBy: 2.0)
    let linear = phase < 1.0 ? phase : 2.0 - phase
    // Mostly linear: full smoothstep easing parks the origin at each
    // flank tip (zero velocity there), which reads as the glow stopping
    // to wait for the particles. A light blend keeps constant travel
    // with just a softened turnaround.
    let eased = linear * linear * (3.0 - 2.0 * linear)
    return linear + (eased - linear) * 0.3
  }

  /// Where the mask origin sits at time `t`, in this view's coordinates.
  nonisolated private static func sweepOrigin(
    at t: TimeInterval,
    in size: CGSize,
    cornerRadius: CGFloat,
    topFilletRadius: CGFloat,
    inset: CGFloat
  ) -> CGPoint {
    HUDGlowSilhouetteShape.point(
      atArcFraction: sweepFraction(at: t),
      cornerRadius: cornerRadius,
      topFilletRadius: topFilletRadius,
      inset: inset,
      in: size
    )
  }
}

/// The HUD's open silhouette as a strokable path: up the left flank, across
/// the top run with its two corner arcs, down the right flank. The bottom
/// edge is where the housing cap meets the screen edge and is never drawn.
struct HUDGlowSilhouetteShape: Shape {
  var cornerRadius: CGFloat
  /// Radius of the physical housing fillets. Zero keeps the square
  /// corners used by external displays without a measured housing.
  var topFilletRadius: CGFloat = 0
  /// Distance from the view's left/right/top edges to the silhouette
  /// (the spill the blurred strokes need).
  var inset: CGFloat

  nonisolated func path(in rect: CGRect) -> Path {
    // The housing cap meets the bottom edge, so the open silhouette is the
    // top-housing form's vertical mirror: the drawn run is the top of the
    // pill and the fillets sit at its bottom corners.
    topHousingPath(in: rect)
      .applying(CGAffineTransform(translationX: 0, y: rect.height).scaledBy(x: 1, y: -1))
  }

  /// The silhouette drawn as if the housing were at the top — the form this
  /// shape is the vertical reflection of.
  nonisolated private func topHousingPath(in rect: CGRect) -> Path {
    let left = rect.minX + inset
    let right = rect.maxX - inset
    let bottom = rect.maxY - inset
    let radius = min(cornerRadius, max(0, (bottom - rect.minY) / 2))
    let topRadius = min(topFilletRadius, max(0, (bottom - rect.minY) / 2))

    var path = Path()
    if topRadius > 0 {
      path.move(to: CGPoint(x: left - topRadius, y: rect.minY))
      path.addArc(
        tangent1End: CGPoint(x: left, y: rect.minY),
        tangent2End: CGPoint(x: left, y: rect.minY + topRadius),
        radius: topRadius
      )
    } else {
      path.move(to: CGPoint(x: left, y: rect.minY))
    }
    path.addLine(to: CGPoint(x: left, y: bottom - radius))
    path.addArc(
      tangent1End: CGPoint(x: left, y: bottom),
      tangent2End: CGPoint(x: left + radius, y: bottom),
      radius: radius
    )
    path.addLine(to: CGPoint(x: right - radius, y: bottom))
    path.addArc(
      tangent1End: CGPoint(x: right, y: bottom),
      tangent2End: CGPoint(x: right, y: bottom - radius),
      radius: radius
    )
    if topRadius > 0 {
      path.addArc(
        tangent1End: CGPoint(x: right, y: rect.minY),
        tangent2End: CGPoint(x: right + topRadius, y: rect.minY),
        radius: topRadius
      )
    } else {
      path.addLine(to: CGPoint(x: right, y: rect.minY))
    }
    return path
  }

  /// The point at `fraction` (0…1) of the silhouette's arc length, from the
  /// left flank's tip to the right flank's tip. Mirrors `path(in:)`.
  nonisolated static func point(
    atArcFraction fraction: Double,
    cornerRadius: CGFloat,
    topFilletRadius: CGFloat = 0,
    inset: CGFloat,
    in size: CGSize
  ) -> CGPoint {
    let housed = topHousingPoint(
      atArcFraction: fraction,
      cornerRadius: cornerRadius,
      topFilletRadius: topFilletRadius,
      inset: inset,
      in: size
    )
    return CGPoint(x: housed.x, y: size.height - housed.y)
  }

  /// The top-housing form of `point(atArcFraction:)`, before the vertical
  /// mirror the bottom cap reflects it across.
  nonisolated private static func topHousingPoint(
    atArcFraction fraction: Double,
    cornerRadius: CGFloat,
    topFilletRadius: CGFloat,
    inset: CGFloat,
    in size: CGSize
  ) -> CGPoint {
    let left = inset
    let right = size.width - inset
    let bottom = size.height - inset
    let radius = min(cornerRadius, bottom / 2)
    let topRadius = min(topFilletRadius, bottom / 2)

    let flank = max(0, bottom - radius - topRadius)
    let topCorner = Double.pi * topRadius / 2
    let corner = Double.pi * radius / 2
    let run = (right - left) - 2 * radius
    let total = 2 * flank + 2 * corner + run + 2 * topCorner
    var distance = fraction.clamped(to: 0...1) * total
    if topRadius > 0 {
      if distance < topCorner {
        let angle = -Double.pi / 2 + distance / topRadius
        return CGPoint(
          x: left - topRadius + topRadius * cos(angle),
          y: topRadius + topRadius * sin(angle)
        )
      }
      distance -= topCorner
    }
    if distance < flank {
      return CGPoint(x: left, y: topRadius + distance)
    }
    distance -= flank
    if distance < corner {
      let angle = Double.pi - distance / radius
      return CGPoint(
        x: left + radius + radius * cos(angle),
        y: bottom - radius + radius * sin(angle)
      )
    }
    distance -= corner
    if distance < run {
      return CGPoint(x: left + radius + distance, y: bottom)
    }
    distance -= run
    if distance < corner {
      let angle = Double.pi / 2 - distance / radius
      return CGPoint(
        x: right - radius + radius * cos(angle),
        y: bottom - radius + radius * sin(angle)
      )
    }
    distance -= corner
    if distance < flank {
      return CGPoint(x: right, y: bottom - radius - distance)
    }
    distance -= flank
    if topRadius > 0 {
      let angle = Double.pi + distance / topRadius
      return CGPoint(
        x: right + topRadius + topRadius * cos(angle),
        y: topRadius + topRadius * sin(angle)
      )
    }
    return CGPoint(x: right, y: 0)
  }
}

private extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    min(max(self, range.lowerBound), range.upperBound)
  }
}

// The gist's GlowModifier, verbatim: a crisp stroke plus two blurred copies.
private extension Shape {
  func glow(
    fill: some ShapeStyle,
    lineWidth: Double,
    blurRadius: Double = 8.0,
    lineCap: CGLineCap = .round
  ) -> some View {
    stroke(style: StrokeStyle(lineWidth: lineWidth / 2, lineCap: lineCap))
      .fill(fill)
      .overlay {
        stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
          .fill(fill)
          .blur(radius: blurRadius)
      }
      .overlay {
        stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
          .fill(fill)
          .blur(radius: blurRadius / 2)
      }
  }
}

#Preview("Edge glow · live") {
  HUDShellPreviewHarness(visual: .glow)
}

#Preview("Edge glow · session cycle") {
  HUDShellPreviewHarness(visual: .glow, simulatesSessionCycle: true)
}

#Preview("Edge glow · dead mic") {
  HUDShellPreviewHarness(visual: .glow, micAlive: false)
}
