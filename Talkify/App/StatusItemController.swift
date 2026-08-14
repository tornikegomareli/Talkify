import AppKit

@MainActor
final class StatusItemController: NSObject {
  private let statusItem: NSStatusItem
  private let toggleDictation: () -> Void
  private let toggleReadAloud: () -> Void
  private let openSettings: () -> Void
  private let checkForUpdates: () -> Void
  private let dictationItem: NSMenuItem
  private let readAloudItem: NSMenuItem
  private var blinkTimer: Timer?
  private var blinkDimmed = false
  private let templateIcon = NSImage(named: "MenuBarIcon")
  /// Pre-tinted session icons. NSStatusBarButton renders custom
  /// contentTintColor values as black (FB8530353), so palette tinting
  /// swaps in non-template images instead.
  private var sessionIcons: (full: NSImage, dim: NSImage)?

  init(
    toggleDictation: @escaping () -> Void,
    toggleReadAloud: @escaping () -> Void,
    openSettings: @escaping () -> Void,
    checkForUpdates: @escaping () -> Void
  ) {
    self.toggleDictation = toggleDictation
    self.toggleReadAloud = toggleReadAloud
    self.openSettings = openSettings
    self.checkForUpdates = checkForUpdates
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    dictationItem = NSMenuItem(title: "Start Dictation", action: nil, keyEquivalent: "")
    readAloudItem = NSMenuItem(title: "Read Selected Text", action: nil, keyEquivalent: "")
    super.init()

    statusItem.button?.image = templateIcon
    statusItem.button?.image?.accessibilityDescription = "Talkify"

    let menu = NSMenu()

    dictationItem.action = #selector(toggleDictationItem)
    dictationItem.target = self
    menu.addItem(dictationItem)

    readAloudItem.action = #selector(toggleReadAloudItem)
    readAloudItem.target = self
    menu.addItem(readAloudItem)
    menu.addItem(.separator())

    let settingsItem = NSMenuItem(
      title: "Settings…",
      action: #selector(openSettingsItem),
      keyEquivalent: ","
    )
    settingsItem.target = self
    menu.addItem(settingsItem)

    let updatesItem = NSMenuItem(
      title: "Check for Updates…",
      action: #selector(checkForUpdatesItem),
      keyEquivalent: ""
    )
    updatesItem.target = self
    menu.addItem(updatesItem)

    menu.addItem(NSMenuItem(
      title: "Quit Talkify",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    ))
    statusItem.menu = menu
  }

  /// Mirrors the session state on the shell: the ghost pulses between
  /// full and dimmed tint while recording, and the menu item flips.
  /// An Edge Glow session passes its palette accent so the pulse speaks
  /// the session's color; nil keeps the theme tint.
  func setRecording(_ isRecording: Bool, accent: NSColor? = nil) {
    dictationItem.title = isRecording ? "Stop Dictation" : "Start Dictation"
    sessionIcons = isRecording ? accent.flatMap(makeSessionIcons) : nil
    if isRecording {
      startBlinking()
    } else {
      stopBlinking()
    }
  }

  /// Shows the recorded bindings as menu hints; the event tap does the
  /// real work, these only display. Bare modifier keys cannot render as
  /// key equivalents, so those ride a trailing badge instead.
  func setKeyBindings(trigger: KeyBinding, readAloud: KeyBinding) {
    dictationItem.badge = NSMenuItemBadge(string: trigger.label)
    if readAloud.keyEquivalent.isEmpty {
      readAloudItem.keyEquivalent = ""
      readAloudItem.badge = NSMenuItemBadge(string: readAloud.label)
    } else {
      readAloudItem.badge = nil
      readAloudItem.keyEquivalent = readAloud.keyEquivalent
      readAloudItem.keyEquivalentModifierMask = readAloud.cocoaModifiers
    }
  }

  private func startBlinking() {
    guard blinkTimer == nil else { return }
    if let sessionIcons {
      statusItem.button?.image = sessionIcons.full
    }
    blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.blinkDimmed.toggle()
        if let icons = self.sessionIcons {
          self.statusItem.button?.image = self.blinkDimmed ? icons.dim : icons.full
        } else {
          self.statusItem.button?.contentTintColor =
            self.blinkDimmed ? .tertiaryLabelColor : .labelColor
        }
      }
    }
  }

  private func stopBlinking() {
    blinkTimer?.invalidate()
    blinkTimer = nil
    blinkDimmed = false
    statusItem.button?.contentTintColor = nil
    statusItem.button?.image = templateIcon
  }

  /// Renders the template ghost filled with the accent, full and dimmed;
  /// the results are plain images the status bar shows as-is.
  private func makeSessionIcons(for accent: NSColor) -> (full: NSImage, dim: NSImage)? {
    guard let templateIcon else { return nil }
    let full = NSImage(size: templateIcon.size, flipped: false) { rect in
      templateIcon.draw(in: rect)
      accent.set()
      rect.fill(using: .sourceAtop)
      return true
    }
    let dim = NSImage(size: templateIcon.size, flipped: false) { rect in
      full.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)
      return true
    }
    full.isTemplate = false
    dim.isTemplate = false
    return (full, dim)
  }

  /// Mirrors Read Aloud playback on the menu item.
  func setSpeaking(_ isSpeaking: Bool) {
    readAloudItem.title = isSpeaking ? "Stop Reading" : "Read Selected Text"
  }

  @objc private func toggleDictationItem() {
    toggleDictation()
  }

  @objc private func toggleReadAloudItem() {
    toggleReadAloud()
  }

  @objc private func checkForUpdatesItem() {
    checkForUpdates()
  }

  @objc private func openSettingsItem() {
    openSettings()
  }
}
