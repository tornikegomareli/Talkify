import Foundation
import Testing
@testable import Talkify

struct VocabularyStoreTests {
  @Test func returnsAnEmptyDocumentBeforeAnythingIsSaved() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    let document = try await VocabularyStore(fileURL: fileURL).load()
    #expect(document.terms.isEmpty)
    #expect(document.version == VocabularyDocument.currentVersion)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test func persistsTermsAcrossStoreInstances() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    let store = VocabularyStore(fileURL: fileURL)
    _ = try await store.replace(terms: [
      VocabularyTerm(text: "NotchIsland"),
      VocabularyTerm(text: "Core Data")
    ])

    let reloaded = try await VocabularyStore(fileURL: fileURL).load()
    #expect(reloaded.terms.map(\.text) == ["NotchIsland", "Core Data"])
  }

  @Test func replaceOverwritesRatherThanAppends() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    let store = VocabularyStore(fileURL: fileURL)
    _ = try await store.replace(terms: [VocabularyTerm(text: "Sparkle")])
    _ = try await store.replace(terms: [VocabularyTerm(text: "Talkify")])

    let reloaded = try await VocabularyStore(fileURL: fileURL).load()
    #expect(reloaded.terms.map(\.text) == ["Talkify"])
  }

  @Test func rejectsADocumentFromAFutureVersion() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let future = VocabularyDocument(
      version: VocabularyDocument.currentVersion + 1,
      terms: [VocabularyTerm(text: "Talkify")]
    )
    try JSONEncoder().encode(future).write(to: fileURL, options: .atomic)

    await #expect(throws: VocabularyStoreError.self) {
      _ = try await VocabularyStore(fileURL: fileURL).load()
    }
  }

  /// The file holds a list the user typed and nothing else — no recognized
  /// text, no target application (CONTEXT.md).
  @Test func storesOnlyTheTermsAndTheVersion() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    _ = try await VocabularyStore(fileURL: fileURL)
      .replace(terms: [VocabularyTerm(text: "Talkify")])

    let data = try Data(contentsOf: fileURL)
    let json = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(Set(json.keys) == ["version", "terms"])

    let terms = try #require(json["terms"] as? [[String: Any]])
    #expect(terms.allSatisfy { Set($0.keys) == ["text"] })
  }

  private func temporaryFileURL() -> (URL, () -> Void) {
    let directory = FileManager.default.temporaryDirectory
      .appending(
        path: "TalkifyVocabularyStoreTests-" + UUID().uuidString,
        directoryHint: .isDirectory
      )
    return (
      directory.appending(path: "vocabulary.json"),
      { try? FileManager.default.removeItem(at: directory) }
    )
  }
}
