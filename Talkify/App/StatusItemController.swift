import AppKit

@MainActor
final class StatusItemController: NSObject {
  private let statusItem: NSStatusItem
  private let toggleDictation: () -> Void
  private let toggleReadAloud: () -> Void
  private let transcribeFile: () -> Void
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
  /// Remembered so a dictation session that interrupts a running file job can
  /// hand the ghost back to it afterwards.
  private var transcriptionProgress: Double?
  private var transcriptionAccent = SettingsTheme.accentColor

  init(
    toggleDictation: @escaping () -> Void,
    toggleReadAloud: @escaping () -> Void,
    transcribeFile: @escaping () -> Void,
    openSettings: @escaping () -> Void,
    checkForUpdates: @escaping () -> Void
  ) {
    self.toggleDictation = toggleDictation
    self.toggleReadAloud = toggleReadAloud
    self.transcribeFile = transcribeFile
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

    let transcribeItem = NSMenuItem(
      title: "Transcribe File…",
      action: #selector(transcribeFileItem),
      keyEquivalent: ""
    )
    transcribeItem.target = self
    menu.addItem(transcribeItem)
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
    // A file job can outlast the dictation that interrupted it, so the ghost
    // goes back to reporting it rather than to idle.
    if let transcriptionProgress {
      setTranscriptionProgress(transcriptionProgress, accent: transcriptionAccent)
    }
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

  /// A Drop Transcription's progress, 0…1, or nil once it ends.
  ///
  /// The ghost fills from the bottom like a battery rather than growing a ring
  /// or a bar: it reads at 16 points, needs no extra chrome, and it is the
  /// app's own mark doing the work. A dictation session outranks it — the
  /// pulse is the more urgent thing to say.
  ///
  /// `accent` is the same colour the HUD's drop surfaces wear, so a glow
  /// palette shows in the menu bar too.
  func setTranscriptionProgress(_ fraction: Double?, accent: NSColor) {
    transcriptionProgress = fraction
    transcriptionAccent = accent
    guard blinkTimer == nil else { return }
    if let fraction {
      statusItem.button?.contentTintColor = nil
      statusItem.button?.image = makeProgressIcon(fraction: fraction, accent: accent) ?? templateIcon
    } else {
      statusItem.button?.image = templateIcon
    }
  }

  private func makeProgressIcon(fraction: Double, accent: NSColor) -> NSImage? {
    guard let templateIcon else { return nil }
    return Self.progressIcon(from: templateIcon, fraction: fraction, accent: accent)
  }

  /// The ghost drawn twice in the accent: faint for the whole silhouette, solid
  /// for the filled part, split at the progress line.
  ///
  /// Not a template image — a template is recoloured by the menu bar and would
  /// come back white, which is the whole thing this replaces. Drawing the
  /// unfilled part in the same colour at low alpha keeps it legible in either
  /// menu bar theme.
  static func progressIcon(
    from templateIcon: NSImage,
    fraction: Double,
    accent: NSColor = SettingsTheme.accentColor
  ) -> NSImage {
    let clamped = min(max(fraction, 0), 1)
    let icon = NSImage(size: templateIcon.size, flipped: false) { rect in
      // The unfilled part is the accent at low opacity, not the artwork with
      // a wash of accent over it: `sourceAtop` with an opaque colour replaces
      // the colour and keeps the alpha, so the whole silhouette is one hue and
      // only its weight changes at the progress line.
      templateIcon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.32)
      accent.set()
      rect.fill(using: .sourceAtop)

      let filled = NSRect(
        x: rect.minX,
        y: rect.minY,
        width: rect.width,
        height: rect.height * clamped
      )
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: filled).setClip()
      templateIcon.draw(in: rect)
      accent.set()
      rect.fill(using: .sourceAtop)
      NSGraphicsContext.restoreGraphicsState()
      return true
    }
    icon.isTemplate = false
    return icon
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

  @objc private func transcribeFileItem() {
    transcribeFile()
  }

  @objc private func checkForUpdatesItem() {
    checkForUpdates()
  }

  @objc private func openSettingsItem() {
    openSettings()
  }
}
