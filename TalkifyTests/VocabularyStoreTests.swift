import Foundation
import Testing
@testable import Talkify

struct VocabularyStoreTests {
  @Test func returnsAnEmptyDocumentBeforeAnythingIsSaved() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    let result = try await VocabularyStore(fileURL: fileURL).load()
    #expect(result.terms.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }

  @Test func persistsTermsAcrossStoreInstances() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    let store = VocabularyStore(fileURL: fileURL)
    _ = try await store.add("NotchIsland")
    _ = try await store.add("Core Data")

    let reloaded = try await VocabularyStore(fileURL: fileURL).load()
    #expect(reloaded.terms.map(\.text) == ["Core Data", "NotchIsland"])
  }

  @Test func addAppliesTheVocabularyRulesAndReportsRefusals() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    let store = VocabularyStore(fileURL: fileURL)
    _ = try await store.add("Talkify")

    #expect(try await store.add("  talkify ") == .rejected(.duplicate))
    #expect(try await store.add("   ") == .rejected(.empty))

    let reloaded = try await VocabularyStore(fileURL: fileURL).load()
    #expect(reloaded.terms.map(\.text) == ["Talkify"])
  }

  @Test func removeMatchesOnTheFoldedTerm() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    let store = VocabularyStore(fileURL: fileURL)
    _ = try await store.add("Core Data")
    _ = try await store.add("Sparkle")

    let result = try await store.remove(VocabularyTerm(text: "core data"))
    #expect(result.terms.map(\.text) == ["Sparkle"])
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

  /// Every mutation is one transaction inside the actor. Deriving the new list
  /// in the caller and awaiting the write would let these overlap and
  /// overwrite one another.
  @Test func concurrentAddsAllSurvive() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    let store = VocabularyStore(fileURL: fileURL)
    let entries = (0..<20).map { "term-\($0)" }

    await withTaskGroup(of: Void.self) { group in
      for entry in entries {
        group.addTask { _ = try? await store.add(entry) }
      }
    }

    let reloaded = try await VocabularyStore(fileURL: fileURL).load()
    #expect(Set(reloaded.terms.map(\.text)) == Set(entries))
  }

  @Test func concurrentRemovalsAllSurvive() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    let store = VocabularyStore(fileURL: fileURL)
    let entries = (0..<20).map { "term-\($0)" }
    for entry in entries {
      _ = try await store.add(entry)
    }

    await withTaskGroup(of: Void.self) { group in
      for entry in entries.prefix(10) {
        group.addTask { _ = try? await store.remove(VocabularyTerm(text: entry)) }
      }
    }

    let reloaded = try await VocabularyStore(fileURL: fileURL).load()
    #expect(Set(reloaded.terms.map(\.text)) == Set(entries.dropFirst(10)))
  }

  @Test func everyMutationAdvancesTheRevision() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    let store = VocabularyStore(fileURL: fileURL)
    let loaded = try await store.load()

    guard case let .added(first) = try await store.add("Talkify") else {
      Issue.record("expected the term to be added")
      return
    }
    let second = try await store.remove(VocabularyTerm(text: "Talkify"))

    #expect(first.revision > loaded.revision)
    #expect(second.revision > first.revision)
  }

  /// A refused add changes nothing, so it must not look like a newer list to a
  /// caller comparing revisions.
  @Test func aRefusedAddLeavesTheRevisionAlone() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    let store = VocabularyStore(fileURL: fileURL)
    guard case let .added(added) = try await store.add("Talkify") else {
      Issue.record("expected the term to be added")
      return
    }
    #expect(try await store.add("talkify") == .rejected(.duplicate))
    #expect(try await store.load().revision == added.revision)
  }

  /// An older build or a hand-edited file can hold entries this build rejects.
  @Test func canonicalizesADocumentWrittenUnderDifferentRules() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    try write(
      VocabularyDocument(terms: [
        VocabularyTerm(text: "  Talkify  "),
        VocabularyTerm(text: "   "),
        VocabularyTerm(text: "TALKIFY"),
        VocabularyTerm(text: String(repeating: "c", count: Vocabulary.maximumTermLength + 1)),
        VocabularyTerm(text: "Core   Data")
      ]),
      to: fileURL
    )

    let loaded = try await VocabularyStore(fileURL: fileURL).load()
    #expect(loaded.terms.map(\.text) == ["Talkify", "Core Data"])
    #expect(Set(loaded.terms.map(\.id)).count == loaded.terms.count)
  }

  @Test func canonicalizesADocumentThatExceedsTheCap() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    let overflowing = (0..<(Vocabulary.maximumTermCount + 25)).map {
      VocabularyTerm(text: "term-\($0)")
    }
    try write(VocabularyDocument(terms: overflowing), to: fileURL)

    let loaded = try await VocabularyStore(fileURL: fileURL).load()
    #expect(loaded.terms.count == Vocabulary.maximumTermCount)
  }

  @Test func rejectsADocumentFromAFutureVersion() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    try write(
      VocabularyDocument(
        version: VocabularyDocument.currentVersion + 1,
        terms: [VocabularyTerm(text: "Talkify")]
      ),
      to: fileURL
    )

    await #expect(throws: VocabularyStoreError.self) {
      _ = try await VocabularyStore(fileURL: fileURL).load()
    }
  }

  /// The file holds a list the user typed and nothing else — no recognized
  /// text, no target application, and no revision (CONTEXT.md).
  @Test func storesOnlyTheTermsAndTheVersion() async throws {
    let (fileURL, cleanup) = temporaryFileURL()
    defer { cleanup() }

    _ = try await VocabularyStore(fileURL: fileURL).add("Talkify")

    let data = try Data(contentsOf: fileURL)
    let json = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    #expect(Set(json.keys) == ["version", "terms"])

    let terms = try #require(json["terms"] as? [[String: Any]])
    #expect(terms.allSatisfy { Set($0.keys) == ["text"] })
  }

  private func write(_ document: VocabularyDocument, to fileURL: URL) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try JSONEncoder().encode(document).write(to: fileURL, options: .atomic)
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
