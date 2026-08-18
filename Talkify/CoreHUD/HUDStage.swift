import AppKit
import SwiftUI

/// The one shape, and who is holding it.
///
/// Talkify has a single HUD: one panel, one hosting view, one place on screen.
/// Two features want it — Direct Dictation and Drop Transcription — and they
/// must never both have it. This owns the window, the display choice, the
/// mounting, and the arbitration; the feature controllers own what their
/// surface says. Neither of them touches `NSPanel`.
///
/// It also owns the status message band, because "the HUD is the only surface
/// for status and error messages" (CONTEXT.md) is a property of the HUD, not of
/// either feature: a file that cannot be read says so in the same place a
/// secure field does.
@MainActor
final class HUDStage {
  /// How long the retract animation needs before the panel can order out.
  /// A perceptual duration rather than the spring's settling time, per
  /// WWDC23 "Animate with springs": don't wait for settling.
  private static let dismissDuration = Duration.milliseconds(350)
  private static let messageDuration = Duration.seconds(2)

  /// Who holds the shape. `message` is its own occupant rather than a mode of
  /// dictation: a message can interrupt either feature and outranks both.
  enum Occupant: Equatable {
    case none
    case dictation
    case message
    case drop
  }

  private(set) var occupant = Occupant.none

  let dictationContent = DictationHUDContent()
  let dropContent = DropHUDContent()
  let sounds = HUDSounds()

  /// Forwarded to the drop surface, which is the only part of the HUD that
  /// takes input.
  var onDropReceived: ((Int) -> Void)?
  var onCardEvent: ((HUDCardEvent) -> Void)?

  private let settings: AppSettings
  private let panel: HUDPanel
  private let hostingView: NSHostingView<HUDRootView>
  private var renderedSettings: DictationSessionSettings
  private var orderOutTask: Task<Void, Never>?
  private var messageDismissTask: Task<Void, Never>?

  init(settings: AppSettings) {
    self.settings = settings
    renderedSettings = settings.sessionSettings
    let placeholder = HUDScreenSnapshot(
      id: 0,
      frame: .zero,
      safeAreaTop: 0,
      auxiliaryTopLeftArea: nil,
      auxiliaryTopRightArea: nil
    )
    hostingView = NSHostingView(
      rootView: HUDRootView(
        screen: placeholder,
        settings: renderedSettings,
        content: dictationContent,
        drop: dropContent
      )
    )
    // The window size is this stage's decision, not the content's; without
    // this the hosting view imposes the shell's intrinsic size on the window
    // and collapses the fixed frame.
    hostingView.sizingOptions = []
    panel = HUDPanel(
      contentRect: CGRect(origin: .zero, size: CGSize(width: 1, height: 1)),
      contentView: hostingView
    )
  }

  /// Whether the shape currently takes the mouse. Only a drop surface does,
  /// plus the editable-draft review while the field is up.
  var acceptsMouse: Bool {
    get { panel.acceptsMouse }
    set { panel.acceptsMouse = newValue }
  }

  /// Gives the dictation surface the key for the editable-draft review.
  ///
  /// The panel becomes key so the draft field can take focus — the app
  /// never activates, the panel stays `.nonactivatingPanel`, and the
  /// previously focused control stays frontmost — and with key comes the
  /// mouse, so clicks place the cursor in the field instead of leaking
  /// into the app below (which would steal key mid-review). The shape
  /// arbitration is unchanged: this is a mode of the dictation occupant.
  func enableDraftEditing() {
    panel.acceptsKey = true
    acceptsMouse = true
    panel.makeKey()
  }

  /// Ends the editable-draft review's key surface. The panel stops taking
  /// key or mouse, and a key panel resigns so the previously focused
  /// control's window takes key back — which is what lets the review's
  /// Return paste land in the right place.
  func endDraftEditing() {
    panel.acceptsKey = false
    acceptsMouse = false
    panel.resignKey()
  }

  /// The live sound preferences. A Drop Transcription has no session snapshot
  /// to capture — its moments are minutes apart — so it reads the current pick
  /// each time, where dictation uses the one it started with.
  var dropSoundSettings: DictationSoundSettings {
    settings.sessionSettings.sounds
  }

