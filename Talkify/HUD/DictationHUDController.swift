import AppKit
import SwiftUI

/// The Direct Dictation HUD surface: a NotchIsland-style shape that descends
/// from the top center of the selected display. Non-activating and
/// click-through; the host window is sized once per display and only its
/// origin moves. Each session keeps the settings captured at its start.
@MainActor
final class DictationHUDController {
  private static let messageDuration = Duration.seconds(2)
  /// How long the retract animation needs before the panel can order out.
  /// A perceptual duration rather than the spring's settling time, per
  /// WWDC23 "Animate with springs": don't wait for settling.
  private static let dismissDuration = Duration.milliseconds(350)
  private static let latchedText = "Listening (latched)"
  private static let listeningText = "Listening…"

  private enum Mode {
    case hidden
    case session
    case message
  }

  private let settings: AppSettings
  private var renderedSettings: DictationSessionSettings
  private var sessionSettings: DictationSessionSettings
  private let panel: DictationHUDPanel
  private let hostingView: NSHostingView<DictationHUDShellView>
  private let content = DictationHUDContent()
  private let sounds: DictationHUDSounds
  private var mode = Mode.hidden
  /// Remembered so a download line can restore the right session text.
  private var sessionIsLatched = false
  private var messageDismissTask: Task<Void, Never>?
  private var orderOutTask: Task<Void, Never>?
  private var lastLevelAt = ContinuousClock.now
  private var micWatchdogTask: Task<Void, Never>?

  init(settings: AppSettings) {
    let initialSettings = settings.sessionSettings
    self.settings = settings
    renderedSettings = initialSettings
    sessionSettings = initialSettings
    sounds = DictationHUDSounds()
    let placeholder = HUDScreenSnapshot(
      id: 0,
      frame: .zero,
      safeAreaTop: 0,
      auxiliaryTopLeftArea: nil,
      auxiliaryTopRightArea: nil
    )
    hostingView = NSHostingView(
      rootView: DictationHUDShellView(
        screen: placeholder,
        settings: initialSettings,
        content: content
      )
    )
    // The window size is this controller's decision, not the content's;
    // without this the hosting view imposes the shell's intrinsic size on
    // the window and collapses the fixed frame.
    hostingView.sizingOptions = []
    panel = DictationHUDPanel(
      contentRect: CGRect(origin: .zero, size: CGSize(width: 1, height: 1)),
      contentView: hostingView
    )
  }

  /// Live microphone level, 0–1, ~46 Hz while listening. Smoothed with a
  /// fast attack and slow release, appended raw to the waveform history,
  /// and marks the microphone alive for the dead-mic watchdog.
  func showAudioLevel(_ level: Float) {
    guard content.showsVoiceVisual else { return }
    content.audioLevel = max(Double(level), content.audioLevel * 0.88)
    content.levelHistory.removeFirst()
    // Light EMA against the previous bar calms per-tick jitter without
    // dulling the speech rhythm.
    let lastBar = content.levelHistory.last ?? 0
    content.levelHistory.append(0.6 * level + 0.4 * lastBar)
    lastLevelAt = ContinuousClock.now
    content.isAudioAlive = true
  }

  /// Played when finalized text lands in the target, after a finished
  /// session's insertion.
  func playPasteSound() {
    sounds.playPaste(using: sessionSettings.soundSet)
  }

  func showMessage(_ text: String) {
    showMessage(text, on: nil)
  }

  func showMessage(_ text: String, on displayID: CGDirectDisplayID?) {
    guard let screen = selectScreen(targetDisplayID: displayID) else { return }
    renderedSettings = settings.sessionSettings
    mode = .message
    stopVoiceVisual()
    present(text, on: screen)
    scheduleMessageDismiss()
  }

  func showListening(
    on displayID: CGDirectDisplayID?,
    isLatched: Bool,
    settings: DictationSessionSettings,
    languageTag: String? = nil
  ) {
    guard let screen = selectScreen(targetDisplayID: displayID) else { return }
    sessionSettings = settings
    renderedSettings = settings
    content.languageTag = languageTag
    cancelMessageDismiss()
    mode = .session
    startVoiceVisual()
    sessionIsLatched = isLatched
    present(isLatched ? Self.latchedText : Self.listeningText, on: screen)
    sounds.playBegin(using: settings.soundSet)
  }

