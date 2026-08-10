import SwiftUI

/// Prototype voice visual: the Siri orb from GetStream's
/// purposeful-ios-animations (ListeningSiriAnimation), ported layer-for-layer
/// — ten artwork blobs spun through rotation, hue rotation, and 3D tilts over
/// a 12-second loop — and adapted to the HUD: scaled into the visual band,
/// breathing with the microphone level, desaturated to amber on a dead
/// microphone. The demo's drop-shadow layer is omitted: it is invisible on
/// the HUD's black housing and would spill past the shape's bottom edge.
///
/// PROTOTYPE ARTWORK: the siri-* imagesets have no license and imitate
/// Apple's Siri orb — replace or clear before any release
/// (LICENSE-ARTWORK.txt).
struct HUDSiriOrbView: View {
  /// Intrinsic side of the orb body (siri-icon-bg); the composition
  /// scales from it into the band.
  private static let artworkSide: CGFloat = 503.6

  let content: DictationHUDContent
  /// The orb's rendered diameter; the shell sizes it to the notch island.
  let side: CGFloat

  @State private var isRotating = false
  @State private var spin = SpinIntegrator()

  var body: some View {
    TimelineView(.animation) { context in
      let alive = content.isAudioAlive
      let level = alive ? content.audioLevel : 0
      // The orb breathes with the voice on top of its fit scale,
      // flares brighter and more saturated while talking, and spins
      // faster — the integrator keeps speed changes smooth.
      let scale = side / Self.artworkSide * (1 + 0.3 * level)
      let angle = spin.advance(to: context.date, level: level)
      orb(alive: alive, scale: scale, spinAngle: angle)
        .brightness(0.3 * level)
        .saturation(alive ? 1 + 0.6 * level : 0)
    }
    .frame(width: side, height: side)
    .accessibilityHidden(true)
  }

  private func orb(alive: Bool, scale: Double, spinAngle: Double) -> some View {
    ZStack {
      ZStack {
        Image("siri-icon-bg")
        Image("siri-pink-top")
          .rotationEffect(.degrees(isRotating ? 320 : -360))
          .hueRotation(.degrees(isRotating ? -270 : 60))

        Image("siri-pink-left")
          .rotationEffect(.degrees(isRotating ? -360 : 180))
          .hueRotation(.degrees(isRotating ? -220 : 300))

        Image("siri-blue-middle")
          .rotationEffect(.degrees(isRotating ? -360 : 420))
          .hueRotation(.degrees(isRotating ? -150 : 0))
          .rotation3DEffect(
            .degrees(75),
            axis: (x: isRotating ? 1 : 5, y: 0, z: 0)
          )

        Image("siri-blue-right")
          .rotationEffect(.degrees(isRotating ? -360 : 420))
          .hueRotation(.degrees(isRotating ? 720 : -50))
          .rotation3DEffect(
            .degrees(75),
            axis: (x: 1, y: 0, z: isRotating ? -5 : 15)
          )

        Image("siri-intersect")
          .rotationEffect(.degrees(isRotating ? 30 : -420))
          .hueRotation(.degrees(isRotating ? 0 : 720))
          .rotation3DEffect(
            .degrees(15),
            axis: (x: 1, y: 1, z: 1),
            perspective: isRotating ? 5 : -5
          )

        Image("siri-green-right")
          .rotationEffect(.degrees(isRotating ? -300 : 360))
          .hueRotation(.degrees(isRotating ? 300 : -15))
          .rotation3DEffect(
            .degrees(15),
            axis: (x: 1, y: isRotating ? -1 : 1, z: 0),
            perspective: isRotating ? -1 : 1
          )

        Image("siri-green-left")
          .rotationEffect(.degrees(isRotating ? 360 : -360))
          .hueRotation(.degrees(isRotating ? 180 : 50))
          .rotation3DEffect(
            .degrees(75),
            axis: (x: 1, y: isRotating ? -5 : 15, z: 0)
          )

        Image("siri-bottom-pink")
          .rotationEffect(.degrees(isRotating ? 400 : -360))
          .hueRotation(.degrees(isRotating ? 0 : 230))
          .opacity(0.25)
          .blendMode(.multiply)
          .rotation3DEffect(
            .degrees(75),
            axis: (x: 5, y: isRotating ? 1 : -45, z: 0)
          )
      }
      .blendMode(isRotating ? .hardLight : .difference)

      Image("siri-highlight")
        .rotationEffect(.degrees(isRotating ? 360 : 250))
        .hueRotation(.degrees(isRotating ? 0 : 230))
        .padding()
        .onAppear {
          withAnimation(
            .easeInOut(duration: 12).repeatForever(autoreverses: false)
          ) {
            isRotating.toggle()
          }
        }
    }
    .rotationEffect(.degrees(spinAngle))
    .scaleEffect(scale)
    // Dead microphone: the color life drains to a static amber tint
    // (CONTEXT.md: dead ≠ silent).
    .colorMultiply(alive ? .white : HUDVisualTokens.deadMicAmber)
  }
}

/// Integrates the voice-driven spin: a slow idle drift plus a boost while
/// talking. Integrating (instead of mapping level straight to an angle)
/// makes speed follow the voice while the motion stays continuous.
@MainActor
private final class SpinIntegrator {
  private var angle = 0.0
  private var lastDate: Date?

  func advance(to date: Date, level: Double) -> Double {
    let dt = lastDate.map { min(max(date.timeIntervalSince($0), 0), 0.1) } ?? 0
    lastDate = date
    angle += dt * (14 + 260 * level)
    return angle
  }
}

#Preview("Siri orb · live") {
  HUDShellPreviewHarness(visual: .glow, glowCenter: .siriOrb)
}

#Preview("Siri orb · dead mic") {
  HUDShellPreviewHarness(visual: .glow, glowCenter: .siriOrb, micAlive: false)
}
