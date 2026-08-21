import Foundation

// Vendored from MyVoice/Sources/MyVoice/MyVoiceCollector.swift.

#if canImport(os)
import os
private let logger = Logger(subsystem: "com.talkify.myvoice", category: "collector")
#endif

/// Entry point for Talkify to stage a dictation sample.
/// Implements `tmp → validate → rename → event` and is designed to be called
/// from a detached Task so the insertion path never blocks.
///
/// Usage from Talkify (see docs/talkify-integration.md):
/// ```
/// if settings.myvoiceCaptureEnabled {
///     Task.detached {
///         do { try collector.collect(rawTranscript: text, correctedText: hudText, ...) }
///         catch { os_log("MyVoice save failed: %{public}@", error.localizedDescription) }
///     }
/// }
/// // insertion continues immediately
/// ```
public final class MyVoiceCollector: Sendable {
    public let storage: MyVoiceStorage

    public init(storage: MyVoiceStorage) {
        self.storage = storage
    }

    /// Convenience inits for production default root and test root.
    public convenience init(rootURL: URL) {
        self.init(storage: MyVoiceStorage(rootURL: rootURL))
    }

    /// Production default: ~/Library/Application Support/Talkify/MyVoice
    public static var defaultRootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Talkify/MyVoice", isDirectory: true)
    }

    nonisolated(unsafe) public static var shared: MyVoiceCollector = {
        let storage = MyVoiceStorage(rootURL: defaultRootURL)
        return MyVoiceCollector(storage: storage)
    }()


    /// Creates a `candidate` sample with `asr_text` immutable, `corrected_text` from HUD, `polished_text = nil`,
    /// `audio.sha256`, `duration_ms`, `status = candidate`, `human_verified = false`.
    ///
    /// - Parameters:
    ///   - rawTranscript: Exactly what SpeechTranscriber finished with (`speechService.finish()`). Immutable `asr_text`.
    ///   - correctedText: The text that will be inserted — HUD-corrected if in editable draft, otherwise equal to rawTranscript.
    ///   - audioURL: PCM CAF/WAV at analyzer feed format. Nil if capture failed or flag Off.
    ///   - startedAt: When the analyzer started (session start)
    ///   - stoppedAt: When finish() returned (session end)
    ///   - source: "talkify" (default)
    ///   - provenance: optional overrides
    /// - Returns: The committed MyVoiceRecord (after rename + event)
    @discardableResult
    public func collect(
        rawTranscript: String,
        correctedText: String,
        audioURL: URL?,
        startedAt: Date,
        stoppedAt: Date,
        source: MyVoiceSource = .talkify,
        sourceSessionId: String? = nil,
        locale: String = "en-US",
        appVersion: String? = nil
    ) throws -> MyVoiceRecord {
        let trimmedRaw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCorrected = correctedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Use stoppedAt as creation time for determinism in tests; real time is close enough.
        let now = Date()
        let createdAt = now
        let updatedAt = now

        let id = UUID().uuidString.lowercased()
        let durationMs = max(0, Int(stoppedAt.timeIntervalSince(startedAt) * 1000))

        // Audio handling
        let audioFormat: MyVoiceAudioFormat
        let audioSHA: String
        let sampleRate: Int
        let channels: Int
        let audioDurationMs: Int

        var stagedAudioSourceURL: URL? = nil

        if let audioURL, FileManager.default.fileExists(atPath: audioURL.path) {
            audioFormat = MyVoiceAudioHelper.format(for: audioURL)
            audioSHA = (try? MyVoiceAudioHelper.sha256(of: audioURL)) ?? MyVoiceAudioHelper.emptySHA256
            let fallback = durationMs
            let meta = MyVoiceAudioHelper.metadata(at: audioURL, fallbackDurationMs: fallback)
            sampleRate = meta.sampleRate
            channels = meta.channels
            audioDurationMs = meta.durationMs > 0 ? meta.durationMs : durationMs
            stagedAudioSourceURL = audioURL
        } else {
            // No audio (tee failed or flag off) — still create candidate with empty hash.
            // This path is used when audio capture fails; sample is still candidate, insertion still succeeds.
            audioFormat = .caf
            audioSHA = MyVoiceAudioHelper.emptySHA256
            sampleRate = 16000
            channels = 1
            audioDurationMs = durationMs
            stagedAudioSourceURL = nil
        }

        let audioPath = "samples/\(id)/audio/source.\(audioFormat.rawValue)"

        let transcript = MyVoiceRecord.TranscriptInfo(
            asrText: trimmedRaw,
            correctedText: trimmedCorrected.isEmpty ? trimmedRaw : trimmedCorrected,
            polishedText: nil
        )

        let provenance = MyVoiceRecord.ProvenanceInfo(
            sttProvider: "apple_speech",
            sttModel: "on-device",
            polishProvider: nil,
            polishModel: nil,
            appVersion: appVersion ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            locale: locale
        )

        let review = MyVoiceRecord.ReviewInfo(
            humanVerified: false,
            approvedAt: nil,
            excludedAt: nil,
            exclusionReason: nil,
            notes: nil
        )

        let audioInfo = MyVoiceRecord.AudioInfo(
            path: audioPath,
            sha256: audioSHA,
            format: audioFormat,
            sampleRate: sampleRate,
            channels: channels,
            durationMs: audioDurationMs
        )

        let record = MyVoiceRecord(
            schemaVersion: storage.currentSchemaVersion,
            id: id,
            source: source,
            sourceSessionId: sourceSessionId,
            status: .candidate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            audio: audioInfo,
            transcript: transcript,
            provenance: provenance,
            review: review
        )

        // Stage: tmp/<id>.<random>/ → validate → rename → event

        let stagedDir = try storage.makeStagedDirectory(for: id)

        // Use do/catch to ensure tmp cleaned on any failure before rename
        do {
            // Create subdirectories
            let audioDir = stagedDir.appendingPathComponent("audio", isDirectory: true)
            let transcriptDir = stagedDir.appendingPathComponent("transcript", isDirectory: true)
            let revisionsDir = stagedDir.appendingPathComponent("revisions", isDirectory: true)
            let fm = FileManager.default
            try fm.createDirectory(at: audioDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: transcriptDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: revisionsDir, withIntermediateDirectories: true)

            // Copy audio if available
            if let src = stagedAudioSourceURL {
                let filename = URL(fileURLWithPath: audioPath).lastPathComponent // source.caf etc
                let dest = audioDir.appendingPathComponent(filename)
                // Use copy; if fails, treat as nil-audio path? But we want to surface error for atomic test
                // For robustness, if copy fails we fall back to empty audio handling: log and set sha to empty?
                // However spec says if tee fails, audioURL nil and sample still created.
                // If copy fails here (disk-full), we should throw and insertion still pastes (caller logs)
                try fm.copyItem(at: src, to: dest)
            }

            // Write transcript files
            let asrURL = transcriptDir.appendingPathComponent("asr.txt")
            let correctedURL = transcriptDir.appendingPathComponent("corrected.txt")
            // asr.txt is immutable raw ASR
            try transcript.asrText.write(to: asrURL, atomically: true, encoding: .utf8)
            let correctedToWrite = transcript.correctedText ?? transcript.asrText
            try correctedToWrite.write(to: correctedURL, atomically: true, encoding: .utf8)
            // polished.txt absent for talkify

            // Write record.json
            let recordURL = stagedDir.appendingPathComponent("record.json")
            let jsonData = try record.jsonData()
            try jsonData.write(to: recordURL, options: .atomic)

            // Commit: validate + rename + event (storage handles tmp cleanup on fail)
            try storage.commitStagedDirectory(stagedDir, id: id, record: record)

            return record
        } catch {
            // Ensure stagedDir cleaned if storage didn't already (e.g., failure before commit)
            try? FileManager.default.removeItem(at: stagedDir)
#if canImport(os)
            logger.error("MyVoice save failed: \(error.localizedDescription, privacy: .public)")
#else
            // Fallback: print to stderr
            fputs("MyVoice save failed: \(error.localizedDescription)\n", stderr)
#endif
            throw error
        }
    }


    /// Non-blocking wrapper designed for DirectDictationController.
    /// Calls `collect` in a detached Task and logs via os_log on failure without throwing.
    /// This guarantees dictation insertion never blocks on dataset saving (hard boundary #5).
    public func collectNonBlocking(
        rawTranscript: String,
        correctedText: String,
        audioURL: URL?,
        startedAt: Date,
        stoppedAt: Date,
        source: MyVoiceSource = .talkify,
        locale: String = "en-US",
        appVersion: String? = nil
    ) {
        // Capture values for detached task
        let raw = rawTranscript
        let corrected = correctedText
        let url = audioURL
        let start = startedAt
        let stop = stoppedAt
        let loc = locale
        let ver = appVersion
        let storageRef = self.storage

        Task.detached(priority: .utility) { [storageRef] in
            let collector = MyVoiceCollector(storage: storageRef)
            do {
                _ = try collector.collect(
                    rawTranscript: raw,
                    correctedText: corrected,
                    audioURL: url,
                    startedAt: start,
                    stoppedAt: stop,
                    source: .talkify,
                    locale: loc,
                    appVersion: ver
                )
            } catch {
#if canImport(os)
                logger.error("MyVoice save failed (detached): \(error.localizedDescription, privacy: .public)")
#else
                fputs("MyVoice save failed (detached): \(error.localizedDescription)\n", stderr)
#endif
            }
        }
    }

    /// Async detached variant for callers that already run in async context.
    /// Still never throws; logs and returns.
    public func collectDetached(
        rawTranscript: String,
        correctedText: String,
        audioURL: URL?,
        startedAt: Date,
        stoppedAt: Date
    ) async {
        do {
            _ = try collect(rawTranscript: rawTranscript, correctedText: correctedText, audioURL: audioURL, startedAt: startedAt, stoppedAt: stoppedAt)
        } catch {
#if canImport(os)
            logger.error("MyVoice save failed (async detached): \(error.localizedDescription, privacy: .public)")
#else
            fputs("MyVoice save failed (async detached): \(error.localizedDescription)\n", stderr)
#endif
        }
    }
}
