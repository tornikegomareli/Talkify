import SwiftUI

/// The concave corner that joins the HUD's side to the bottom edge of the
/// screen.
///
/// A square with a quarter disc removed from its *outer* top corner — the
/// one furthest from the HUD body. That leaves the black full height where it
/// meets the flank, tapering along the screen's bottom edge as it runs out
/// into the bezel, which is what reads as the housing cap flaring wider.
/// Removing the disc from the body-adjacent corner instead mirrors the curve
/// and draws a detached tab with a wedge of wallpaper between it and the body.
struct NotchFilletShape: Shape {
  /// Which side of the HUD body this fillet sits against.
  let side: HorizontalEdge

  nonisolated func path(in rect: CGRect) -> Path {
    let radius = min(rect.width, rect.height)
    // The body's flank is at `maxX` for a leading fillet and `minX` for a
    // trailing one, so the outer corner — where the disc goes — is the
    // opposite edge in each case.
    let corner = CGPoint(
      x: side == .leading ? rect.minX : rect.maxX,
      y: rect.minY
    )
    let disc = Path(
      ellipseIn: CGRect(
        x: corner.x - radius,
        y: corner.y - radius,
        width: radius * 2,
        height: radius * 2
      )
    )

    return Path(rect).subtracting(disc)
  }
}
