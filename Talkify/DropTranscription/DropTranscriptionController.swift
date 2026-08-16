import AppKit
import Foundation

/// Runs a Drop Transcription end to end: resolve the language, transcribe the
/// file, write the transcript, and say what happened.
///
/// One job at a time. A second request while one runs is refused rather than
/// queued — the HUD can only hold one result, and a queue is a feature nobody
/// has asked for yet.
@MainActor
final class DropTranscriptionController {
  /// How long a finished card waits to be grabbed. Short, because the file is
  /// already on disk and dismissing loses nothing; the timer stops the moment
  /// the pointer arrives, so reaching for it always wins.
  private static let cardLifetime = Duration.seconds(5)
  private static let cardTick = Duration.milliseconds(50)

  private let settings: AppSettings
  private let hudController: DictationHUDController
  private let transcriptionService = FileTranscriptionService()
  private let dragWatcher = DragWatcher()
  private var job: Task<Void, Never>?
  private var cardTimer: Task<Void, Never>?
  private var isShowingTarget = false
  /// Reported while a job runs, for the status item.
  var onProgressChange: ((Double?) -> Void)?

  var isRunning: Bool { job != nil }

  init(settings: AppSettings, hudController: DictationHUDController) {
    self.settings = settings
    self.hudController = hudController
    hudController.onDropReceived = { [weak self] url, index in
      self?.acceptDrop(url, languageIndex: index) ?? false
    }
    hudController.onTranscriptCardHover = { [weak self] isInside in
      self?.setCardHovered(isInside)
    }
  }

  /// Starts watching for a media file dragged toward the notch.
  func start() {
    dragWatcher.onZoneChange = { [weak self] zone, url in
      self?.showTarget(for: zone, url: url)
    }
    dragWatcher.onDragEnd = { [weak self] in
      self?.dismissTargetIfArmed()
    }
    dragWatcher.start()
  }

  private func showTarget(for zone: DropZone, url: URL) {
    guard !isRunning else { return }
    switch zone {
    case .outside:
      dismissTargetIfArmed()
    case .peek, .open:
      let tags = settings.languageTagsForDrop
      if isShowingTarget {
        hudController.setDropTargetOpen(zone == .open)
      } else {
        isShowingTarget = true
        hudController.showDropTarget(
          fileName: url.lastPathComponent,
          isOpen: zone == .open,
          languageTags: tags
        )
      }
    }
  }

  private func dismissTargetIfArmed() {
    guard isShowingTarget else { return }
    isShowingTarget = false
    hudController.hideDrop()
  }

  /// A file landed on the shape. `languageIndex` is which half took it, which
  /// is the language choice when a second language is configured.
  private func acceptDrop(_ url: URL, languageIndex: Int) -> Bool {
    guard MediaFileTypes.isTranscribable(url: url) else { return false }
    isShowingTarget = false
    hudController.hideDrop()
    transcribe(url, languageIndex: languageIndex)
    return true
  }

  /// The discoverable path into the feature, for anyone who never finds the
  /// drag or cannot perform one.
  func pickFile() {
    guard !isRunning else {
      hudController.showMessage("Already transcribing")
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
      hudController.showMessage("Already transcribing")
      return
    }
    guard MediaFileTypes.isTranscribable(url: url) else {
      hudController.showMessage("Not an audio or video file")
      return
    }

    let destinationPreference = settings.transcriptDestination
    let folder = settings.transcriptFolder
    let localeIdentifier = settings.localeIdentifierForDrop(languageIndex: languageIndex)

    hudController.showMessage("Transcribing \(url.lastPathComponent)")
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

        let destination = TranscriptDestination.resolve(
          for: url,
          preference: destinationPreference,
          chosenFolder: folder
        )
        // Written before the card appears, so the result never depends on the
        // user catching the HUD (CONTEXT.md).
        try transcript.text.write(to: destination, atomically: true, encoding: .utf8)
        presentCard(
          HUDDropContent.Transcript(
            url: destination,
            wordCount: transcript.wordCount,
            duration: transcript.duration
          )
        )
      } catch is CancellationError {
        return
      } catch {
        self?.hudController.showMessage(Self.message(for: error))
      }
    }
  }

  /// Offers the written transcript and starts its countdown.
  private func presentCard(_ transcript: HUDDropContent.Transcript) {
    hudController.showTranscript(transcript)
    startCardTimer()
  }

  private func startCardTimer() {
    cardTimer?.cancel()
    cardTimer = Task { [weak self] in
      let ticks = Int(Self.cardLifetime / Self.cardTick)
      for tick in 0...ticks {
        try? await Task.sleep(for: Self.cardTick)
        guard !Task.isCancelled, let self else { return }
        hudController.setTranscriptRemaining(1 - Double(tick) / Double(ticks))
      }
      guard !Task.isCancelled, let self else { return }
      hudController.hideDrop()
      cardTimer = nil
    }
  }

  /// The pointer reaching the card cancels its deadline; leaving restarts it.
  /// A surface that asks for a drag must not expire while it is being reached
  /// for.
  private func setCardHovered(_ isHovered: Bool) {
    if isHovered {
      cardTimer?.cancel()
      cardTimer = nil
      hudController.setTranscriptRemaining(0)
    } else if cardTimer == nil {
      hudController.setTranscriptRemaining(1)
      startCardTimer()
    }
  }

  func cancel() {
    job?.cancel()
    job = nil
    cardTimer?.cancel()
    cardTimer = nil
  }

  /// A transcription failure has to fit the HUD's one-line band, so the
  /// service's own wording is used where it has any and everything else
  /// collapses to one phrase.
  private static func message(for error: any Error) -> String {
    (error as? FileTranscriptionService.Failure)?.errorDescription
      ?? "Could not transcribe that file"
  }
}
