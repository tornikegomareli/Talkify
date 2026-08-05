import SwiftUI

/// What the HUD currently says. `@Observable` so the AppKit controller can
/// mutate it and the SwiftUI shell follows.
@MainActor
@Observable
final class DictationHUDContent {
    var text = ""
}

/// The HUD's shape and surface, lifted from Tilebar's NotchIsland shell:
/// square against the top of the screen, rounded below, filleted into the
/// bezel on a real housing, hardware-black fill, drawn shadow. The hosting
/// window never resizes, so the shell top-aligns itself inside whatever frame
/// it is given.
struct DictationHUDShellView: View {
    let screen: HUDScreenSnapshot
    let content: DictationHUDContent

    private var size: CGSize {
        HUDNotchGeometry.contentSize(for: screen)
    }

    private var filletSize: CGFloat {
        HUDNotchGeometry.filletSize(for: screen)
    }

    private var housingShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            bottomLeadingRadius: HUDNotchGeometry.bottomCornerRadius,
            bottomTrailingRadius: HUDNotchGeometry.bottomCornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        textBand
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .background { housing }
            .overlay(alignment: .topLeading) { fillet(.leading) }
            .overlay(alignment: .topTrailing) { fillet(.trailing) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Draft text lives in the band below the housing so it never collides
    /// with the camera on a display with a real notch.
    private var textBand: some View {
        Text(content.text)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            // Tail-only truncation: long drafts show the newest words
            // (CONTEXT.md flags long-draft behavior as undecided; this is the
            // current variant).
            .truncationMode(.head)
            .padding(.horizontal, 24)
            .frame(height: HUDNotchGeometry.textBandHeight)
    }

    private var housing: some View {
        Color.black
            .clipShape(housingShape)
            .shadow(color: .black.opacity(0.35), radius: 11, y: 4)
    }

    /// Sits alongside the body rather than inside it. Absent on a display with
    /// no notch: the flare exists to meet a housing (ADR-0001).
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
