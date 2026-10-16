import SwiftUI

/// Talkify's ghost as a shape, after the app icon: a dome, straight sides, and
/// a hem of three scallops, one at each corner and one in the middle.
struct HUDGhostShape: Shape {
  /// Shifts the hem's scallops sideways, in radians, so the hem can sway.
  var sway: Double = 0

  nonisolated func path(in rect: CGRect) -> Path {
    let radius = rect.width / 2
    let depth = rect.height * 0.09
    let hemTop = rect.maxY - depth
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
    path.addArc(
      tangent1End: CGPoint(x: rect.minX, y: rect.minY),
      tangent2End: CGPoint(x: rect.midX, y: rect.minY),
      radius: radius
    )
    path.addArc(
      tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
      tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius),
      radius: radius
    )
    // The hem, right to left: two periods of a cosine put the scallops'
    // lowest points at both corners and the middle.
    let steps = 36
    for step in 0...steps {
      let fraction = 1 - Double(step) / Double(steps)
      let y = hemTop + depth * 0.5 * (1 + cos(2 * .pi * 2 * fraction + sway))
      path.addLine(to: CGPoint(x: rect.minX + rect.width * fraction, y: y))
    }
    path.closeSubpath()
    return path
  }
}

/// The ghost Intelligence can show in place of the orb, filled with the
/// palette's moving mesh. It blinks, glances side to side, floats, sways its
/// hem, and opens its eyes wider while the user speaks. On a dead microphone it
/// stops in amber with its eyes half shut.
struct HUDIntelligenceGhostView: View {
  /// Width over height, as in the app icon.
  static let aspect: CGFloat = 0.8

  let colors: [Color]
  let level: Double
  let alive: Bool
  let height: CGFloat

  var body: some View {
    TimelineView(.animation(paused: !alive)) { context in
      let t = context.date.timeIntervalSinceReferenceDate
      let width = height * Self.aspect
      let ghost = HUDGhostShape(sway: alive ? 0.5 * sin(t * 2.3) : 0)
      ZStack {
        ghost
          .fill(colors[1])
          .blur(radius: height * 0.3)
          .opacity(0.4 + 0.2 * level)
        HUDIntelligenceMesh(colors: colors, moving: alive)
          .mask(ghost)
        ghost
          .fill(RadialGradient(
            colors: [.white.opacity(0.35), .white.opacity(0)],
            center: UnitPoint(x: 0.32, y: 0.22),
            startRadius: 0,
            endRadius: width * 0.6
          ))
        eyes(at: t, width: width)
      }
      .frame(width: width, height: height)
      .offset(y: alive ? -height * 0.04 * sin(t * 2.0) : 0)
    }
    .accessibilityHidden(true)
  }

  private func eyes(at t: TimeInterval, width: CGFloat) -> some View {
    let openness = alive ? Self.openness(at: t) : 0.4
    let glance = alive ? sin(t * 0.6) * width * 0.05 : 0
    return HStack(spacing: width * 0.16) {
      Capsule()
      Capsule()
    }
    .foregroundStyle(.black.opacity(0.88))
    .frame(width: width * 0.36, height: height * 0.22 * openness * (1 + 0.25 * level))
    .offset(x: glance, y: -height * 0.08)
  }

  /// How open the eyes are at `t`: fully, apart from a quick blink every few
  /// seconds.
  static func openness(at t: TimeInterval) -> Double {
    let phase = t.truncatingRemainder(dividingBy: blinkPeriod)
    guard phase < blinkDuration else { return 1 }
    return 1 - 0.9 * sin(.pi * phase / blinkDuration)
  }

  static let blinkPeriod = 3.4
  static let blinkDuration = 0.16
}
