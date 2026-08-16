import AVFoundation
import Foundation
import Speech

/// Transcribes an audio or video file off the microphone path entirely.
///
/// This deliberately shares nothing with `SpeechRecognitionService`. That actor
/// holds one active session plus a prewarmed analyzer per bound language, all
/// so a trigger key answers instantly; a file job that borrowed either would
/// stall live dictation for minutes. Here every job builds its own transcriber
/// and analyzer and throws them away afterwards, which a job already measured
/// in minutes can easily afford.
actor FileTranscriptionService {
  struct Transcript: Sendable {
    let text: String
    let duration: TimeInterval

    var wordCount: Int {
      text.split { $0.isWhitespace || $0.isNewline }.count
    }
  }

  enum Failure: LocalizedError {
    case unavailable
    case unsupportedLocale
    case noAudioTrack
    case unreadable
    case emptyTranscript

    var errorDescription: String? {
      switch self {
      case .unavailable: "Speech recognition is unavailable"
      case .unsupportedLocale: "That language is not supported"
      case .noAudioTrack: "No audio in that file"
      case .unreadable: "Could not read that file"
      case .emptyTranscript: "No speech found"
      }
    }
  }

  /// Transcribes `url`, reporting 0…1 as it goes. Progress comes from the
  /// audio time ranges the transcriber stamps on its results, so it tracks
  /// real position in the file rather than elapsed wall time.
  func transcribe(
    url: URL,
    localeIdentifier: String,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws -> Transcript {
    guard SpeechTranscriber.isAvailable else { throw Failure.unavailable }
    guard let locale = await Self.resolveLocale(identifier: localeIdentifier) else {
      throw Failure.unsupportedLocale
    }

    let duration = try await duration(of: url)
    let audioFile = try await openAsAudio(url)
    defer { discardTemporaryFile() }

    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      // No volatile results: nothing renders a live draft for a file job, and
      // finalized-only halves the result traffic on a long recording.
      reportingOptions: [],
      // The stamps are what progress is derived from.
      attributeOptions: [.audioTimeRange]
    )

    if let installation = try await AssetInventory.assetInstallationRequest(
      supporting: [transcriber]
    ) {
      try await installation.downloadAndInstall()
    }

    let analyzer = SpeechAnalyzer(modules: [transcriber])

    async let collected = collect(
      from: transcriber,
      duration: duration,
      onProgress: onProgress
    )

    if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
      try await analyzer.finalizeAndFinish(through: lastSample)
    } else {
      await analyzer.cancelAndFinishNow()
    }

    let text = try await collected.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw Failure.emptyTranscript }

    onProgress(1)
    return Transcript(text: text, duration: duration)
  }

  /// Concatenates finalized results, reporting how far through the file each
  /// one lands. Reading the stream concurrently with `analyzeSequence` is
  /// Apple's own shape for this (WWDC25-277).
  private func collect(
    from transcriber: SpeechTranscriber,
    duration: TimeInterval,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws -> String {
    var text = AttributedString()
    for try await result in transcriber.results {
      text += result.text
      guard duration > 0 else { continue }
      if let reached = result.text.runs.compactMap(\.audioTimeRange).last?.end.seconds {
        onProgress(min(max(reached / duration, 0), 1))
      }
    }
    return String(text.characters)
  }

  /// The dictation language, or the Mac's own when the user never picked one.
  /// Resolution is entirely static API, which is why this needs nothing from
  /// `SpeechRecognitionService` and cannot disturb its reservations.
  private static func resolveLocale(identifier: String) async -> Locale? {
    if !identifier.isEmpty,
       let picked = await SpeechTranscriber.supportedLocale(
         equivalentTo: Locale(identifier: identifier)
       ) {
      return picked
    }
    return await SpeechTranscriber.supportedLocale(equivalentTo: .current)
  }

  private func duration(of url: URL) async throws -> TimeInterval {
    let asset = AVURLAsset(url: url)
    guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
      throw Failure.noAudioTrack
    }
    return try await asset.load(.duration).seconds
  }

  /// Where the source is already something Core Audio reads, this is just an
  /// open. A movie container usually is not, so its audio track is exported to
  /// a temporary file first and removed when the job ends.
  private var temporaryFile: URL?

  private func openAsAudio(_ url: URL) async throws -> AVAudioFile {
    if let file = try? AVAudioFile(forReading: url) { return file }

    let exported = try await exportAudioTrack(of: url)
    temporaryFile = exported
    guard let file = try? AVAudioFile(forReading: exported) else { throw Failure.unreadable }
    return file
  }

  private func exportAudioTrack(of url: URL) async throws -> URL {
    let asset = AVURLAsset(url: url)
    guard let session = AVAssetExportSession(
      asset: asset,
      presetName: AVAssetExportPresetAppleM4A
    ) else {
      throw Failure.unreadable
    }

    let destination = URL.temporaryDirectory
      .appending(path: "talkify-\(UUID().uuidString).m4a")
    try await session.export(to: destination, as: .m4a)
    return destination
  }

  private func discardTemporaryFile() {
    guard let temporaryFile else { return }
    try? FileManager.default.removeItem(at: temporaryFile)
    self.temporaryFile = nil
  }
}
