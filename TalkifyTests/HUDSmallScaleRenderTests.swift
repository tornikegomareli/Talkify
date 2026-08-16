import SwiftUI
import Testing

@testable import Talkify

/// Renders the smallest HUD sizes on a display without a notch, which is the
/// only place they apply. Writes PNGs to `TALKIFY_RENDER_DIR` when it is set.
@MainActor
@Suite("Smallest HUD sizes")
struct HUDSmallScaleRenderTests {
  private var externalScreen: HUDScreenSnapshot {
    HUDScreenSnapshot(
      id: 2,
      frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
      safeAreaTop: 0,
      auxiliaryTopLeftArea: nil,
      auxiliaryTopRightArea: nil
    )
  }

  /// The preview stands in for a notched MacBook until the picked size is one
  /// a notch cannot show, and then for a display without one — so the slider
  /// keeps changing something visible all the way to its minimum.
  @Test func thePreviewFollowsTheSliderToItsMinimum() {
    let store = AppSettings.previewStore()
    let notchedFloor = HUDNotchGeometry.minimumScale(for: HUDPreviewScreen.notched)

    var widths: [CGFloat] = []
    for percent in stride(from: 100, through: 20, by: -5) {
      store.hudScale = Double(percent) / 100
      let card = SettingsPreviewCard(settings: store)
      let metrics = store.sessionSettings.hudMetrics
        .atLeast(HUDNotchGeometry.minimumScale(for: card.previewScreenForTesting))
      widths.append(metrics.contentWidth)
    }

    // Strictly decreasing: no step of the slider leaves the preview unchanged.
    #expect(zip(widths, widths.dropFirst()).allSatisfy { $0 > $1 })
    #expect(notchedFloor > HUDMetrics.minimumScale)
  }

  @Test(arguments: [0.4, 0.3, 0.25, 0.2])
  func aSmallHUDStillRendersOnADisplayWithoutANotch(scale: Double) throws {
    let store = AppSettings.previewStore()
    store.hudScale = scale
    let session = store.sessionSettings
    #expect(session.hudMetrics.scale == CGFloat(scale))

    let content = DictationHUDContent()
    content.text = "Listening…"
    content.isRevealed = true

    guard let directory = ProcessInfo.processInfo.environment["TALKIFY_RENDER_DIR"]
      .map({ URL(filePath: $0) })
    else { return }

    let renderer = ImageRenderer(
      content: DictationHUDShellView(
        screen: externalScreen,
        settings: session,
        content: content
      )
      .frame(width: 420, height: 110)
      .background(Color(white: 0.55))
    )
    renderer.scale = 3
    guard let image = renderer.cgImage else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let bitmap = NSBitmapImageRep(cgImage: image)
    if let data = bitmap.representation(using: .png, properties: [:]) {
      try data.write(to: directory.appending(path: "small-\(Int(scale * 100)).png"))
    }
  }
}
