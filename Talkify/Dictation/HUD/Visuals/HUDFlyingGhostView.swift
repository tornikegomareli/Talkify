import SwiftUI

/// Where the ghost is on its trip between the notch and its corner, each
/// track 0 (under the camera) to 1 (resting in the corner).
struct HUDGhostTrip {
  /// Along the arc from under the camera to the corner.
  var progress: Double = 0
  /// The ghost's size, as a fraction of its resting size.
  var swell: Double = 0
}

/// Flying Ghost's ghost on the move: it waits under the camera while the shape
/// reveals, flies one curved arc to the stage's leading corner, and flies the
/// same arc home when speech ends, after the draft has left. At rest it is the
/// ghost itself (HUDGhostView), which flies its own small figure-eight.
///
/// Mounted whenever Flying Ghost is selected, not only while listening, so the
/// flight home can play after `showsVoiceVisual` flips false.
struct HUDFlyingGhostView: View {
  /// The shortest keyframe the trip uses. A zero-length keyframe leaves its
  /// track without a value, which hid the ghost entirely.
  static let minimumKeyframe: TimeInterval = 0.001
  /// How long the ghost waits, when speech ends, for the draft to blur away
  /// and the island to ease back before it flies home.
  static let draftExitHold: TimeInterval = 0.35
  /// The island's morph spring, decoded from SpringBoard
  /// (SBSystemApertureTransitionSettings: damping ratio 0.816, response 0.512).
  static let islandSpring = Spring(response: 0.512, dampingRatio: 0.816)
  /// Half the ghost's resting size at full HUD size; it stands 2.25 times this.
  static let restingRadius: CGFloat = 15
  /// The ghost's center from the stage's leading edge at full HUD size. The
  /// stage keeps the draft clear of it.
  static let restingInset: CGFloat = 30

  let content: DictationHUDContent
  let palette: HUDGlowPalette
  let metrics: HUDMetrics
  /// Height of the housing strip the ghost flies out of.
  let housingHeight: CGFloat
  /// Height of the stage the ghost rests in. It grows when the first word
  /// arrives, and the ghost stays on its center line.
  let stageHeight: CGFloat
  /// Words the ghost has eaten so far this session; each new one is a bite.
  var bites = 0
  /// Whether there are words beside the ghost to watch.
  var eating = false

  /// The trip under way, and when it started. Rebuilt from wherever the ghost
  /// is whenever listening starts or stops, so a session that ends mid-flight
  /// turns back from that point instead of jumping.
  @State private var trip = Self.timeline(emerging: false, from: HUDGhostTrip(), after: 0)
  @State private var tripStart = Date.distantPast
  /// Bumped once a trip has finished, so the timeline below re-reads its
  /// pause state and stops drawing once the ghost is back in the notch.
  @State private var settledEpoch = 0

