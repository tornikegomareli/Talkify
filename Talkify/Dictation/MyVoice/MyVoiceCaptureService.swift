import Foundation

#if canImport(os)
import os
private let logger = Logger(subsystem: "com.talkify.myvoice", category: "capture")
#endif

/// The non-blocking transcript capture boundary Talkify's controller calls.
///
/// A session's raw ASR and final draft are saved as a MyVoice candidate when
/// `myvoiceCaptureEnabled` is On. Saving never blocks or fails dictation:
/// empty transcripts are skipped, and collector throws are logged.
protocol MyVoiceCaptureServicing: Sendable {
  func capture(
    rawTranscript: String,
    correctedText: String,
    audioURL: URL?,
    startedAt: Date,
    stoppedAt: Date,
    localeIdentifier: String
  )
}

/// Production bridge over the vendored MyVoice storage path.
///
/// Audio tee is intentionally transcript-only in this slice: the converted buffer
/// stream exists in `MicrophoneInput`, but teeing it to a temp CAF adds
/// lifecycle across start/finish/cancel that expands scope (see
/// docs/MyVoiceIntegration.md § Audio). Candidates are created with nil audio
/// (`emptySHA256`), which the MyVoice contract allows; adding the tee later
/// keeps the same `tmp → validate → rename → event` path with a real file.
final class MyVoiceCaptureService: MyVoiceCaptureServicing, Sendable {
  private let collector: MyVoiceCollector
  private let enabled: @Sendable () -> Bool

  init(collector: MyVoiceCollector, enabled: @escaping @Sendable () -> Bool) {
    self.collector = collector
    self.enabled = enabled
  }

  convenience init(enabled: @escaping @Sendable () -> Bool) {
    let storage = MyVoiceStorage(rootURL: MyVoiceCollector.defaultRootURL)
    self.init(collector: MyVoiceCollector(storage: storage), enabled: enabled)
  }

  func capture(
    rawTranscript: String,
    correctedText: String,
    audioURL: URL?,
    startedAt: Date,
    stoppedAt: Date,
    localeIdentifier: String
  ) {
    guard enabled() else { return }
    let raw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return }

    let corrected = correctedText
    let url = audioURL
    let start = startedAt
    let stop = stoppedAt
    let locale = localeIdentifier
    let storage = collector.storage

    Task.detached(priority: .utility) {
      let collector = MyVoiceCollector(storage: storage)
      do {
        _ = try collector.collect(
          rawTranscript: raw,
          correctedText: corrected,
          audioURL: url,
          startedAt: start,
          stoppedAt: stop,
          locale: locale
        )
      } catch {
#if canImport(os)
        logger.error("MyVoice save failed: \(error.localizedDescription, privacy: .public)")
#else
        fputs("MyVoice save failed: \(error.localizedDescription)\n", stderr)
#endif
      }
    }
  }
}

/// No-op implementation for when the feature is off or in fakes that need
/// explicit control over captured calls.
final class NoopMyVoiceCaptureService: MyVoiceCaptureServicing, Sendable {
  func capture(
    rawTranscript: String,
    correctedText: String,
    audioURL: URL?,
    startedAt: Date,
    stoppedAt: Date,
    localeIdentifier: String
  ) {}
}
