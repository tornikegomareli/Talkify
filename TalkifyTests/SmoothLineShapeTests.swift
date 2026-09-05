import CoreGraphics
import SwiftUI
import Testing

@testable import Talkify

/// The concert rest lift is 0.75pt in a 64-point band. Applied unchanged
/// to the 12-point ribbon (and the 40% HUD-size floor) it is larger than
/// quiet speech, so the line never moves.
@Suite("Smooth line shape")
struct SmoothLineShapeTests {
  @Test func quietSpeechMovesInTheRibbon() {
    let samples: [Float] = [0, 0.2, 0.4, 0.25, 0]
    let ribbon = SmoothLineShape(
      samples: samples.map { $0.squareRoot() },
      scrollProgress: 0,
      fill: 0.8
    )
    .path(in: CGRect(x: 0, y: 0, width: 200, height: 12))

    let concertMapping = SmoothLineShape(
      samples: samples,
      scrollProgress: 0
    )
    .path(in: CGRect(x: 0, y: 0, width: 200, height: 12))

    #expect(ribbon.boundingRect.height > 2)
    #expect(ribbon.boundingRect.height > concertMapping.boundingRect.height)
  }

  @Test func theConcertBandStillRestsNearTheMidline() {
    let path = SmoothLineShape(samples: [0, 1, 0], scrollProgress: 0)
      .path(in: CGRect(x: 0, y: 0, width: 100, height: 64))
    #expect(path.boundingRect.maxY > 30)
    #expect(path.boundingRect.maxY < 33)
    #expect(path.boundingRect.minY < 16)
  }
}
