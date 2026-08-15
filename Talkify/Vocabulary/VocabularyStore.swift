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

/// The result of a mutation: the stored list and the revision it produced.
///
/// The revision is in-memory only and never reaches the file. It exists so a
/// caller that resumes out of order can tell a stale answer from a current
/// one, rather than assigning an older list over a newer one.
struct VocabularyRevision: Equatable, Sendable {
  let terms: [VocabularyTerm]
  let revision: Int
}

enum VocabularyAddResult: Equatable, Sendable {
  case added(VocabularyRevision)
  case rejected(VocabularyRejection)
}

/// The Vocabulary on disk, beside the Insights document and written the same
/// way: one versioned JSON file in Application Support, replaced atomically.
///
/// Every mutation happens here rather than in the caller. Reading the list,
/// applying a rule to it, and writing it back is one transaction with no
/// suspension inside it, so two edits in flight at once cannot each derive a
/// new list from the same stale snapshot and overwrite one another.
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
  private var revision = 0

  init(fileURL: URL = VocabularyStore.defaultFileURL) {
    self.fileURL = fileURL
  }

  func load() throws -> VocabularyRevision {
    VocabularyRevision(terms: try document().terms, revision: revision)
  }

  func add(_ raw: String) throws -> VocabularyAddResult {
    var document = try document()

    switch Vocabulary.adding(raw, to: document.terms) {
    case let .added(terms):
      document.terms = terms
      return .added(try commit(document))
    case let .rejected(reason):
      return .rejected(reason)
    }
  }

  func remove(_ term: VocabularyTerm) throws -> VocabularyRevision {
    var document = try document()
    document.terms = Vocabulary.removing(term, from: document.terms)
    return try commit(document)
  }

  @discardableResult
  func replace(terms: [VocabularyTerm]) throws -> VocabularyRevision {
    var document = try document()
    document.terms = Vocabulary.canonical(terms)
    return try commit(document)
  }

  /// The stored document, canonicalized on the way in. An older build or a
  /// hand-edited file can hold entries this build's rules reject, and they must
  /// not reach the list the section renders (`Vocabulary.canonical`).
  private func document() throws -> VocabularyDocument {
    if let cachedDocument {
      return cachedDocument
    }

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      let document = VocabularyDocument()
      cachedDocument = document
      return document
    }

    let data = try Data(contentsOf: fileURL)
    var document = try JSONDecoder().decode(VocabularyDocument.self, from: data)
    guard document.version == VocabularyDocument.currentVersion else {
      throw VocabularyStoreError.unsupportedVersion(document.version)
    }
    document.terms = Vocabulary.canonical(document.terms)
    cachedDocument = document
    return document
  }

  private func commit(_ document: VocabularyDocument) throws -> VocabularyRevision {
    try save(document)
    cachedDocument = document
    revision += 1
    return VocabularyRevision(terms: document.terms, revision: revision)
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
