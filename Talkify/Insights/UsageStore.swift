import Foundation

enum UsageStoreError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "Unsupported Insights data version: \(version)"
        }
    }
}

actor UsageStore {
    static var defaultFileURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appending(path: "Talkify", directoryHint: .isDirectory)
        .appending(path: "usage.json")
    }

    private let fileURL: URL
    private var cachedDocument: UsageDocument?

    init(fileURL: URL = UsageStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    func load() throws -> UsageDocument {
        if let cachedDocument {
            return cachedDocument
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let document = UsageDocument()
            cachedDocument = document
            return document
        }

        let data = try Data(contentsOf: fileURL)
        let document = try JSONDecoder().decode(UsageDocument.self, from: data)
        guard document.version == UsageDocument.currentVersion else {
            throw UsageStoreError.unsupportedVersion(document.version)
        }
        cachedDocument = document
        return document
    }

    @discardableResult
    func recordSession(
        wordCount: Int,
        speakingDuration: TimeInterval,
        at date: Date,
        calendar: Calendar
    ) throws -> UsageDocument {
        guard wordCount > 0 else { return try load() }

        var document = try load()
        let day = UsageDay(date: date, calendar: calendar)
        if let index = document.days.firstIndex(where: { $0.day == day }) {
            document.days[index].wordCount += wordCount
            document.days[index].speakingDuration += max(speakingDuration, 0)
            document.days[index].sessionCount += 1
        } else {
            document.days.append(DailyUsage(
                day: day,
                wordCount: wordCount,
                speakingDuration: max(speakingDuration, 0),
                sessionCount: 1
            ))
            document.days.sort { $0.day < $1.day }
        }

        try save(document)
        cachedDocument = document
        return document
    }

    private func save(_ document: UsageDocument) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }
}
