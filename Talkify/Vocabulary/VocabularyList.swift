import Foundation
import Observation

/// The Vocabulary as the app holds it: an observable list over the store, in
/// the shape `UsageTracker` already established — the view calls through it,
/// the composition root observes it, and the actor behind it owns both the
/// file and the rules.
///
/// This type decides nothing about the list's contents. It forwards the edit
/// and adopts what came back, so no rule is applied to a snapshot that another
/// edit has already moved past.
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

  /// The revision behind `terms`. Two edits in flight resume independently,
  /// and the store answers each with the list as of its own turn — so an
  /// answer older than what is already shown is dropped rather than assigned.
  @ObservationIgnored
  private var appliedRevision = -1

  init(store: VocabularyStore = VocabularyStore()) {
    self.store = store
  }

  /// What the analyzer is biased toward. Recomputed from the list rather than
  /// stored, so it can never drift from what the section shows.
  var contextualStrings: [String] {
    Vocabulary.contextualStrings(for: terms)
  }

  func load() async {
    do {
      apply(try await store.load())
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @discardableResult
  func add(_ raw: String) async -> Bool {
    do {
      switch try await store.add(raw) {
      case let .added(result):
        rejection = nil
        errorMessage = nil
        apply(result)
        return true
      case let .rejected(reason):
        rejection = reason
        return false
      }
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func remove(_ term: VocabularyTerm) async {
    rejection = nil
    do {
      apply(try await store.remove(term))
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func clearRejection() {
    rejection = nil
  }

  private func apply(_ result: VocabularyRevision) {
    guard result.revision >= appliedRevision else { return }
    appliedRevision = result.revision
    terms = result.terms
  }
}
