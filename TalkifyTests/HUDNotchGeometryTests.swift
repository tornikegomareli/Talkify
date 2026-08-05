import CoreGraphics
import Testing
@testable import Talkify

struct HUDNotchGeometryTests {
    private let notched = HUDScreenSnapshot(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32,
        auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663.5, height: 32),
        auxiliaryTopRightArea: CGRect(x: 848.5, y: 950, width: 663.5, height: 32)
    )
    private let external = HUDScreenSnapshot(
        id: 2,
        frame: CGRect(x: 1512, y: 200, width: 2560, height: 1440),
        safeAreaTop: 0,
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil
    )

    @Test func measuresNotchBySubtractingAuxiliaryAreas() {
        let size = HUDNotchGeometry.measuredClosedSize(for: notched)
        #expect(size == CGSize(width: 185, height: 32))
    }

    @Test func measurementIsNilWithoutAuxiliaryAreas() {
        #expect(HUDNotchGeometry.measuredClosedSize(for: external) == nil)
    }

    @Test func measurementIsNilWithZeroSafeArea() {
        let flat = HUDScreenSnapshot(
            id: 3,
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            safeAreaTop: 0,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 1085, width: 700, height: 32),
            auxiliaryTopRightArea: CGRect(x: 1028, y: 1085, width: 700, height: 32)
        )
        #expect(HUDNotchGeometry.measuredClosedSize(for: flat) == nil)
    }

    @Test func closedSizeFallsBackToSimulatedFootprint() {
        #expect(HUDNotchGeometry.closedSize(for: external) == CGSize(width: 185, height: 32))
    }

    @Test func hasMeasuredNotchReflectsMeasurement() {
        #expect(HUDNotchGeometry.hasMeasuredNotch(for: notched))
        #expect(!HUDNotchGeometry.hasMeasuredNotch(for: external))
    }

    @Test func contentSizeAddsTextBandBelowHousing() {
        let size = HUDNotchGeometry.contentSize(for: notched)
        #expect(size == CGSize(width: 540, height: 32 + HUDNotchGeometry.textBandHeight))
    }

    @Test func windowFrameIsTopCenterWithShadowSlack() {
        let frame = HUDNotchGeometry.windowFrame(for: notched)
        let expectedWidth: CGFloat = 540 + 44 * 2
        let expectedHeight = HUDNotchGeometry.contentSize(for: notched).height + 44
        #expect(frame.width == expectedWidth)
        #expect(frame.height == expectedHeight)
        #expect(frame.midX == notched.frame.midX)
        #expect(frame.maxY == notched.frame.maxY)
    }

    @Test func windowFrameClampsToNarrowScreen() {
        let narrow = HUDScreenSnapshot(
            id: 4,
            frame: CGRect(x: 0, y: 0, width: 600, height: 800),
            safeAreaTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )
        let frame = HUDNotchGeometry.windowFrame(for: narrow)
        #expect(frame.width == 600)
        #expect(frame.midX == 300)
    }

    @Test func filletsExistOnlyAgainstRealHousing() {
        #expect(HUDNotchGeometry.filletSize(for: notched) > 0)
        #expect(HUDNotchGeometry.filletSize(for: external) == 0)
    }
}
