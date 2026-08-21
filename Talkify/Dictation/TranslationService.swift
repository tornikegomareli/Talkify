import Foundation

/// The policy half of Dictate and Translate: when a pair may be used, how long
/// a translation is allowed to take, and what an empty draft means.
///
/// It holds no framework type. Everything Apple's translator does arrives
/// through `Client`, which is the same shape `TextInsertionService.Dependencies`
/// uses for the pasteboard, and for the same reason: every rule below is then
/// testable without a translator, and the rules are the part that can be wrong.
struct TranslationService: Sendable {
  struct Client: Sendable {
    var availability: @Sendable (TranslationPair) async -> TranslationAvailability
    /// Loads the pair's model, downloading it if this Mac does not have it.
    var prepare: @Sendable (TranslationPair) async throws -> Void
    var translate: @Sendable (TranslationPair, String) async throws -> String
    /// Drops every held session except this pair, cancelling what it drops.
    /// Every language this Mac can translate into, before availability is
    /// known for any particular pair.
    var candidateTargets: @Sendable () async -> [Locale.Language]
    var retain: @Sendable (TranslationPair?) async -> Void
    var shutDown: @Sendable () async -> Void
  }

  /// Long enough that a long draft is not cut off by a stopwatch, short enough
  /// that a wedged translator cannot hold the user's words. Measured on this
  /// machine: 250–410ms warm, 590–1050ms cold, for a sentence.
  static let defaultTimeout = Duration.seconds(6)

  let client: Client
  var timeout = Self.defaultTimeout

  func availability(of pair: TranslationPair) async -> TranslationAvailability {
    await client.availability(pair)
  }

  /// Readies a pair, answering whether it can translate right now.
  ///
  /// Never throws. A translation model that still needs downloading must not
  /// fail the preparation that plain dictation depends on: the user may never
  /// press the translate key at all, and refusing to dictate because of it
  /// would be the wrong trade.
  func prewarm(_ pair: TranslationPair) async -> Bool {
    guard await client.availability(pair) != .unsupported else { return false }
    do {
      try await client.prepare(pair)
      return true
    } catch {
      return false
    }
  }

  func translate(_ text: String, with pair: TranslationPair) async throws -> String {
    // Nothing to translate is not a failure, and Apple's translator reports it
    // as one. A session that heard only silence must not show an error.
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return text
    }
    guard await client.availability(pair) != .unsupported else {
      throw TranslationFailure.unsupported
    }
    return try await withTimeout(text, pair)
  }

  /// Every target worth offering for this source, named and sorted, with what
  /// this Mac can do about each. Unsupported pairs are dropped rather than
  /// listed and refused, and the source is never offered as its own target.
  func targets(from source: Locale) async -> [TranslationTarget] {
    guard let sourceCode = source.language.languageCode?.identifier else { return [] }
    var targets: [TranslationTarget] = []
    for language in await client.candidateTargets() {
      guard let code = language.languageCode?.identifier, code != sourceCode else { continue }
      let pair = TranslationPair(source: source.language, target: language)
      let availability = await client.availability(pair)
      guard availability != .unsupported else { continue }
      targets.append(
        TranslationTarget(
          id: code,
          name: SpeechLanguageCatalog.shortName(for: Locale(identifier: code)),
          availability: availability
        )
      )
    }
    // Installed first, because those work now, then alphabetically inside
    // each group so a list of sixteen is scannable.
    return targets.sorted {
      if ($0.availability == .installed) != ($1.availability == .installed) {
        return $0.availability == .installed
      }
      return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  func retain(_ pair: TranslationPair?) async {
    await client.retain(pair)
  }

  func shutDown() async {
    await client.shutDown()
  }

  /// Races the translation against the budget. The loser is cancelled, which
  /// matters: a translator left running holds a session that can never be
  /// reused, so the live client discards it on cancellation.
  private func withTimeout(_ text: String, _ pair: TranslationPair) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
      let client = client
      let timeout = timeout
      group.addTask { try await client.translate(pair, text) }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw TranslationFailure.timedOut
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else {
        throw TranslationFailure.timedOut
      }
      return first
    }
  }
}
