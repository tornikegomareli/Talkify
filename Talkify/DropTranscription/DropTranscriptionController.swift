import AppKit
import Foundation

/// Turns a dragged file into a running job: watches for the drag, opens the
/// target, takes the drop, and transcribes.
///
/// What becomes of the finished transcript is `TranscriptOffer`'s, and what the
/// shape looks like is `DropHUDController`'s. This owns the gesture and the
/// job, and one job at a time — a second request while one runs is refused
/// rather than queued, because the HUD can only hold one result and a queue is
/// a feature nobody has asked for yet.
@MainActor
final class DropTranscriptionController {
  /// How long the target waits for a drop after the button comes up over it
  /// before assuming none is coming.
  private static let dropGrace = Duration.milliseconds(600)
  /// How long the shape holds the dropped file before the job starts. Long
  /// enough to read the name and see the icon land — the point of it is that
  /// the drop has an ending you can watch.
  private static let heldDuration = Duration.milliseconds(1100)

  private let settings: AppSettings
  private let hud: DropHUDController
  private let transcriptionService = FileTranscriptionService()
  private let dragWatcher = DragWatcher()
  private var job: Task<Void, Never>?
  private var isShowingTarget = false
  /// The file the open target is standing by for, read from the drag
  /// pasteboard on the way in. Holding it is what lets the drop itself be
  /// answered without reading anything.
  private var armedURL: URL?
  private var dropWatchdog: Task<Void, Never>?
  private var heldTask: Task<Void, Never>?
  private let offer: TranscriptOffer
  /// Reported while a job runs, for the status item.
  var onProgressChange: ((Double?) -> Void)?

  var isRunning: Bool { job != nil }

  init(settings: AppSettings, hud: DropHUDController) {
    self.settings = settings
    self.hud = hud
    offer = TranscriptOffer(settings: settings, hud: hud)
    hud.onDropReceived = { [weak self] index in
      self?.acceptDrop(languageIndex: index)
    }
    hud.onCardEvent = { [weak self] event in
      self?.offer.handle(event)
    }
  }

  /// Starts watching for a media file dragged toward the notch.
  func start() {
    dragWatcher.onZoneChange = { [weak self] zone, url in
      self?.showTarget(for: zone, url: url)
    }
    dragWatcher.onDragEnd = { [weak self] zone in
      self?.endDrag(in: zone)
    }
    dragWatcher.start()
  }

  private func showTarget(for zone: DropZone, url: URL) {
    guard !isRunning else { return }
    switch zone {
    case .outside:
      dismissTargetIfArmed()
    case .peek, .open:
      armedURL = url
      let tags = settings.languageTagsForDrop
      if isShowingTarget {
        hud.setTargetOpen(zone == .open)
      } else {
        isShowingTarget = true
        hud.showTarget(
          fileName: url.lastPathComponent,
          isOpen: zone == .open,
          languageTags: tags
        )
      }
    }
  }

  /// The button came up.
  ///
  /// Over the open target that is a drop, and the drop owns everything that
  /// follows. Dismissing here instead would take the destination out from
  /// under the drop AppKit is still delivering — `hideDrop` stops the panel
  /// accepting the mouse — and macOS answers a refused drop by flying the item
  /// back to where it came from. That flight is what made dropping on the
  /// notch feel slow next to dropping on the Desktop.
  ///
  /// A release anywhere else in the catch area is just a drag that ended, so
  /// the target goes away at once.
  private func endDrag(in zone: DropZone) {
    guard zone == .open else {
      dismissTargetIfArmed()
      return
    }
    // If the drop never lands — released on a window sitting over the HUD, or
    // refused for a reason we cannot see — the target must not be left open.
    dropWatchdog?.cancel()
    dropWatchdog = Task { [weak self] in
      try? await Task.sleep(for: Self.dropGrace)
      guard !Task.isCancelled, let self else { return }
      dismissTargetIfArmed()
    }
  }