  /// The display this surface should open on: the one holding the focused
  /// input where that is known, else the pointer's, else the main one.
  func screen(preferring displayID: CGDirectDisplayID? = nil) -> HUDScreenSnapshot? {
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
      targetDisplayID: displayID,
      pointerLocation: NSEvent.mouseLocation
    )
  }

  /// Hands the shape to `occupant` and puts it on `screen`.
  ///
  /// Taking it for dictation or a message evicts any drop surface: the file
  /// job keeps running with the status item carrying it, but the user is
  /// speaking now and that outranks a card (CONTEXT.md).
  func claim(
    _ occupant: Occupant,
    on screen: HUDScreenSnapshot,
    rendering settings: DictationSessionSettings? = nil
  ) {
    orderOutTask?.cancel()
    if occupant != .message { cancelMessageDismiss() }
    if occupant != .drop { evictDrop() }
    // A fresh claim starts without the review's key surface; the
    // editable-draft mode arms it again once the draft is held.
    panel.acceptsKey = false
    self.occupant = occupant
    renderedSettings = settings ?? self.settings.sessionSettings
    mount(on: screen)
  }

  /// Gives the shape up. The panel stays front while the retract plays, then
  /// orders out and the drop surface clears itself down. The review's key
  /// surface ends here too: a key panel resigns, handing the previously
  /// focused control back its AX focus.
  func retract() {
    guard occupant != .none else { return }
    endDraftEditing()
    occupant = .none
    dictationContent.isRevealed = false
    dropContent.isRevealed = false

    orderOutTask?.cancel()
    orderOutTask = Task { [weak self] in
      try? await Task.sleep(for: Self.dismissDuration)
      guard !Task.isCancelled, let self, occupant == .none else { return }
      panel.orderOut(nil)
      // Only once it is off screen: clearing any of these earlier would show
      // through the retract.
      dictationContent.isDismissing = false
      dictationContent.text = ""
      dropContent.mode = .none
      dropContent.heldIcon = nil
      dropContent.transcript = nil
    }
  }

  /// Runs `work` after `delay` unless the shape has changed hands, for the
  /// self-dismissing states: a message, a notice, a card's deadline.
  func schedule(after delay: Duration, while occupant: Occupant, _ work: @escaping () -> Void) {
    orderOutTask?.cancel()
    orderOutTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled, let self, self.occupant == occupant else { return }
      work()
    }
  }

  /// A status or error line, in the one place Talkify says anything.
  func showMessage(_ text: String, on displayID: CGDirectDisplayID? = nil) {
    guard let screen = screen(preferring: displayID) else { return }
    claim(.message, on: screen)
    dictationContent.showsVoiceVisual = false
    dictationContent.text = text
    revealDictation()

    messageDismissTask?.cancel()
    messageDismissTask = Task { [weak self] in
      try? await Task.sleep(for: Self.messageDuration)
      guard !Task.isCancelled, let self, occupant == .message else { return }
      retract()
    }
  }

  func cancelMessageDismiss() {
    messageDismissTask?.cancel()
    messageDismissTask = nil
  }

  /// Reveals the dictation surface. It is always mounted — the root shows it
  /// whenever no drop state is up — so its reveal animates against a frame
  /// that already exists.
  func revealDictation() {
    guard !dictationContent.isRevealed else { return }
    commitParkedFrame()
    Task { @MainActor [dictationContent] in
      dictationContent.isRevealed = true
    }
  }

  /// Reveals a drop surface once its parked state has actually been drawn.
  ///
  /// The drop shape is inserted into the view tree at the same moment it is
  /// asked to open, and a view that has never rendered has no parked frame to
  /// spring from — both states collapse into one render and it appears already
  /// open. Forcing layout is not enough and there is no callback for "SwiftUI
  /// has drawn", so the flip waits one display cycle.
  func revealDrop() {
    guard !dropContent.isRevealed else { return }
    commitParkedFrame()
    Task { @MainActor [dropContent] in
      try? await Task.sleep(for: .milliseconds(20))
      dropContent.isRevealed = true
    }
  }

  /// Commits one frame in the parked state, so the reveal has something to
  /// animate from rather than drawing itself already open.
  private func commitParkedFrame() {
    hostingView.layoutSubtreeIfNeeded()
    panel.displayIfNeeded()
  }

  /// Rebuilds the root for this display and brings the window forward. The
  /// window's frame comes from the screen, never from the content.
  private func mount(on screen: HUDScreenSnapshot) {
    hostingView.rootView = HUDRootView(
      screen: screen,
      settings: renderedSettings,
      content: dictationContent,
      drop: dropContent,
      onDrop: { [weak self] index in
        self?.onDropReceived?(index)
      },
      onCardEvent: { [weak self] event in
        self?.onCardEvent?(event)
      }
    )
    panel.setFrame(HUDNotchGeometry.windowFrame(for: screen), display: true)
    panel.orderFrontRegardless()
  }

  private func evictDrop() {
    acceptsMouse = false
    dropContent.mode = .none
  }
}
