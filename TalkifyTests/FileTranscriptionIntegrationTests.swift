import Foundation
import Testing

@testable import Talkify

/// Exercises the real Apple Speech path against a real file. Disabled by
/// default: it needs an installed language model and takes seconds rather
/// than milliseconds, which is not what the rest of the suite is for.
///
/// Run it deliberately after touching the transcription path:
///   TALKIFY_MEDIA=/path/to/file.m4a xcodebuild test \
///     -only-testing:TalkifyTests/FileTranscriptionIntegrationTests
@Suite(
  "File transcription against real audio",
  .enabled(if: ProcessInfo.processInfo.environment["TALKIFY_MEDIA"] != nil)
)
struct FileTranscriptionIntegrationTests {
  @Test func aSpokenFileComesBackAsText() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["TALKIFY_MEDIA"])
    let service = FileTranscriptionService()

    let progress = ProgressRecorder()
    let transcript = try await service.transcribe(
      url: URL(filePath: path),
      localeIdentifier: "en-US",
      onProgress: { progress.record($0) }
    )

    #expect(!transcript.text.isEmpty)
    #expect(transcript.wordCount > 0)
    #expect(transcript.duration > 0)
    #expect(progress.last == 1)

    // xcodebuild swallows stdout from the test process, so the result is
    // written where the caller can read it.
    let dump = """
      text: \(transcript.text)
      words: \(transcript.wordCount)
      duration: \(transcript.duration)
      progress: \(progress.values)
      """
    try? dump.write(
      to: URL(filePath: path).appendingPathExtension("out.txt"),
      atomically: true,
      encoding: .utf8
    )
  }
}

/// CONTEXT.md: a Drop Transcription of a video with no audio track ends with a
/// message rather than an empty transcript.
@Suite(
  "Video with no audio",
  .enabled(if: ProcessInfo.processInfo.environment["TALKIFY_SILENT_MEDIA"] != nil)
)
struct SilentMediaTests {
  @Test func aVideoWithNoAudioTrackIsRefused() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["TALKIFY_SILENT_MEDIA"])
    let service = FileTranscriptionService()

    await #expect(throws: FileTranscriptionService.Failure.noAudioTrack) {
      try await service.transcribe(
        url: URL(filePath: path),
        localeIdentifier: "en-US",
        onProgress: { _ in }
      )
    }
  }
}

/// The whole pipeline a drop triggers, minus the physical drag: resolve the
/// language, transcribe, resolve the destination, write the file, offer the
/// card. Runs the real controllers against a real HUD panel.
@MainActor
@Suite(
  "Drop Transcription end to end",
  .enabled(if: ProcessInfo.processInfo.environment["TALKIFY_MEDIA"] != nil)
)
struct DropPipelineTests {
  @Test func aDroppedFileEndsUpAsATranscriptBesideIt() async throws {
    let source = URL(filePath: try #require(ProcessInfo.processInfo.environment["TALKIFY_MEDIA"]))

    // A copy in its own folder, so "beside the source" is unambiguous and the
    // real Desktop is never written to.
    let workspace = URL.temporaryDirectory.appending(path: "talkify-drop-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }
    let media = workspace.appending(path: source.lastPathComponent)
    try FileManager.default.copyItem(at: source, to: media)

    let settings = AppSettings.previewStore()
    settings.recognitionLocaleIdentifier = "en-US"
    let controller = DropTranscriptionController(
      settings: settings,
      hud: DropHUDController(stage: HUDStage(settings: settings))
    )

    let progress = ProgressRecorder()
    controller.onProgressChange = { fraction in
      if let fraction { progress.record(fraction) }
    }

    controller.transcribe(media)
    #expect(controller.isRunning)

    // The job runs off the main actor; wait for it rather than polling a clock.
    for _ in 0..<600 where controller.isRunning {
      try await Task.sleep(for: .milliseconds(100))
    }
    #expect(!controller.isRunning)

    let expected = media.deletingPathExtension().appendingPathExtension("txt")
    #expect(FileManager.default.fileExists(atPath: expected.path(percentEncoded: false)))
    let text = try String(contentsOf: expected, encoding: .utf8)
    #expect(!text.isEmpty)
    #expect(progress.values.contains { $0 > 0 })
  }
}

/// The load-bearing claim of this feature's architecture: a file job builds its
/// own analyzer and shares nothing with `SpeechRecognitionService`, so pressing
/// Fn mid-job must still answer instantly (CONTEXT.md).
@Suite(
  "Dictation stays available during a file job",
  .enabled(if: ProcessInfo.processInfo.environment["TALKIFY_MEDIA"] != nil)
)
struct ConcurrencyTests {
  @Test func theDictationServiceStaysUsableWhileAFileTranscribes() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["TALKIFY_MEDIA"])
    let fileService = FileTranscriptionService()
    let speechService = SpeechRecognitionService()

    async let transcript = fileService.transcribe(
      url: URL(filePath: path),
      localeIdentifier: "en-US",
      onProgress: { _ in }
    )

    // What a trigger key does first. If the file job had taken the shared
    // session or its reservation, this is where it would stall or throw.
    let locale = try await speechService.resolveLocale(identifier: "en-US")
    try await speechService.prewarm(locale: locale)

    #expect(try await !transcript.text.isEmpty)
    await speechService.shutDown()
  }
}

/// The progress callback is `@Sendable` and fires off the test's isolation.
private final class ProgressRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [Double] = []

  func record(_ value: Double) {
    lock.withLock { recorded.append(value) }
  }

  var last: Double? {
    lock.withLock { recorded.last }
  }

  var values: [Double] {
    lock.withLock { recorded }
  }
}
