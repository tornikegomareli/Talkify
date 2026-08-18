import Foundation
import Testing
import os
@testable import Talkify

/// Pins the shaping rules: passthrough on any failure, trimming on success,
/// and the timeout that keeps a hung rewrite from holding the user's words.
struct PromptShapingServiceTests {
  private static let prompt = ShapingPrompt.library[0]

  /// A client whose model is available and answers with `result`.
  private func availableClient(
    _ respond: @escaping @Sendable (String, String) async throws -> String
  ) -> PromptShapingService.Client {
    PromptShapingService.Client(unavailabilityReason: { nil }, respond: respond)
  }

  @Test func successReturnsShapedTextAndPassesPromptAndInput() async {
    let received = OSAllocatedUnfairLock<(instructions: String, text: String)?>(
      initialState: nil
    )
    let service = PromptShapingService(
      client: availableClient { instructions, text in
        received.withLock { $0 = (instructions, text) }
        return "shaped"
      }
    )

    let result = await service.shape("raw words", with: Self.prompt)

    #expect(result == "shaped")
    let call = received.withLock { $0 }
    #expect(call?.instructions == Self.prompt.instructions)
    #expect(call?.text == "raw words")
  }

  @Test func unavailableClientPassesThroughWithoutCallingRespond() async {
    let responded = OSAllocatedUnfairLock(initialState: false)
    let client = PromptShapingService.Client(
      unavailabilityReason: { "Model is downloading." },
      respond: { _, _ in
        responded.withLock { $0 = true }
        return "shaped"
      }
    )
    let service = PromptShapingService(client: client)

    let result = await service.shape("raw words", with: Self.prompt)

    #expect(result == "raw words")
    #expect(responded.withLock { $0 } == false)
  }

  @Test func throwingRespondPassesThrough() async {
    struct ModelRefused: Error {}
    let service = PromptShapingService(
      client: availableClient { _, _ in throw ModelRefused() }
    )

    let result = await service.shape("raw words", with: Self.prompt)

    #expect(result == "raw words")
  }

  @Test(arguments: ["", "   \n\t  "])
  func emptyOrWhitespaceAnswerPassesThroughOriginal(answer: String) async {
    let service = PromptShapingService(
      client: availableClient { _, _ in answer }
    )

    let result = await service.shape("raw words", with: Self.prompt)

    #expect(result == "raw words")
  }

  @Test func shapedOutputIsTrimmed() async {
    let service = PromptShapingService(
      client: availableClient { _, _ in "  shaped  \n" }
    )

    let result = await service.shape("raw words", with: Self.prompt)

    #expect(result == "shaped")
  }

  @Test func timeoutPassesThroughPromptly() async {
    let service = PromptShapingService(
      client: availableClient { _, _ in
        try await Task.sleep(for: .seconds(5))
        return "too late"
      },
      timeout: .milliseconds(50)
    )

    let clock = ContinuousClock()
    let start = clock.now
    let result = await service.shape("raw words", with: Self.prompt)
    let elapsed = clock.now - start

    #expect(result == "raw words")
    #expect(elapsed < .seconds(2))
  }

  @Test func timedOutRespondTaskIsCancelled() async throws {
    let cancelled = OSAllocatedUnfairLock(initialState: false)
    let service = PromptShapingService(
      client: availableClient { _, _ in
        do {
          try await Task.sleep(for: .seconds(5))
        } catch {
          cancelled.withLock { $0 = true }
          throw error
        }
        return "too late"
      },
      timeout: .milliseconds(50)
    )

    let result = await service.shape("raw words", with: Self.prompt)
    #expect(result == "raw words")

    // The timeout path cancels the work task; the sleep's cancellation error
    // lands moments after shape returns, so poll briefly for the flag.
    for _ in 0..<100 {
      if cancelled.withLock({ $0 }) { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(cancelled.withLock { $0 })
  }

  @Test func libraryLookupFindsEachPromptById() {
    for prompt in ShapingPrompt.library {
      #expect(ShapingPrompt.prompt(for: prompt.id) == prompt)
    }
    #expect(ShapingPrompt.prompt(for: "no-such-prompt") == nil)
  }

  @Test func libraryIdsAreUnique() {
    let ids = ShapingPrompt.library.map(\.id)
    #expect(Set(ids).count == ids.count)
  }
}
