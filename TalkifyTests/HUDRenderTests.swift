import SwiftUI
import Testing

@testable import Talkify

/// Renders HUD surfaces to PNGs so a change to the shape, the bands or the
/// drop states can be looked at rather than inferred from a diff. Writes to
/// `TALKIFY_RENDER_DIR` when it is set; otherwise it only asserts that each
/// surface renders at the size the geometry promises.
@MainActor
@Suite("HUD rendering")
struct HUDRenderTests {
  private var outputDirectory: URL? {
    ProcessInfo.processInfo.environment["TALKIFY_RENDER_DIR"].map { URL(filePath: $0) }
  }

  /// A 14" MacBook Pro's numbers, which are also the simulated notch's.
  private var notchedScreen: HUDScreenSnapshot {
    HUDScreenSnapshot(
      id: 1,
      frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
      safeAreaTop: 32,
      auxiliaryTopLeftArea: CGRect(x: 0, y: 0, width: 663.5, height: 32),
      auxiliaryTopRightArea: CGRect(x: 848.5, y: 0, width: 663.5, height: 32)
    )
  }

  private var settings: DictationSessionSettings {
    AppSettings.previewStore().sessionSettings
  }

  private func render(_ view: some View, named name: String) throws -> CGSize {
    let renderer = ImageRenderer(content: view.frame(width: 640, height: 260))
    renderer.scale = 2
    let image = try #require(renderer.cgImage)

    if let directory = outputDirectory {
      try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let bitmap = NSBitmapImageRep(cgImage: image)
      if let data = bitmap.representation(using: .png, properties: [:]) {
        try data.write(to: directory.appending(path: "\(name).png"))
      }
    }
    return CGSize(width: image.width, height: image.height)
  }

  @Test func theDictationShellRendersAMessage() throws {
    let content = DictationHUDContent()
    content.text = "Secure field"
    content.isRevealed = true

    let size = try render(
      DictationHUDShellView(
        screen: notchedScreen,
        settings: settings,
        content: content
      ),
      named: "01-dictation-message"
    )
    #expect(size == CGSize(width: 1280, height: 520))
  }

  @Test func theDropTargetRendersArmedAndOpen() throws {
    for (isOpen, name) in [(false, "02-drop-peek"), (true, "03-drop-open")] {
      let drop = HUDDropContent()
      drop.mode = .armed
      drop.isOpen = isOpen
      drop.fileName = "Talkify-test-human.mp3"
      drop.isRevealed = true

      _ = try render(
        DropHUDView(
          screen: notchedScreen,
          settings: settings,
          drop: drop,
          acceptsDrops: false
        ),
        named: name
      )
    }
  }

  @Test func theDropTargetSplitsForTwoLanguages() throws {
    let drop = HUDDropContent()
    drop.mode = .armed
    drop.isOpen = true
    drop.fileName = "interview.m4a"
    drop.languageTags = ["EN", "KA"]
    drop.isRevealed = true

    _ = try render(
      DropHUDView(
        screen: notchedScreen,
        settings: settings,
        drop: drop,
        acceptsDrops: false
      ),
      named: "04-drop-two-languages"
    )
  }

  /// The menu bar ghost filling from the bottom as a file job advances.
  @Test func theStatusGhostFillsWithProgress() throws {
    let template = try #require(NSImage(named: "MenuBarIcon"))
    let fractions = [0.0, 0.35, 0.7, 1.0]

    let strip = HStack(spacing: 14) {
      ForEach(fractions, id: \.self) { fraction in
        Image(nsImage: StatusItemController.progressIcon(from: template, fraction: fraction))
          .renderingMode(.template)
          .foregroundStyle(.white)
      }
    }
    .padding(24)
    .background(Color(red: 0.1, green: 0.1, blue: 0.12))

    _ = try render(strip, named: "06-status-ghost-progress")
  }

  @Test func theTranscriptCardRenders() throws {
    let drop = HUDDropContent()
    drop.mode = .transcript
    drop.isRevealed = true
    drop.transcript = HUDDropContent.Transcript(
      url: URL(filePath: "/Users/x/Desktop/Talkify-test-human.txt"),
      wordCount: 1240,
      duration: 723
    )

    _ = try render(
      DropHUDView(
        screen: notchedScreen,
        settings: settings,
        drop: drop,
        acceptsDrops: false
      ),
      named: "05-transcript-card"
    )
  }
}
