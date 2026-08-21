import Foundation

// Vendored from MyVoice/Sources/MyVoice/MyVoiceRecord.swift —
// contract-identical storage type for the Talkify → MyVoice bridge.
// See docs/MyVoiceIntegration.md for the vendoring rationale.


public enum MyVoiceSource: String, Codable, CaseIterable, Sendable {
    case talkify
    case openscribe
}

public enum MyVoiceStatus: String, Codable, CaseIterable, Sendable {
    case candidate
    case needsReview = "needs_review"
    case approved
    case excluded
    case duplicate
    case corrupt
}

public enum MyVoiceAudioFormat: String, Codable, Sendable {
    case caf
    case wav
    case m4a
}

public enum MyVoiceExclusionReason: String, Codable, Sendable {
    case backgroundNoise = "background-noise"
    case truncated
    case mislabeled
    case duplicate
    case sensitive
    case empty
    case corrupt
    case other
}


public struct MyVoiceRecord: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var id: String
    public var source: MyVoiceSource
    public var sourceSessionId: String?
    public var status: MyVoiceStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var audio: AudioInfo
    public var transcript: TranscriptInfo
    public var provenance: ProvenanceInfo
    public var review: ReviewInfo

    public struct AudioInfo: Codable, Sendable, Equatable {
        public var path: String
        public var sha256: String
        public var format: MyVoiceAudioFormat
        public var sampleRate: Int
        public var channels: Int
        public var durationMs: Int

        public init(
            path: String,
            sha256: String,
            format: MyVoiceAudioFormat,
            sampleRate: Int,
            channels: Int,
            durationMs: Int
        ) {
            self.path = path
            self.sha256 = sha256
            self.format = format
            self.sampleRate = sampleRate
            self.channels = channels
            self.durationMs = durationMs
        }

        enum CodingKeys: String, CodingKey {
            case path, sha256, format
            case sampleRate = "sample_rate"
            case channels
            case durationMs = "duration_ms"
        }
    }

    public struct TranscriptInfo: Codable, Sendable, Equatable {
        public var asrText: String
        public var correctedText: String?
        public var polishedText: String?

        public init(asrText: String, correctedText: String?, polishedText: String? = nil) {
            self.asrText = asrText
            self.correctedText = correctedText
            self.polishedText = polishedText
        }

        enum CodingKeys: String, CodingKey {
            case asrText = "asr_text"
            case correctedText = "corrected_text"
            case polishedText = "polished_text"
        }
    }

    public struct ProvenanceInfo: Codable, Sendable, Equatable {
        public var sttProvider: String?
        public var sttModel: String?
        public var polishProvider: String?
        public var polishModel: String?
        public var appVersion: String?
        public var locale: String?

        public init(
            sttProvider: String?,
            sttModel: String?,
            polishProvider: String? = nil,
            polishModel: String? = nil,
            appVersion: String?,
            locale: String?
        ) {
            self.sttProvider = sttProvider
            self.sttModel = sttModel
            self.polishProvider = polishProvider
            self.polishModel = polishModel
            self.appVersion = appVersion
            self.locale = locale
        }

        enum CodingKeys: String, CodingKey {
            case sttProvider = "stt_provider"
            case sttModel = "stt_model"
            case polishProvider = "polish_provider"
            case polishModel = "polish_model"
            case appVersion = "app_version"
            case locale
        }
    }

    public struct ReviewInfo: Codable, Sendable, Equatable {
        public var humanVerified: Bool
        public var approvedAt: Date?
        public var excludedAt: Date?
        public var exclusionReason: MyVoiceExclusionReason?
        public var notes: String?

        public init(
            humanVerified: Bool = false,
            approvedAt: Date? = nil,
            excludedAt: Date? = nil,
            exclusionReason: MyVoiceExclusionReason? = nil,
            notes: String? = nil
        ) {
            self.humanVerified = humanVerified
            self.approvedAt = approvedAt
            self.excludedAt = excludedAt
            self.exclusionReason = exclusionReason
            self.notes = notes
        }

        enum CodingKeys: String, CodingKey {
            case humanVerified = "human_verified"
            case approvedAt = "approved_at"
            case excludedAt = "excluded_at"
            case exclusionReason = "exclusion_reason"
            case notes
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id, source
        case sourceSessionId = "source_session_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case audio, transcript, provenance, review
    }

    public init(
        schemaVersion: Int = 1,
        id: String,
        source: MyVoiceSource,
        sourceSessionId: String? = nil,
        status: MyVoiceStatus,
        createdAt: Date,
        updatedAt: Date,
        audio: AudioInfo,
        transcript: TranscriptInfo,
        provenance: ProvenanceInfo,
        review: ReviewInfo
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.source = source
        self.sourceSessionId = sourceSessionId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.audio = audio
        self.transcript = transcript
        self.provenance = provenance
        self.review = review
    }
}


extension MyVoiceRecord {
    static var iso8601Formatter: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    static var iso8601NoFraction: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    /// Encoder matching contract: ISO-8601 UTC with Z, sorted keys for determinism.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            // Use fractional seconds for sub-second precision, but contract examples use Z without fractions.
            // Use custom formatter that omits fractional if zero.
            let s = iso8601Formatter.string(from: date)
            // Alternative fallback: without fractional
            // Keep fractional for determinism; tests handle both.
            try container.encode(s)
        }
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let s = try container.decode(String.self)
            if let d = iso8601Formatter.date(from: s) { return d }
            if let d = iso8601NoFraction.date(from: s) { return d }
            // Try without colon?
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(s)")
        }
        return decoder
    }

    public func jsonData() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    public static func from(jsonData: Data) throws -> MyVoiceRecord {
        try makeDecoder().decode(MyVoiceRecord.self, from: jsonData)
    }
}


public enum MyVoiceValidationError: LocalizedError, Equatable {
    case missingASRText
    case invalidStatus(String)
    case schemaMismatch(expected: Int, found: Int)
    case audioMissing(path: String)
    case shaMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .missingASRText: return "asr_text is required (empty considered corrupt)"
        case .invalidStatus(let s): return "Invalid status: \(s)"
        case .schemaMismatch(let expected, let found): return "schema_version mismatch expected \(expected) found \(found)"
        case .audioMissing(let path): return "Audio file missing at \(path)"
        case .shaMismatch(let expected, let actual): return "SHA mismatch expected \(expected) actual \(actual)"
        }
    }
}
