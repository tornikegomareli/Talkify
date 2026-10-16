import SwiftUI

/// Where Intelligence's orb is in its life. Each track runs 0 (a bead under
/// the camera) to 1 (resting on the stage), and they are separate so the drop
/// can fall before it travels and the bead can let go between the two.
struct HUDIntelligenceDrop {
  /// From the bead under the housing down to the stage's center line.
  var fall: Double = 0
  /// From under the camera across to the orb's resting place.
  var glide: Double = 0
  /// The orb's radius, as a fraction of its resting radius.
  var swell: Double = 0
  /// The bead the drop hangs from. While it and the orb are close the shader
  /// grows a neck between them; letting it go is what pinches the drop off.
  var bead: Double = 0
}

/// Intelligence's orb: a moving mesh of the palette that drips out of the
/// notch when a session starts, pinches off, settles at the stage's leading
/// edge and breathes with the voice, then flows back up into the notch when
/// the session ends. The liquid outline is IntelligenceDrop.metal.
///
/// Mounted whenever Intelligence is selected, not only while listening, so the
/// flow back into the notch can play after `showsVoiceVisual` flips false.
struct HUDIntelligenceOrbView: View {
  /// The island's morph spring, decoded from SpringBoard
  /// (SBSystemApertureTransitionSettings: damping ratio 0.816, response 0.512).
  static let islandSpring = Spring(response: 0.512, dampingRatio: 0.816)
  /// The orb's resting radius at full HUD size.
  static let restingRadius: CGFloat = 15
  /// The orb's center from the stage's leading edge at full HUD size. The
  /// shell keeps the draft clear of it.
  static let restingInset: CGFloat = 30

  @Environment(\.displayScale) private var displayScale

  let content: DictationHUDContent
  let palette: HUDGlowPalette
  let metrics: HUDMetrics
  /// Height of the housing strip the orb drips out of.
  let housingHeight: CGFloat
  /// Height of the stage the orb rests in. It grows when the first word
  /// arrives, and the orb stays on its center line.
  let stageHeight: CGFloat
  /// The orb itself, or Talkify's ghost on the same path, without the liquid
  /// neck: a ghost floats down rather than drips.
  var center = HUDIntelligenceCenterStyle.orb

  /// The drop's current path, and when it started. Rebuilt from wherever the
  /// drop is whenever listening starts or stops, so a session that ends
  /// mid-drip reverses from that point instead of jumping.
  @State private var path = Self.timeline(emerging: false, from: HUDIntelligenceDrop())
  @State private var pathStart = Date.distantPast
  /// Bumped once a path has finished, so the timeline below re-reads its
  /// pause state and stops drawing after the drop is back in the notch.
  @State private var settledEpoch = 0

