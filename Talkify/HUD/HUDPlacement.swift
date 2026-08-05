import CoreGraphics

/// Pure placement math for the Direct Dictation HUD. UI-free so tests can
/// drive it with plain display bounds, a pointer location, and an optional
/// target display ID.
enum HUDPlacement {
    struct Display: Equatable, Sendable {
        let id: CGDirectDisplayID
        /// Display frame in global screen coordinates (bottom-left origin, y up).
        let frame: CGRect
    }

    /// Selection order: display of the focused target if known, else the
    /// display containing the pointer, else the main display. The first
    /// element of `displays` is the main display, matching `NSScreen.screens`.
    static func selectDisplay(
        from displays: [Display],
        targetDisplayID: CGDirectDisplayID?,
        pointerLocation: CGPoint
    ) -> Display? {
        if let targetDisplayID,
           let target = displays.first(where: { $0.id == targetDisplayID }) {
            return target
        }
        if let pointer = displays.first(where: { contains($0.frame, pointerLocation) }) {
            return pointer
        }
        return displays.first
    }

    /// Unlike `CGRect.contains`, treats the top and right edges as inside:
    /// `NSEvent.mouseLocation` reports exactly `maxY` when the cursor rests
    /// at the top edge of a screen.
    private static func contains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }

    /// Panel frame anchored to the top center of the display.
    static func panelFrame(on display: Display, panelSize: CGSize) -> CGRect {
        CGRect(
            x: display.frame.midX - panelSize.width / 2,
            y: display.frame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}