  var body: some View {
    // Home as soon as speech is over, not only when the shape retracts: the
    // retract is too quick to watch a flight under it.
    let listening = content.showsVoiceVisual && !content.isFinalizing
    let alive = content.isAudioAlive
    let _ = settledEpoch
    let running = listening || Date.now.timeIntervalSince(tripStart) < trip.duration
    GeometryReader { proxy in
      TimelineView(.animation(paused: !running)) { context in
        let position = trip.value(time: context.date.timeIntervalSince(tripStart))
        if position.swell > 0.01 {
          ghost(at: position, in: proxy.size, level: alive ? content.audioLevel : 0, alive: alive)
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onChange(of: listening, initial: true) { _, listening in
      let now = Date.now
      let current = trip.value(time: now.timeIntervalSince(tripStart))
      // With a draft on screen the words leave first, then the ghost.
      let hold = !listening && eating ? Self.draftExitHold : 0
      trip = Self.timeline(emerging: listening, from: current, after: hold)
      tripStart = now
    }
    .task(id: tripStart) {
      try? await Task.sleep(for: .seconds(trip.duration))
      settledEpoch += 1
    }
  }

  /// The trip out or home: one eased arc, growing on the way out and shrinking
  /// into the notch on the way home. Out, it waits under the camera while the
  /// shape reveals, so the whole arc is flown in plain sight.
  private static func timeline(
    emerging: Bool,
    from start: HUDGhostTrip,
    after hold: TimeInterval
  ) -> KeyframeTimeline<HUDGhostTrip> {
    KeyframeTimeline(initialValue: start) {
      KeyframeTrack(\.progress) {
        LinearKeyframe(start.progress, duration: max(hold, minimumKeyframe))
        if emerging {
          LinearKeyframe(start.progress, duration: 0.25)
          SpringKeyframe(1, duration: 1.2, spring: Spring(response: 0.75, dampingRatio: 0.86))
        } else {
          SpringKeyframe(0, duration: 0.7, spring: Spring(response: 0.5, dampingRatio: 1))
        }
      }
      KeyframeTrack(\.swell) {
        LinearKeyframe(start.swell, duration: max(hold, minimumKeyframe))
        if emerging {
          SpringKeyframe(1, duration: 0.8, spring: Spring(response: 0.5, dampingRatio: 0.85))
        } else {
          LinearKeyframe(start.swell, duration: 0.3)
          SpringKeyframe(0, duration: 0.4, spring: Spring(response: 0.35, dampingRatio: 1))
        }
      }
    }
  }

  /// A point on the ghost's arc and the lean that goes with it. A cubic curve
  /// that leaves the camera straight down, sweeps low toward the corner and
  /// arrives level, so the ghost swoops rather than sliding. The lean follows
  /// the curve's sideways direction and is zero at both ends, so the ghost
  /// sets off and lands upright.
  static func flight(
    progress: Double,
    from start: CGPoint,
    to end: CGPoint,
    scale: CGFloat
  ) -> (point: CGPoint, lean: Double) {
    let p = min(max(progress, 0), 1)
    let c1 = CGPoint(x: start.x, y: end.y + 10 * scale)
    let c2 = CGPoint(x: end.x + 80 * scale, y: end.y + 8 * scale)
    let u = 1 - p
    let point = CGPoint(
      x: u * u * u * start.x + 3 * u * u * p * c1.x + 3 * u * p * p * c2.x + p * p * p * end.x,
      y: u * u * u * start.y + 3 * u * u * p * c1.y + 3 * u * p * p * c2.y + p * p * p * end.y
    )
    let dx = 3 * u * u * (c1.x - start.x) + 6 * u * p * (c2.x - c1.x) + 3 * p * p * (end.x - c2.x)
    let dy = 3 * u * u * (c1.y - start.y) + 6 * u * p * (c2.y - c1.y) + 3 * p * p * (end.y - c2.y)
    let speed = max(hypot(dx, dy), 0.001)
    return (point, Double(dx / speed) * 16 * sin(.pi * p))
  }

  private func ghost(at position: HUDGhostTrip, in size: CGSize, level: Double, alive: Bool) -> some View {
    let scale = metrics.scale
    let colors = alive
      ? palette.ghostColors
      : Array(repeating: HUDVisualTokens.deadMicAmber, count: 5)
    let camera = CGPoint(x: size.width / 2, y: housingHeight - 4 * scale)
    let corner = CGPoint(x: Self.restingInset * scale, y: housingHeight + stageHeight / 2)
    let radius = Self.restingRadius * scale * position.swell * (1 + 0.14 * level)
    let flight = Self.flight(progress: position.progress, from: camera, to: corner, scale: scale)
    return HUDGhostView(
      colors: colors,
      level: level,
      alive: alive,
      height: radius * 2.25,
      bites: bites,
      eating: eating,
      glowBalance: palette.ghostGlowBalance
    )
    .rotationEffect(.degrees(flight.lean))
    .position(flight.point)
  }
}
