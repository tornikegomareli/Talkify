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

    @State private var isRotating = false

    var body: some View {
        let alive = content.isAudioAlive
        // The orb breathes with the voice on top of its fit-to-band scale.
        let scale = HUDNotchGeometry.waveBandHeight / Self.artworkSide
            * (1 + 0.15 * content.audioLevel)
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
        .scaleEffect(scale)
        // Dead microphone: the color life drains to a static amber tint
        // (CONTEXT.md: dead ≠ silent).
        .saturation(alive ? 1 : 0)
        .colorMultiply(alive ? .white : Color(red: 1.0, green: 0.6, blue: 0.16))
        .frame(
            width: HUDNotchGeometry.waveBandHeight,
            height: HUDNotchGeometry.waveBandHeight
        )
        .accessibilityHidden(true)
    }
}

#Preview("Siri orb · live") {
    HUDShellPreviewHarness(visual: .siriOrb)
}

#Preview("Siri orb · dead mic") {
    HUDShellPreviewHarness(visual: .siriOrb, micAlive: false)
}
