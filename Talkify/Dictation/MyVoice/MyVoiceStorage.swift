import Foundation

// Vendored from MyVoice/Sources/MyVoice/MyVoiceStorage.swift.

#if canImport(os)
import os
#endif

public enum MyVoiceStorageError: LocalizedError {
    case notADirectory(URL)
    case validationFailed(MyVoiceValidationError)
    case underlying(Error)

    public var errorDescription: String? {
        switch self {
        case .notADirectory(let url): return "Not a directory: \(url.path)"
        case .validationFailed(let e): return "Validation failed: \(e.localizedDescription)"
        case .underlying(let e): return e.localizedDescription
        }
    }
}

public final class MyVoiceStorage: @unchecked Sendable {
    public let rootURL: URL
    private let fileManager: FileManager

    // Test hook: when true, next commit will fail with injected error after validation.
    // Used by testAtomicWriteCleansTmpOnFail to simulate disk-full without filesystem mocking.
    private let failNextCommitBox: FailBox

    private final class FailBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _shouldFail = false
        var shouldFail: Bool {
            get { lock.withLock { _shouldFail } }
            set { lock.withLock { _shouldFail = newValue } }
        }
    }

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.failNextCommitBox = FailBox()
    }

    /// Inject a failure on the next commit (test-only).
    public func setNextCommitShouldFail(_ value: Bool) {
        failNextCommitBox.shouldFail = value
    }


    public var samplesURL: URL { rootURL.appendingPathComponent("samples", isDirectory: true) }
    public var tmpURL: URL { rootURL.appendingPathComponent("tmp", isDirectory: true) }
    public var eventsURL: URL { rootURL.appendingPathComponent("events.jsonl", isDirectory: false) }
    public var schemaVersionURL: URL { rootURL.appendingPathComponent("schema-version", isDirectory: false) }
    public var exportsURL: URL { rootURL.appendingPathComponent("exports", isDirectory: true) }

    public var currentSchemaVersion: Int {
        guard let data = try? Data(contentsOf: schemaVersionURL),
              let s = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let v = Int(s) else {
            return 1
        }
        return v
    }


    @discardableResult
    public func ensureRoot() throws -> URL {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: samplesURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tmpURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: exportsURL, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: schemaVersionURL.path) {
            try "1\n".write(to: schemaVersionURL, atomically: true, encoding: .utf8)
        }
        if !fileManager.fileExists(atPath: eventsURL.path) {
            fileManager.createFile(atPath: eventsURL.path, contents: Data())
        }
        return rootURL
    }

    public func writeSchemaVersion(_ version: Int) throws {
        try "\(version)\n".write(to: schemaVersionURL, atomically: true, encoding: .utf8)
    }


    /// Create a fresh tmp staging directory for sample id, with random suffix to avoid collisions.
    /// Returns URL of the staging dir (e.g., tmp/<id>.<random>/).
    public func makeStagedDirectory(for id: String) throws -> URL {
        try ensureRoot()
        let suffix = UUID().uuidString.lowercased().prefix(8)
        let dir = tmpURL.appendingPathComponent("\(id).\(suffix)", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Convenience to get staged directory path for test introspection (list tmp).
    public func listTmpDirectories() throws -> [URL] {
        guard fileManager.fileExists(atPath: tmpURL.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil)
        return contents.filter { $0.hasDirectoryPath }
    }

    /// Validate the staged sample at stagedDir.
    /// Checks: record.json exists and decodes, schema_version matches root, status allowed,
    /// audio sha matches if audio file exists, audio path present.
    public func validateStaged(at stagedDir: URL, expectedId: String? = nil) throws {
        let recordURL = stagedDir.appendingPathComponent("record.json")
        guard fileManager.fileExists(atPath: recordURL.path) else {
            throw MyVoiceValidationError.audioMissing(path: recordURL.path)
        }
        let data = try Data(contentsOf: recordURL)
        let record = try MyVoiceRecord.from(jsonData: data)

        if let expectedId, record.id != expectedId {
            // Not a validation failure per se, but treat as mismatch
            throw MyVoiceValidationError.invalidStatus(
                "id mismatch expected \(expectedId) found \(record.id)"
            )
        }

        // schema_version must match root
        let expectedSchema = currentSchemaVersion
        if record.schemaVersion != expectedSchema {
            throw MyVoiceValidationError.schemaMismatch(expected: expectedSchema, found: record.schemaVersion)
        }

        // status must be allowed
        let allowed = MyVoiceStatus.allCases.map { $0.rawValue }
        if !allowed.contains(record.status.rawValue) {
            throw MyVoiceValidationError.invalidStatus(record.status.rawValue)
        }

        // audio.sha256 must match file if file is expected
        // record.audio.path is relative to root, e.g., samples/<id>/audio/source.caf
        // Staged layout mirrors final: we expect stagedDir/audio/source.<ext> to correspond.
        let audioFilename = URL(fileURLWithPath: record.audio.path).lastPathComponent
        // Look for audio file in stagedDir/audio/
        let stagedAudioDir = stagedDir.appendingPathComponent("audio", isDirectory: true)
        let stagedAudioURL = stagedAudioDir.appendingPathComponent(audioFilename)

        // If audio path indicates a format requiring file, check existence.
        // For talkify captures with audioURL == nil, we allow missing audio file
        // but only if sha is empty hash. Otherwise require file.
        let emptyHash = MyVoiceAudioHelper.emptySHA256
        let hasAudioFile = fileManager.fileExists(atPath: stagedAudioURL.path)

        if !hasAudioFile {
            // Allow missing only when sha is empty (nil-audio case)
            if record.audio.sha256 != emptyHash {
                // If sha is not empty, we expect a file
                throw MyVoiceValidationError.audioMissing(path: stagedAudioURL.path)
            }
        } else {
            let actual = try MyVoiceAudioHelper.sha256(of: stagedAudioURL)
            if actual.lowercased() != record.audio.sha256.lowercased() {
                throw MyVoiceValidationError.shaMismatch(expected: record.audio.sha256, actual: actual)
            }
        }

        // Additional check: asr_text present? Empty is allowed but considered corrupt downstream;
        // here we don't fail for empty, but we ensure record can be decoded.
        // If you want to enforce non-empty for candidate, uncomment:
        // if record.transcript.asrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        //     throw MyVoiceValidationError.missingASRText
        // }

        // Transcript files should exist and match record
        let asrURL = stagedDir.appendingPathComponent("transcript/asr.txt")
        let correctedURL = stagedDir.appendingPathComponent("transcript/corrected.txt")
        if fileManager.fileExists(atPath: asrURL.path) {
            let asrFileContent = try String(contentsOf: asrURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let recordASR = record.transcript.asrText.trimmingCharacters(in: .whitespacesAndNewlines)
            if asrFileContent != recordASR {
                // Not fatal per se, but treat as mismatch to enforce immutability contract
                // We log but don't fail? Contract says asr.txt is written once and never modified.
                // So staged must match record.
                throw MyVoiceValidationError.shaMismatch(expected: recordASR, actual: asrFileContent)
            }
        }
        if fileManager.fileExists(atPath: correctedURL.path) {
            let correctedContent = try String(contentsOf: correctedURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let recCorrected = (record.transcript.correctedText ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if correctedContent != recCorrected {
                throw MyVoiceValidationError.shaMismatch(expected: recCorrected, actual: correctedContent)
            }
        }
    }

    /// Commit stagedDir to samples/<id>/ via atomic rename, then append event.
    /// On any failure before rename, stagedDir is removed (clean tmp).
    /// Incomplete tmp never appears in samples.
    public func commitStagedDirectory(_ stagedDir: URL, id: String, record: MyVoiceRecord) throws {
        try commitStagedDirectory(stagedDir, id: id, record: record, eventType: "created", extraEvent: nil)
    }

    /// Commit with custom event type (e.g., "imported" for OpenScribe). Exists for importer idempotency.
    public func commitStagedDirectory(
        _ stagedDir: URL,
        id: String,
        record: MyVoiceRecord,
        eventType: String,
        extraEvent: [String: String]? = nil
    ) throws {
        // Pre-check test injection
        let shouldFailInjected = failNextCommitBox.shouldFail
        if shouldFailInjected {
            failNextCommitBox.shouldFail = false
        }

        do {
            try validateStaged(at: stagedDir, expectedId: id)

            if shouldFailInjected {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(ENOSPC),
                    userInfo: [NSLocalizedDescriptionKey: "Injected disk-full for test (ENOSPC)"]
                )
            }

            let destination = samplesURL.appendingPathComponent(id, isDirectory: true)

            // Ensure samples parent exists
            try fileManager.createDirectory(at: samplesURL, withIntermediateDirectories: true)

            // If destination already exists (duplicate import), treat as error - caller decides.
            if fileManager.fileExists(atPath: destination.path) {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileWriteFileExistsError,
                    userInfo: [NSLocalizedDescriptionKey: "Sample \(id) already exists"]
                )
            }

            try fileManager.moveItem(at: stagedDir, to: destination)

            // Append event after successful rename
            try appendEvent(
                type: eventType,
                sampleId: id,
                status: record.status.rawValue,
                source: record.source.rawValue,
                extra: extraEvent
            )

        } catch {
            // On failure, remove stagedDir to clean tmp (test expects this)
            try? fileManager.removeItem(at: stagedDir)
            // Map validation errors
            if let ve = error as? MyVoiceValidationError {
                throw MyVoiceStorageError.validationFailed(ve)
            }
            throw MyVoiceStorageError.underlying(error)
        }
    }


    public func appendEvent(
        type: String,
        sampleId: String,
        status: String? = nil,
        source: String? = nil,
        extra: [String: String]? = nil
    ) throws {
        var event: [String: String] = [
            "at": ISO8601DateFormatter().string(from: Date()),
            "type": type,
            "sample_id": sampleId
        ]
        if let status { event["status"] = status }
        if let source { event["source"] = source }
        if let extra { for (k,v) in extra { event[k] = v } }

        let lineData: Data
        do {
            lineData = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        } catch {
            throw MyVoiceStorageError.underlying(error)
        }
        var line = lineData
        line.append("\n".data(using: .utf8)!)

        // Use FileHandle append
        let url = eventsURL
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: Data())
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    public func readEvents() throws -> [[String: String]] {
        guard fileManager.fileExists(atPath: eventsURL.path) else { return [] }
        let content = try String(contentsOf: eventsURL, encoding: .utf8)
        let lines = content.split(separator: "\n").filter { !$0.isEmpty }
        return lines.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: String]
        }
    }


    public func cleanupTmp() throws {
        guard fileManager.fileExists(atPath: tmpURL.path) else { return }
        let contents = try fileManager.contentsOfDirectory(at: tmpURL, includingPropertiesForKeys: nil)
        for url in contents {
            try? fileManager.removeItem(at: url)
        }
    }


    public func sampleExists(id: String) -> Bool {
        let dest = samplesURL.appendingPathComponent(id, isDirectory: true)
        return fileManager.fileExists(atPath: dest.path)
    }

    public func recordURL(for id: String) -> URL {
        samplesURL.appendingPathComponent(id, isDirectory: true).appendingPathComponent("record.json")
    }

    public func readRecord(id: String) throws -> MyVoiceRecord {
        let data = try Data(contentsOf: recordURL(for: id))
        return try MyVoiceRecord.from(jsonData: data)
    }


    public struct StoreStats: Sendable, Equatable {
        public var total: Int = 0
        public var byStatus: [String: Int] = [:]
        public var totalDurationMs: Int = 0
        public var lastExport: String? = nil
    }

    public func computeStats() throws -> StoreStats {
        var stats = StoreStats()
        guard fileManager.fileExists(atPath: samplesURL.path) else { return stats }
        let entries = try fileManager.contentsOfDirectory(
            at: samplesURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for entry in entries {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            let recordURL = entry.appendingPathComponent("record.json")
            guard fileManager.fileExists(atPath: recordURL.path),
                  let data = try? Data(contentsOf: recordURL),
                  let rec = try? MyVoiceRecord.from(jsonData: data) else { continue }
            stats.total += 1
            stats.byStatus[rec.status.rawValue, default: 0] += 1
            stats.totalDurationMs += rec.audio.durationMs
        }
        // Last export: most recent directory in exports/
        if fileManager.fileExists(atPath: exportsURL.path),
           let exports = try? fileManager.contentsOfDirectory(
               at: exportsURL,
               includingPropertiesForKeys: [.creationDateKey]
           ) {
            let sorted = exports.sorted { (a,b) -> Bool in
                let ad = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let bd = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return ad > bd
            }
            if let latest = sorted.first {
                stats.lastExport = latest.lastPathComponent
            }
        }
        return stats
    }

    public func listRecords() throws -> [MyVoiceRecord] {
        guard fileManager.fileExists(atPath: samplesURL.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(at: samplesURL, includingPropertiesForKeys: nil)
        var records: [MyVoiceRecord] = []
        for entry in entries {
            let recordURL = entry.appendingPathComponent("record.json")
            guard fileManager.fileExists(atPath: recordURL.path),
                  let data = try? Data(contentsOf: recordURL),
                  let rec = try? MyVoiceRecord.from(jsonData: data) else { continue }
            records.append(rec)
        }
        return records
    }
}
