import CoreGraphics
import Testing
@testable import Talkify

struct HUDPlacementTests {
    private let main = HUDScreenSnapshot(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        safeAreaTop: 32,
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil
    )
    private let external = HUDScreenSnapshot(
        id: 2,
        frame: CGRect(x: 1728, y: 200, width: 2560, height: 1440),
        safeAreaTop: 0,
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil
    )

    @Test func selectsDisplayOfKnownTarget() {
        let selected = HUDPlacement.selectDisplay(
            from: [main, external],
            targetDisplayID: 2,
            pointerLocation: CGPoint(x: 100, y: 100)
        )
        #expect(selected == external)
    }

    @Test func fallsBackToPointerDisplayWhenTargetUnknown() {
        let selected = HUDPlacement.selectDisplay(
            from: [main, external],
            targetDisplayID: nil,
            pointerLocation: CGPoint(x: 2000, y: 500)
        )
        #expect(selected == external)
    }

    @Test func fallsBackToPointerDisplayWhenTargetIDNotConnected() {
        let selected = HUDPlacement.selectDisplay(
            from: [main, external],
            targetDisplayID: 99,
            pointerLocation: CGPoint(x: 2000, y: 500)
        )
        #expect(selected == external)
    }

    @Test func pointerAtTopEdgeOfDisplayStillSelectsIt() {
        let selected = HUDPlacement.selectDisplay(
            from: [main, external],
            targetDisplayID: nil,
            pointerLocation: CGPoint(x: 2000, y: 1640)
        )
        #expect(selected == external)
    }

    @Test func fallsBackToMainDisplayWhenPointerOutsideAllDisplays() {
        let selected = HUDPlacement.selectDisplay(
            from: [main, external],
            targetDisplayID: nil,
            pointerLocation: CGPoint(x: -500, y: -500)
        )
        #expect(selected == main)
    }

    @Test func returnsNilWhenNoDisplays() {
        let selected = HUDPlacement.selectDisplay(
            from: [],
            targetDisplayID: 1,
            pointerLocation: .zero
        )
        #expect(selected == nil)
    }
}