  private func dismissTargetIfArmed() {
    dropWatchdog?.cancel()
    dropWatchdog = nil
    // `isShowingTarget` is already false once a file has been taken, so a
    // late mouse-up cannot cut short the shape holding it.
    armedURL = nil
    guard isShowingTarget else { return }
    isShowingTarget = false
    hud.hide()
  }

  /// A file landed on the shape. `languageIndex` is which half took it, which
  /// is the language choice when a second language is configured.
  ///
  /// This runs a turn of the run loop after the drop was accepted, so the item
  /// is already off the pointer by the time any of it happens. The file is the
  /// one the target opened for; nothing is read from the drop itself.
  private func acceptDrop(languageIndex: Int) {
    dropWatchdog?.cancel()
    dropWatchdog = nil
    guard let url = armedURL else { return }
    armedURL = nil
    isShowingTarget = false

    // The shape takes the file and shows it. Nothing starts yet: the drop is
    // answered by the notch holding what was dropped, which is the end of the
    // gesture the user performed. The job begins once that has been seen.
    hud.showHeld(
      fileName: url.lastPathComponent,
      icon: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    )

    heldTask?.cancel()
    heldTask = Task { [weak self] in
      try? await Task.sleep(for: Self.heldDuration)
      guard !Task.isCancelled, let self else { return }
      hud.hide()
      transcribe(url, languageIndex: languageIndex)
    }
  }

  /// The discoverable path into the feature, for anyone who never finds the
  /// drag or cannot perform one.
  func pickFile() {
    guard !isRunning else {
      hud.showMessage("Already transcribing")
      return
    }

    let panel = NSOpenPanel()
    panel.allowedContentTypes = MediaFileTypes.openPanelTypes
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.prompt = "Transcribe"
    panel.message = "Choose an audio or video file to transcribe."

    // Under LSUIElement the panel opens behind everything unless the app is
    // activated first, the same problem Sparkle's windows have.
    NSApp.activate()
    guard panel.runModal() == .OK, let url = panel.url else { return }
    transcribe(url)
  }

  func transcribe(_ url: URL, languageIndex: Int = 0) {
    guard !isRunning else {
      hud.showMessage("Already transcribing")
      return
    }
    guard MediaFileTypes.isTranscribable(url: url) else {
      hud.showMessage("Not an audio or video file")
      return
    }

    // The card can only hold one transcript, and the one already there was
    // earned; a second file takes the shape, so the first goes to disk.
    offer.commit()
    let localeIdentifier = settings.localeIdentifierForDrop(languageIndex: languageIndex)

    // Nothing in the shape while a job runs. The drop target retracts and the
    // menu bar ghost carries progress from there.
    onProgressChange?(0)

    job = Task { [weak self] in
      defer {
        self?.job = nil
        self?.onProgressChange?(nil)
      }
      do {
        guard let self else { return }
        let transcript = try await transcriptionService.transcribe(
          url: url,
          localeIdentifier: localeIdentifier,
          onProgress: { fraction in
            Task { @MainActor [weak self] in self?.onProgressChange?(fraction) }
          }
        )
        try Task.checkCancellation()

        // Staged, not saved: the card is where the user picks a destination,
        // and the Save-to location is what happens if they pick none
        // (CONTEXT.md). The file is real from here on either way.
        let staged = try StagedTranscript.stage(text: transcript.text, source: url)
        offer.present(
          staged,
          as: DropHUDContent.Transcript(
            url: staged.url,
            text: transcript.text,
            wordCount: transcript.wordCount,
            duration: transcript.duration
          )
        )
      } catch is CancellationError {
        return
      } catch {
        self?.hud.showMessage(Self.message(for: error))
      }
    }
  }

  /// Writes a still-offered transcript out rather than losing it, for the one
  /// moment the card cannot survive: Talkify quitting.
  func commitOfferedTranscript() {
    offer.commit()
  }

  /// A transcription failure has to fit the HUD's one-line band, so the
  /// service's own wording is used where it has any and everything else
  /// collapses to one phrase.
  private static func message(for error: any Error) -> String {
    (error as? FileTranscriptionService.Failure)?.errorDescription
      ?? "Could not transcribe that file"
  }
}
