import Foundation
import os

/// Applies the selected shaping prompt to finished dictation text, between
/// recognition and insertion.
///
/// Passthrough is the rule: any unavailability, failure, refusal, empty
/// answer, or timeout returns the user's words untouched. Shaping may
/// improve a session; it must never lose one.
struct PromptShapingService: Sendable {
  /// The on-device model boundary, injectable so the shaping rules can be
  /// tested without Apple Intelligence.
  struct Client: Sendable {
    /// Nil while the model can answer; otherwise one sentence saying why not,
    /// which Settings shows beside the beta toggle.
    let unavailabilityReason: @Sendable () -> String?
    let respond: @Sendable (
      _ instructions: String, _ prompt: String
    ) async throws -> String
  }

  /// Longer than any healthy short rewrite. The framework offers no request
  /// timeout of its own, and a hung rewrite must not hold the user's words.
  static let defaultTimeout = Duration.seconds(10)

  let client: Client
  var timeout = Self.defaultTimeout

  func shape(_ text: String, with prompt: ShapingPrompt) async -> String {
    guard client.unavailabilityReason() == nil else { return text }

    let respond = client.respond
    let instructions = prompt.instructions
    let request = prompt.request(wrapping: text)
    let timeout = timeout
    let shaped: String? = await withCheckedContinuation { continuation in
      // First answer wins; the loser's resume is dropped. An abandoned model
      // request may keep running, which is the cost of returning on time.
      let done = OSAllocatedUnfairLock(initialState: false)
      let finish: @Sendable (String?) -> Void = { result in
        let isFirst = done.withLock { flag in
          guard !flag else { return false }
          flag = true
          return true
        }
        if isFirst { continuation.resume(returning: result) }
      }
      let work = Task { finish(try? await respond(instructions, request)) }
      Task {
        try? await Task.sleep(for: timeout)
        work.cancel()
        finish(nil)
      }
    }

    guard let shaped else { return text }
    let trimmed = shaped.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? text : trimmed
  }
}
