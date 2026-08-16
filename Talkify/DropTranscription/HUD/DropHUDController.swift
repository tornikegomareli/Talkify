import AppKit

/// What the HUD shows for a Drop Transcription: the target a file is dragged
/// into, the file once it lands, the finished card, and the line saying what
/// became of it.
///
/// It owns none of the window. `HUDStage` decides where the shape is and who
/// holds it; this decides what a Drop Transcription puts in it.
@MainActor
final class DropHUDController {
  /// How long the shape holds the line saying what became of a transcript.
  /// Shorter than a status message: it confirms rather than informs, and the
  /// card it replaces was already on screen for five seconds.
  private static let noticeDuration = Duration.milliseconds(1600)

  private let stage: HUDStage

  private var content: DropHUDContent { stage.dropContent }
  private var holdsShape: Bool { stage.occupant == .drop }

  init(stage: HUDStage) {
    self.stage = stage
  }

  /// A dropped file and whatever the pointer does to the card, handed to the
  /// Drop Transcription controller without the HUD knowing what either means.
  var onDropReceived: ((Int) -> Void)? {
    get { stage.onDropReceived }
    set { stage.onDropReceived = newValue }
  }

  var onCardEvent: ((HUDCardEvent) -> Void)? {
    get { stage.onCardEvent }
    set { stage.onCardEvent = newValue }
  }

  /// The HUD as a drop target. The window starts accepting the mouse here and
  /// stops again when the drop state ends — during dictation it stays
  /// click-through (CONTEXT.md).
  func showTarget(fileName: String, isOpen: Bool, languageTags: [String]) {
    guard stage.occupant != .dictation else { return }
    guard let screen = stage.screen() else { return }
    stage.claim(.drop, on: screen)
    content.mode = .armed
    content.fileName = fileName
    content.languageTags = languageTags
    content.isOpen = isOpen
    stage.acceptsMouse = true
    stage.revealDrop()
  }

  func setTargetOpen(_ isOpen: Bool) {
    guard content.mode == .armed else { return }
    content.isOpen = isOpen
  }

  /// The file landed and the shape holds it. Nothing has started yet: the drop
  /// is shown back before any work begins, so the gesture ends with the file
  /// visibly inside the notch rather than with the notch vanishing.
  ///
  /// The panel stops taking the mouse here — the target is spent — but the
  /// shape stays exactly where it is.
  func showHeld(fileName: String, icon: NSImage?) {
    guard holdsShape else { return }
    stage.acceptsMouse = false
    content.mode = .held
    content.fileName = fileName
    content.heldIcon = icon
    // The same sound a session opens with: something has been taken in.
    stage.sounds.playBegin(using: stage.dropSoundSettings)
  }

  /// The finished card. Stays until dismissed or dragged, with its own timer
  /// owned by the Drop Transcription controller.
  func showTranscript(_ transcript: DropHUDContent.Transcript) {
    guard let screen = stage.screen() else { return }
    stage.claim(.drop, on: screen)
    content.mode = .transcript
    content.transcript = transcript
    content.remainingFraction = 1
    stage.acceptsMouse = true
    // The session-end sound: the work is finished and here is the result.
    stage.sounds.playEnd(using: stage.dropSoundSettings)
    stage.revealDrop()
  }

  func setTranscriptRemaining(_ fraction: Double) {
    content.remainingFraction = min(max(fraction, 0), 1)
  }

  func setCardHovered(_ isHovered: Bool) {
    content.isCardHovered = isHovered
  }

  /// The card expired untaken, so its transcript went to the Save-to location.
  func showSaved(in destination: URL) {
    showNotice(
      "Saved to \(destination.deletingLastPathComponent().lastPathComponent)",
      symbol: "folder.fill"
    )
  }

  /// The card was clicked, so the transcript went to the clipboard instead of
  /// to a file.
  func showCopied() {
    showNotice("Copied", symbol: "checkmark.circle.fill")
  }

  func showMessage(_ text: String) {
    stage.showMessage(text)
  }

  /// Retracts whatever drop state is showing and hands the shape back.
  func hide() {
    guard holdsShape else { return }
    stage.retract()
  }

  /// The shape swaps the card for one line saying what became of it and then
  /// retracts: retracting first and reopening for a message would bounce it
  /// twice.
  private func showNotice(_ text: String, symbol: String) {
    guard holdsShape else { return }
    stage.acceptsMouse = false
    // The insertion sound: the transcript has landed somewhere, whether the
    // user took it or the timer put it away.
    stage.sounds.playPaste(using: stage.dropSoundSettings)
    content.mode = .notice
    content.noticeText = text
    content.noticeSymbol = symbol
    content.transcript = nil
    content.isCardHovered = false

    stage.schedule(after: Self.noticeDuration, while: .drop) { [weak self] in
      guard self?.content.mode == .notice else { return }
      self?.hide()
    }
  }
}
