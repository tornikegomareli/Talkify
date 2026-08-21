import Foundation
// Vendored from MyVoice/Sources/MyVoice/MyVoiceAudio.swift.
import CryptoKit

#if canImport(AVFoundation)
import AVFoundation
#endif

public enum MyVoiceAudioHelper {
    /// SHA-256 of file bytes, lowercase hex. Throws if file missing.
    public static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return sha256(of: data)
    }

    public static func sha256(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Empty data hash (e3b0...)
    public static var emptySHA256: String {
        sha256(of: Data())
    }

    /// Audio format from file extension, defaults to caf.
    public static func format(for url: URL) -> MyVoiceAudioFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "wav": return .wav
        case "m4a": return .m4a
        case "caf": return .caf
        default: return .caf
        }
    }

    /// Attempt to read sampleRate/channels/durationMs via AVFoundation.
    /// Falls back to defaults (16000, 1) and durationMs from file size estimate if unavailable.
    public static func metadata(
        at url: URL,
        fallbackDurationMs: Int
    ) -> (sampleRate: Int, channels: Int, durationMs: Int) {
#if canImport(AVFoundation)
        // Try AVAudioFile for CAF/WAV — synchronous, no async required.
        if let file = try? AVAudioFile(forReading: url) {
            let sr = Int(file.fileFormat.sampleRate)
            let ch = Int(file.fileFormat.channelCount)
            let frames = file.length
            let durationMs: Int
            if file.fileFormat.sampleRate > 0 {
                durationMs = Int((Double(frames) / file.fileFormat.sampleRate) * 1000.0)
            } else {
                durationMs = fallbackDurationMs
            }
            return (sr > 0 ? sr : 16000, ch > 0 ? ch : 1, durationMs)
        }
#endif
        return (16000, 1, fallbackDurationMs)
    }

    /// Write a minimal silent CAF/WAV helper for tests (if needed).
    /// Creates a file with given data or empty.
    public static func writeDummyAudio(to url: URL, data: Data = Data("dummy-pcm".utf8)) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
