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

/// The ghost's flight: a phase that advances with time at a speed set by the
/// voice, and an energy that follows the voice smoothly. Integrating the phase,
/// rather than multiplying the clock by a speed, is what lets the voice speed
/// the flight up without the ghost jumping to a new point on its path.
@MainActor
final class HUDGhostFlight {
  private(set) var phase = 0.0
  private(set) var energy = 0.0
  private var last: Date?

  func advance(to date: Date, level: Double) {
    // Capped so a pause (a dead microphone, a hidden HUD) resumes in place.
    let dt = min(last.map { date.timeIntervalSince($0) } ?? 0, 0.1)
    last = date
    energy += (level - energy) * min(1, dt * 3)
    phase += dt * (1 + 1.6 * energy)
  }
}

/// Where the ghost is on its flight path, as fractions of its height and in
/// degrees. A figure-eight drift, a lean into the sideways motion, a stretch
/// along the vertical one, and a hem wave that travels instead of swinging.
/// More voice widens the path and deepens the lean.
struct HUDGhostPose: Equatable {
  var x: Double
  var y: Double
  var tilt: Double
  var stretch: Double
  var hemWave: Double

  static func at(phase: Double, energy: Double) -> HUDGhostPose {
    let sideways = 0.9 * phase
    let upDown = 1.8 * phase + 0.6
    return HUDGhostPose(
      x: (0.06 + 0.1 * energy) * sin(sideways),
      y: (0.045 + 0.07 * energy) * sin(upDown),
      // The lean follows the sideways velocity, the derivative of x.
      tilt: (3 + 7 * energy) * cos(sideways),
      // A little taller while rising or falling fastest.
      stretch: 1 + (0.02 + 0.04 * energy) * cos(upDown),
      hemWave: -3.2 * phase
    )
  }
}

/// The ghost Intelligence can show in place of the orb, filled with the
/// palette's moving mesh. It flies a gentle figure-eight that widens with the
/// voice, leans into its motion, flutters its hem, blinks, and opens its eyes
/// wider while the user speaks. On a dead microphone it stops in amber with
/// its eyes half shut.
struct HUDIntelligenceGhostView: View {
  /// Width over height, as in the app icon.
  static let aspect: CGFloat = 0.8

  let colors: [Color]
  let level: Double
  let alive: Bool
  let height: CGFloat
  /// Words eaten so far. Each change is a bite: the mouth opens as the word
  /// arrives and the ghost chomps.
  var bites = 0
  /// Whether there are words beside it; it watches them while there are.
  var eating = false

  @State private var flight = HUDGhostFlight()
  @State private var biteStart = Date.distantPast

  var body: some View {
    TimelineView(.animation(paused: !alive)) { context in
      let t = context.date.timeIntervalSinceReferenceDate
      let _ = flight.advance(to: context.date, level: alive ? level : 0)
      let pose = HUDGhostPose.at(phase: flight.phase, energy: flight.energy)
      let chomp = Self.chomp(at: context.date.timeIntervalSince(biteStart))
      let width = height * Self.aspect
      let ghost = HUDGhostShape(sway: pose.hemWave)
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
        eyes(at: t, width: width, glance: eating ? 0.8 : pose.tilt / 10, squint: chomp)
        mouth(width: width, open: chomp)
      }
      .frame(width: width, height: height)
      .scaleEffect(
        x: (1 + 0.08 * chomp) / pose.stretch,
        y: (1 - 0.06 * chomp) * pose.stretch,
        anchor: .bottom
      )
      // Leans toward the words it is eating.
      .rotationEffect(.degrees(pose.tilt + 6 * chomp))
      .offset(x: pose.x * height, y: pose.y * height)
    }
    .accessibilityHidden(true)
    .onChange(of: bites) { old, new in
      if new > old { biteStart = .now }
    }
  }

  /// The eyes glance the way the ghost leans, so it looks where it flies, or
  /// toward the words while there are some. They squint as it bites.
  private func eyes(at t: TimeInterval, width: CGFloat, glance: Double, squint: Double) -> some View {
    let openness = (alive ? Self.openness(at: t) : 0.4) * (1 - 0.6 * squint)
    return HStack(spacing: width * 0.16) {
      Capsule()
      Capsule()
    }
    .foregroundStyle(.black.opacity(0.88))
    .frame(width: width * 0.36, height: height * 0.22 * openness * (1 + 0.25 * level))
    .offset(x: glance * width * 0.05, y: -height * 0.08)
  }

  /// A mouth that only exists mid-bite.
  private func mouth(width: CGFloat, open: Double) -> some View {
    Ellipse()
      .fill(.black.opacity(0.88))
      .frame(width: width * 0.22, height: height * 0.16 * open)
      .offset(y: height * 0.12)
      .opacity(open > 0.02 ? 1 : 0)
  }

  /// How far into a bite the ghost is, `elapsed` seconds after a word reached
  /// it: the mouth opens fast, holds as the word goes in, and closes.
  static func chomp(at elapsed: TimeInterval) -> Double {
    guard elapsed >= 0, elapsed < chompDuration else { return 0 }
    return sin(.pi * elapsed / chompDuration)
  }

  static let chompDuration = 0.38

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
