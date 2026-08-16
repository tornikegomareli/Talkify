import AppKit

/// A finished transcript being offered back, and everything that can become of
/// it: dragged out to wherever the user wants it, clicked to take as text, or
/// left alone until the deadline files it away.
///
/// This is the one piece of Drop Transcription with genuinely intricate state —
/// a countdown that pauses, a drag that must not expire mid-gesture, a staged
/// file that cannot be deleted while a receiver is still reading it — so it
/// lives on its own rather than inside the controller that starts jobs.
@MainActor
final class TranscriptOffer {
  /// How long a finished card waits to be grabbed before the transcript is
  /// written to the Save-to location. The timer stops the moment the pointer
  /// arrives, so reaching for the card always wins.
  private static let lifetime = Duration.seconds(5)
  private static let tick = Duration.milliseconds(50)

  private let settings: AppSettings
  private let hud: DropHUDController

  /// The transcript the card is offering, still in its staging folder.
  private var staged: StagedTranscript?
  /// A transcript a drag has already taken, kept until the next job or until
  /// Talkify quits.
  ///
  /// It cannot be removed when the drag ends. That callback fires the moment
  /// the destination accepts the drop, and the receiver copies the file
  /// afterwards — deleting the staged file on that signal is what made a
  /// Finder drop fail with "the operation can't be completed" (-43).
  private var spent: StagedTranscript?
  private var timer: Task<Void, Never>?
  /// A drag in flight owns the card, so neither the timer nor the pointer
  /// leaving may act on it until the drag reports back.
  private var isDragging = false

  init(settings: AppSettings, hud: DropHUDController) {
    self.settings = settings
    self.hud = hud
  }

  /// Offers a staged transcript and starts its countdown.
  func present(_ staged: StagedTranscript, as transcript: DropHUDContent.Transcript) {
    self.staged = staged
    hud.showTranscript(transcript)
    startTimer()
  }

  func handle(_ event: HUDCardEvent) {
    switch event {
    case .hover(let isInside): setHovered(isInside)
    case .clicked: copy()
    case .dragBegan: holdForDrag()
    case .dragEnded(let handled): endDrag(handled: handled)
    }
  }

  /// Writes a still-offered transcript out without waiting for the card, for
  /// the two moments the card cannot survive: Talkify quitting, and a second
  /// file arriving.
  func commit() {
    // Far enough past the last drag for any receiver to have finished reading.
    spent?.discard()
    spent = nil
    guard let staged else { return }
    self.staged = nil
    cancelTimer()
    isDragging = false
    _ = try? staged.commit(
      preference: settings.transcriptDestination,
      chosenFolder: settings.transcriptFolder
    )
  }

  private func startTimer() {
    timer?.cancel()
    timer = Task { [weak self] in
      let ticks = Int(Self.lifetime / Self.tick)
      for tick in 0...ticks {
        try? await Task.sleep(for: Self.tick)
        guard !Task.isCancelled, let self else { return }
        hud.setTranscriptRemaining(1 - Double(tick) / Double(ticks))
      }
      guard !Task.isCancelled, let self else { return }
      timer = nil
      expire()
    }
  }

  private func cancelTimer() {
    timer?.cancel()
    timer = nil
  }

  /// Clicking the card takes the transcript as text. It ends the offer exactly
  /// as a landed drag does: the user has the words, so nothing is left behind
  /// on disk.
  ///
  /// This exists because a drag cannot promise text everywhere. A receiver
  /// chooses which flavor of a drag it wants, and one that always prefers a
  /// file — most chat clients do — would attach a .txt for three sentences.
  private func copy() {
    guard let staged,
          let text = try? String(contentsOf: staged.url, encoding: .utf8)
    else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)

    staged.discard()
    self.staged = nil
    cancelTimer()
    hud.showCopied()
  }

  /// The pointer reaching the card cancels its deadline; leaving restarts it.
  /// A surface that asks for a drag must not expire while it is being reached
  /// for.
  private func setHovered(_ isHovered: Bool) {
    guard !isDragging else { return }
    hud.setCardHovered(isHovered)
    if isHovered {
      cancelTimer()
      hud.setTranscriptRemaining(0)
    } else if timer == nil {
      hud.setTranscriptRemaining(1)
      startTimer()
    }
  }

  /// A drag lifts the pointer off the card, which would otherwise restart the
  /// deadline and expire the card mid-gesture.
  private func holdForDrag() {
    isDragging = true
    cancelTimer()
    hud.setTranscriptRemaining(0)
  }

  /// A drag a destination accepted is the user saying where the transcript
  /// goes, so nothing is written to the Save-to location. A drag let go over
  /// nothing changed nothing, so the card goes back to counting down.
  private func endDrag(handled: Bool) {
    isDragging = false
    guard handled else {
      hud.setTranscriptRemaining(1)
      startTimer()
      return
    }
    spent?.discard()
    spent = staged
    staged = nil
    hud.hide()
  }

  /// Nobody took the card, so the transcript goes where the Save-to preference
  /// says. The HUD names the folder before it retracts: this write happens
  /// after the card is gone, and a save the user never sees is one they cannot
  /// rely on.
  private func expire() {
    guard let staged else {
      hud.hide()
      return
    }
    self.staged = nil
    do {
      let destination = try staged.commit(
        preference: settings.transcriptDestination,
        chosenFolder: settings.transcriptFolder
      )
      hud.showSaved(in: destination)
    } catch {
      staged.discard()
      hud.showMessage("Could not save the transcript")
    }
  }
}
