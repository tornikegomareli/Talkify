import SwiftUI
import Testing

@testable import Talkify

/// Draws the keyboard for each shape so it can be looked at. Writes PNGs to
/// `TALKIFY_RENDER_DIR` when set; otherwise it only asserts each shape renders.
@MainActor
@Suite("Keyboard map rendering")
struct KeyboardMapRenderTests {
  @Test(arguments: [KeyboardLayout.Shape.ansi, .iso])
  func eachShapeDraws(shape: KeyboardLayout.Shape) throws {
    // Real legends from this Mac, redrawn on the requested shape, so the
    // picture shows what a user of that board would actually see.
    let live = KeyboardLayout.current()
    let layout = KeyboardLayout(shape: shape, legends: live.legends)

    let fnOption = KeyBinding(
      keyCode: 63,
      modifierFlags: CGEventFlags.maskAlternate.rawValue,
      isModifierKey: true,
      label: "⌥ fn",
      keyEquivalent: ""
    )

    let view = KeyboardMapView(
      layout: layout,
      highlights: [
        KeyboardMapView.Highlight(
          keyCodes: KeyboardMap.highlighted(for: fnOption),
          color: SettingsTheme.accent,
          isEmphasized: true
        ),
        KeyboardMapView.Highlight(
          keyCodes: KeyboardMap.highlighted(for: .optionEscape),
          color: Color(red: 0.95, green: 0.7, blue: 0.35),
          isEmphasized: false
        ),
      ]
    )
    .padding(20)
    .background(SettingsTheme.card)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    #expect(image.width > 0 && image.height > 0)

    guard let directory = ProcessInfo.processInfo.environment["TALKIFY_RENDER_DIR"]
      .map({ URL(filePath: $0) })
    else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
      try data.write(to: directory.appending(path: "keyboard-\(shape).png"))
    }
  }
}

/// The Shortcuts rows, so the keycap layout can be compared with the design.
@MainActor
@Suite("Shortcut row rendering")
struct ShortcutRowRenderTests {
  @Test func theSectionDraws() throws {
    let store = AppSettings.previewStore()
    store.dictationTriggerBinding = KeyBinding(
      keyCode: 35,
      modifierFlags: CGEventFlags.maskShift.rawValue,
      isModifierKey: false,
      label: "⇧ P",
      keyEquivalent: "p"
    )

    let renderer = ImageRenderer(
      content: ShortcutsSettingsView(settings: store)
        .frame(width: 560)
        .padding(20)
        .background(SettingsTheme.background)
    )
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    #expect(image.width > 0)

    guard let directory = ProcessInfo.processInfo.environment["TALKIFY_RENDER_DIR"]
      .map({ URL(filePath: $0) })
    else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
      try data.write(to: directory.appending(path: "shortcuts-rows.png"))
    }
  }
}