  var body: some View {
    let listening = content.showsVoiceVisual
    let alive = content.isAudioAlive
    let _ = settledEpoch
    let running = listening || Date.now.timeIntervalSince(pathStart) < path.duration
    GeometryReader { proxy in
      TimelineView(.animation(paused: !running)) { context in
        let drop = path.value(time: context.date.timeIntervalSince(pathStart))
        if drop.swell > 0.01 {
          orb(drop: drop, in: proxy.size, level: alive ? content.audioLevel : 0, alive: alive)
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onChange(of: listening, initial: true) { _, listening in
      let now = Date.now
      let current = path.value(time: now.timeIntervalSince(pathStart))
      path = Self.timeline(emerging: listening, from: current)
      pathStart = now
    }
    .task(id: pathStart) {
      try? await Task.sleep(for: .seconds(path.duration))
      settledEpoch += 1
    }
  }

  /// The drop's path in or out. Each track starts from where the drop is.
  private static func timeline(
    emerging: Bool,
    from start: HUDIntelligenceDrop
  ) -> KeyframeTimeline<HUDIntelligenceDrop> {
    KeyframeTimeline(initialValue: start) {
      KeyframeTrack(\.swell) {
        if emerging {
          SpringKeyframe(1, duration: 0.6, spring: islandSpring)
        } else {
          LinearKeyframe(start.swell, duration: 0.35)
          SpringKeyframe(0, duration: 0.35, spring: Spring(response: 0.3, dampingRatio: 1))
        }
      }
      KeyframeTrack(\.fall) {
        if emerging {
          SpringKeyframe(1, duration: 0.8, spring: islandSpring)
        } else {
          LinearKeyframe(start.fall, duration: 0.2)
          SpringKeyframe(0, duration: 0.45, spring: Spring(response: 0.35, dampingRatio: 1))
        }
      }
      // Entering, the bead is held until the drop has fallen clear, then
      // released, so the neck thins and snaps as the orb moves away.
      // Leaving, it returns first so the orb has something to flow into.
      KeyframeTrack(\.bead) {
        if emerging {
          LinearKeyframe(1, duration: 0.12)
          LinearKeyframe(1, duration: 0.16)
          SpringKeyframe(0, duration: 0.5, spring: Spring(response: 0.3, dampingRatio: 1))
        } else {
          LinearKeyframe(start.bead, duration: 0.15)
          SpringKeyframe(1, duration: 0.3, spring: Spring(response: 0.25, dampingRatio: 1))
        }
      }
      KeyframeTrack(\.glide) {
        if emerging {
          LinearKeyframe(start.glide, duration: 0.3)
          SpringKeyframe(1, duration: 0.9, spring: Spring(response: 0.55, dampingRatio: 0.78))
        } else {
          SpringKeyframe(0, duration: 0.45, spring: Spring(response: 0.4, dampingRatio: 0.9))
        }
      }
    }
  }

  /// The drop at one point of its life: a soft halo, the mesh body cut to the
  /// liquid outline, and a highlight that makes it read as a sphere. The ghost
  /// takes the same place and size and keeps its own silhouette.
  @ViewBuilder
  private func orb(drop: HUDIntelligenceDrop, in size: CGSize, level: Double, alive: Bool) -> some View {
    let scale = metrics.scale
    let colors = alive
      ? palette.intelligenceColors
      : Array(repeating: HUDVisualTokens.deadMicAmber, count: 4)
    let pixel = 1 / max(displayScale, 1)
    let bud = CGPoint(x: size.width / 2, y: housingHeight - 4 * scale)
    let rest = CGPoint(
      x: Self.restingInset * scale,
      y: housingHeight + stageHeight / 2
    )
    let radius = Self.restingRadius * scale * drop.swell * (1 + 0.14 * level)
    let centerPoint = CGPoint(
      x: bud.x + (rest.x - bud.x) * drop.glide,
      y: bud.y + (rest.y - bud.y) * drop.fall
    )
    let beadRadius = 9 * scale * drop.bead
    let anchor = CGPoint(x: bud.x, y: housingHeight - beadRadius * 0.3)
    // The neck's reach: closer than this, the orb and the bead share one
    // outline. Below the gap they end at, so the drop really lets go.
    let join = 10 * scale
    let box = CGRect(x: centerPoint.x - radius, y: centerPoint.y - radius, width: 2 * radius, height: 2 * radius)
      .union(CGRect(x: anchor.x - beadRadius, y: anchor.y - beadRadius, width: 2 * beadRadius, height: 2 * beadRadius))
      .insetBy(dx: -join, dy: -join)
    if center == .ghost {
      HUDIntelligenceGhostView(colors: colors, level: level, alive: alive, height: radius * 2.25)
        .position(centerPoint)
    } else {
      ZStack(alignment: .topLeading) {
        Circle()
          .fill(colors[1])
          .frame(width: radius * 2.8, height: radius * 2.8)
          .blur(radius: 10 * scale)
          .opacity(0.4 + 0.2 * level)
          .position(centerPoint)
        HUDIntelligenceMesh(colors: colors, moving: alive)
          .frame(width: box.width, height: box.height)
          .layerEffect(
            ShaderLibrary.intelligenceDrop(
              .float2(CGPoint(x: centerPoint.x - box.minX, y: centerPoint.y - box.minY)),
              .float(radius),
              .float2(CGPoint(x: anchor.x - box.minX, y: anchor.y - box.minY)),
              .float(beadRadius),
              .float(join),
              .float(pixel)
            ),
            maxSampleOffset: .zero
          )
          .saturation(1.25)
          .brightness(0.12 * level)
          .position(x: box.midX, y: box.midY)
        Circle()
          .fill(RadialGradient(
            colors: [.white.opacity(0.42), .white.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: radius * 0.5
          ))
          .frame(width: radius, height: radius)
          .position(x: centerPoint.x - radius * 0.3, y: centerPoint.y - radius * 0.32)
          .brightness(0.2 * level)
      }
    }
  }
}

/// The orb's body: a 3×3 mesh gradient whose inner points drift, so the
/// colors move like a liquid instead of spinning. It freezes on a dead
/// microphone, which is what keeps that state from looking like silence.
struct HUDIntelligenceMesh: View {
  let colors: [Color]
  let moving: Bool

  var body: some View {
    TimelineView(.animation(paused: !moving)) { context in
      let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)) * 1.6
      let c = colors
      MeshGradient(
        width: 3,
        height: 3,
        points: Self.points(at: t),
        // Interleaved so no color owns the center or a whole edge.
        colors: [c[0], c[2], c[1], c[3], c[1], c[2], c[1], c[0], c[3]]
      )
    }
  }

  private static func points(at t: Float) -> [SIMD2<Float>] {
    [
      SIMD2(0, 0), SIMD2(0.5 + 0.15 * sin(t * 0.8), 0), SIMD2(1, 0),
      SIMD2(0, 0.5 + 0.2 * sin(t * 0.9)),
      SIMD2(0.5 + 0.22 * sin(t * 0.7), 0.5 + 0.22 * cos(t * 0.85)),
      SIMD2(1, 0.5 + 0.2 * cos(t * 1.1)),
      SIMD2(0, 1), SIMD2(0.5 + 0.18 * cos(t * 0.6), 1), SIMD2(1, 1),
    ]
  }
}
