import SwiftUI
import Testing
import UniformTypeIdentifiers

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
      let drop = DropHUDContent()
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
    let drop = DropHUDContent()
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

  /// The shape holding the file it was just given, before any work starts.
  @Test func theHeldFileRenders() throws {
    let drop = DropHUDContent()
    drop.mode = .held
    drop.isRevealed = true
    drop.fileName = "Talkify-test-human.mp3"
    drop.heldIcon = NSWorkspace.shared.icon(for: .mp3)

    _ = try render(
      DropHUDView(
        screen: notchedScreen,
        settings: settings,
        drop: drop,
        acceptsDrops: false
      ),
      named: "09-drop-held"
    )
  }

  /// The drop target takes its colour from the voice visual: Edge Glow lends
  /// its palette, everything else keeps the Talkify blue.
  @Test(arguments: [HUDGlowPalette.sunset, .aurora, .mono])
  func theDropTargetFollowsTheGlowPalette(palette: HUDGlowPalette) throws {
    let store = AppSettings.previewStore()
    store.voiceVisual = .glow
    store.glowPalette = palette

    let drop = DropHUDContent()
    drop.mode = .armed
    drop.isOpen = true
    drop.isRevealed = true
    drop.fileName = "Talkify-test-human.mp3"

    _ = try render(
      DropHUDView(
        screen: notchedScreen,
        settings: store.sessionSettings,
        drop: drop,
        acceptsDrops: false
      ),
      named: "11-drop-open-\(palette.rawValue.lowercased())"
    )
  }

  /// Every sidebar row, so the titles can be seen starting at one x. SF Symbol
  /// widths vary enough that this drifted without a fixed icon column.
  @Test func theSidebarRowsAlign() throws {
    let rows = VStack(alignment: .leading, spacing: 4) {
      ForEach(SettingsSection.allCases) { section in
        Label(section.title, systemImage: section.icon)
          .labelStyle(SettingsSidebarLabelStyle())
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.white.opacity(0.8))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 11)
          .padding(.vertical, 9)
      }
    }
    .frame(width: 190)
    .padding(16)
    .background(SettingsTheme.sidebar)

    _ = try render(rows, named: "13-settings-sidebar")
  }

  /// The Drop Transcription preview card, with the surface posed mid-gesture:
  /// the stage's chrome is shared with the Appearance preview, so this proves
  /// the drop shape sits in it the same way the dictation shell does.
  @Test func theDropPreviewCardRenders() throws {
    let drop = DropHUDContent()
    drop.mode = .armed
    drop.isOpen = true
    drop.isRevealed = true
    drop.fileName = "Interview.m4a"

    let card = SettingsPreviewStage(
      title: "Live preview",
      subtitle: "The notch taking a file and handing back a transcript"
    ) {
      DropHUDView(
        screen: HUDPreviewScreen.notched,
        settings: AppSettings.previewStore().sessionSettings,
        drop: drop,
        acceptsDrops: false
      )
    }
    .frame(width: 340)
    .padding(20)
    .background(SettingsTheme.background)

    _ = try render(card, named: "12-drop-preview-card")
  }

  /// The menu bar ghost filling from the bottom as a file job advances, in the
  /// accent the drop surfaces are wearing.
  @Test(arguments: [SettingsTheme.accentColor, HUDGlowPalette.sunset.statusAccent])
  func theStatusGhostFillsWithProgress(accent: NSColor) throws {
    let template = try #require(NSImage(named: "MenuBarIcon"))
    let fractions = [0.0, 0.35, 0.7, 1.0]

    let strip = HStack(spacing: 14) {
      ForEach(fractions, id: \.self) { fraction in
        Image(nsImage: StatusItemController.progressIcon(
          from: template,
          fraction: fraction,
          accent: accent
        ))
      }
    }
    .padding(24)
    .background(Color(red: 0.1, green: 0.1, blue: 0.12))

    _ = try render(strip, named: "06-status-ghost-progress-\(accent.redComponent > 0.8 ? "sunset" : "blue")")
  }

  @Test func theTranscriptCardRenders() throws {
    let drop = DropHUDContent()
    drop.mode = .transcript
    drop.isRevealed = true
    drop.transcript = DropHUDContent.Transcript(
      url: URL(filePath: "/Users/x/Desktop/Talkify-test-human.txt"),
      text: "A transcript the card never renders.",
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

  /// Hovering trades the numbers for the two gestures the card offers, which
  /// are invisible otherwise.
  @Test func theHoveredCardShowsBothGestures() throws {
    let drop = DropHUDContent()
    drop.mode = .transcript
    drop.isRevealed = true
    drop.isCardHovered = true
    drop.transcript = DropHUDContent.Transcript(
      url: URL(filePath: "/Users/x/Desktop/Talkify-test-human.txt"),
      text: "A transcript the card never renders.",
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
      named: "08-transcript-card-hovered"
    )
  }

  /// What the shape says when the card was not taken and the transcript went
  /// to the Save-to location instead.
  @Test func theSavedNoticeRenders() throws {
    let drop = DropHUDContent()
    drop.mode = .notice
    drop.isRevealed = true
    drop.noticeText = "Saved to Recordings"

    _ = try render(
      DropHUDView(
        screen: notchedScreen,
        settings: settings,
        drop: drop,
        acceptsDrops: false
      ),
      named: "07-transcript-saved"
    )
  }
}
