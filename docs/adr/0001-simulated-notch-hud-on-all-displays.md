# Simulated notch HUD on all displays

The Direct Dictation HUD always descends from the top center of its display. Displays without a physical notch get a simulated notch — the same surface with a stand-in footprint (Tilebar uses 185×32) and without the corner fillets that hug a real housing. We rejected the conventional bottom-center floating pill because two surfaces meant two behaviors to design and test, and the top-anchored notch surface is the product's visual identity: external-monitor users would otherwise never see it.

## Consequences

- One surface, one behavior. Only the notch measurement differs per display.
- The proven implementation pattern lives in Tilebar's `NotchIsland` module (`/Users/tgomareli/Development/work/Tilebar-dev/Tilebar/Tilebar/Tilebar/Modules/NotchIsland/`): fixed-size host window whose origin moves but never resizes, measured-vs-simulated notch split in `NotchGeometry`, fillets only against a real housing, interactive-rects hit testing.
- No private APIs: the surface needs only `NSWindow.Level.mainMenu + 3`. A CGS/SkyLight call would rule out App Store distribution.
