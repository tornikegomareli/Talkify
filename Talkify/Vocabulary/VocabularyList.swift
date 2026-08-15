import Foundation
import Observation

/// The Vocabulary as the app holds it: an observable list over the store, in
/// the shape `UsageTracker` already established — the view mutates through it,
/// the composition root observes it, and the actor behind it owns the file.
@MainActor
@Observable
final class VocabularyList {
  private let store: VocabularyStore

  private(set) var terms: [VocabularyTerm] = []
  private(set) var errorMessage: String?
  /// Why the last add was refused, cleared as soon as the user types again.
  /// The section shows it inline; a text field that silently discards what you
  /// typed reads as broken.
  private(set) var rejection: VocabularyRejection?

  init(store: VocabularyStore = VocabularyStore()) {
    self.store = store
  }

  /// What the analyzer is biased toward. Recomputed from the list rather than
  /// stored, so it can never drift from what the section shows.
  var contextualStrings: [String] {
    Vocabulary.contextualStrings(for: terms)
  }

  var isFull: Bool {
    terms.count >= Vocabulary.maximumTermCount
  }

  func load() async {
    do {
      terms = try await store.load().terms
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @discardableResult
  func add(_ raw: String) async -> Bool {
    switch Vocabulary.adding(raw, to: terms) {
    case let .added(updated):
      rejection = nil
      await write(updated)
      return errorMessage == nil
    case let .rejected(reason):
      rejection = reason
      return false
    }
  }

  func remove(_ term: VocabularyTerm) async {
    rejection = nil
    await write(Vocabulary.removing(term, from: terms))
  }

  func clearRejection() {
    rejection = nil
  }

  /// Persists first and adopts second. A term that only ever reached memory
  /// would disappear at the next launch while the section showed it as saved.
  private func write(_ updated: [VocabularyTerm]) async {
    do {
      terms = try await store.replace(terms: updated).terms
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
