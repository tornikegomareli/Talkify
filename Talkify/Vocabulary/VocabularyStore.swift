import Foundation

enum VocabularyStoreError: LocalizedError {
  case unsupportedVersion(Int)

  var errorDescription: String? {
    switch self {
    case let .unsupportedVersion(version):
      "Unsupported Vocabulary data version: \(version)"
    }
  }
}

/// The Vocabulary on disk, beside the Insights document and written the same
/// way: one versioned JSON file in Application Support, replaced atomically.
///
/// It holds only what the user typed. Nothing recognized, inserted, or heard
/// reaches this file (CONTEXT.md: Talkify persists no recognized text).
actor VocabularyStore {
  static var defaultFileURL: URL {
    FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    .appending(path: "Talkify", directoryHint: .isDirectory)
    .appending(path: "vocabulary.json")
  }

  private let fileURL: URL
  private var cachedDocument: VocabularyDocument?

  init(fileURL: URL = VocabularyStore.defaultFileURL) {
    self.fileURL = fileURL
  }

  func load() throws -> VocabularyDocument {
    if let cachedDocument {
      return cachedDocument
    }

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      let document = VocabularyDocument()
      cachedDocument = document
      return document
    }

    let data = try Data(contentsOf: fileURL)
    let document = try JSONDecoder().decode(VocabularyDocument.self, from: data)
    guard document.version == VocabularyDocument.currentVersion else {
      throw VocabularyStoreError.unsupportedVersion(document.version)
    }
    cachedDocument = document
    return document
  }

  @discardableResult
  func replace(terms: [VocabularyTerm]) throws -> VocabularyDocument {
    var document = try load()
    document.terms = terms
    try save(document)
    cachedDocument = document
    return document
  }

  private func save(_ document: VocabularyDocument) throws {
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