  func showLatched() {
    guard case .session = mode else { return }
    content.text = Self.latchedText
  }

  /// A session waiting on its language model. The band says what it is waiting
  /// for instead of sitting on "Listening…" while nothing arrives; passing nil
  /// restores whatever the session was saying before.
  func showModelDownload(_ text: String?) {
    guard case .session = mode else { return }
    content.text = text ?? (sessionIsLatched ? Self.latchedText : Self.listeningText)
  }

  func showLiveText(_ text: String) {
    guard case .session = mode, !text.isEmpty else { return }
    content.text = text
  }

  func showFinalizing() {
    guard case .session = mode else { return }
    stopVoiceVisual()
    content.text = "Finalizing…"
  }

  func hide() {
    cancelMessageDismiss()
    stopVoiceVisual()
    if case .session = mode {
      sounds.playEnd(using: sessionSettings.soundSet)
    }
    mode = .hidden
    content.isRevealed = false

    // Keep the panel front while the retract plays, then order out.
    orderOutTask?.cancel()
    orderOutTask = Task { [weak self] in
      try? await Task.sleep(for: Self.dismissDuration)
      guard !Task.isCancelled, let self, case .hidden = mode else { return }
      panel.orderOut(nil)
    }
  }

  private func selectScreen(targetDisplayID: CGDirectDisplayID?) -> HUDScreenSnapshot? {
    let screens = NSScreen.screens.compactMap { screen -> HUDScreenSnapshot? in
      guard let id = screen.cgDirectDisplayID else { return nil }
      return HUDScreenSnapshot(
        id: id,
        frame: screen.frame,
        safeAreaTop: screen.safeAreaInsets.top,
        auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
        auxiliaryTopRightArea: screen.auxiliaryTopRightArea
      )
    }
    return HUDPlacement.selectDisplay(
      from: screens,
      targetDisplayID: targetDisplayID,
      pointerLocation: NSEvent.mouseLocation
    )
  }

  private func present(_ text: String, on screen: HUDScreenSnapshot) {
    orderOutTask?.cancel()
    content.text = text
    hostingView.rootView = DictationHUDShellView(
      screen: screen,
      settings: renderedSettings,
      content: content
    )
    panel.setFrame(HUDNotchGeometry.windowFrame(for: screen), display: true)
    panel.orderFrontRegardless()

    guard !content.isRevealed else { return }
    // The shell needs one committed frame in its parked position or the
    // reveal renders already-descended and the animation never plays.
    // Force that frame synchronously, then flip on the next runloop tick.
    panel.displayIfNeeded()
    Task { @MainActor [content] in
      content.isRevealed = true
    }
  }

  /// Resets the visual to a live-and-silent baseline and arms the dead-mic
  /// watchdog: levels stopping for over 600ms while listening means the
  /// microphone is dead, which must look different from silence (CONTEXT.md).
  private func startVoiceVisual() {
    content.sessionEpoch += 1
    content.showsVoiceVisual = true
    content.audioLevel = 0
    content.levelHistory = [Float](repeating: 0, count: HUDWaveformView.barCount)
    content.isAudioAlive = true
    lastLevelAt = ContinuousClock.now

    micWatchdogTask?.cancel()
    micWatchdogTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(300))
        guard let self, !Task.isCancelled else { return }
        if lastLevelAt.duration(to: .now) > .milliseconds(600) {
          content.isAudioAlive = false
        }
      }
    }
  }

  private func stopVoiceVisual() {
    micWatchdogTask?.cancel()
    micWatchdogTask = nil
    content.showsVoiceVisual = false
  }

  private func scheduleMessageDismiss() {
    messageDismissTask?.cancel()
    messageDismissTask = Task { [weak self] in
      try? await Task.sleep(for: Self.messageDuration)
      guard !Task.isCancelled, let self, case .message = mode else { return }
      hide()
    }
  }

  private func cancelMessageDismiss() {
    messageDismissTask?.cancel()
    messageDismissTask = nil
  }
}
