import Foundation
import Testing
import os
@testable import Talkify

/// Pins the shaping rules: passthrough on any failure, trimming on success,
/// and the timeout that keeps a hung rewrite from holding the user's words.
struct PromptShapingServiceTests {
  private static let prompt = ShapingPrompt.defaults[0]

  /// A prompt with every editable field filled, so tests can pin where each
  /// one lands — and where it must never land.
  private static let fullPrompt = ShapingPrompt(
    id: "full",
    name: "Full",
    preInstruction: "Fix the grammar.",
    postInstruction: "Keep the tone.",
    exampleInput: "what time does the the meeting start",
    exampleOutput: "What time does the meeting start?"
  )

  /// A client whose model is available and answers with `result`.
  private func availableClient(
    _ respond: @escaping @Sendable (String, String) async throws -> String
  ) -> PromptShapingService.Client {
    PromptShapingService.Client(unavailabilityReason: { nil }, respond: respond)
  }

  @Test func successReturnsShapedTextAndPassesPromptAndInput() async {
    let received = OSAllocatedUnfairLock<(instructions: String, prompt: String)?>(
      initialState: nil
    )
    let service = PromptShapingService(
      client: availableClient { instructions, prompt in
        received.withLock { $0 = (instructions, prompt) }
        return "shaped"
      }
    )

    let result = await service.shape("raw words", with: Self.prompt)

    #expect(result == "shaped")
    let call = received.withLock { $0 }
    #expect(call?.instructions == Self.prompt.instructions)
    #expect(call?.prompt == Self.prompt.request(wrapping: "raw words"))
  }

  /// The framing that keeps the model rewriting: the transcript reaches it
  /// as marked data, verbatim, never as the conversational request itself.
  @Test func requestWrapsTheTranscriptVerbatimBetweenMarkers() {
    let transcript = "what time does the meeting start tomorrow"
    for prompt in ShapingPrompt.defaults {
      let request = prompt.request(wrapping: transcript)
      #expect(request.contains("<transcript>\(transcript)</transcript>"))
      #expect(request.contains("Rewrite the transcript"))
    }
  }

  /// The user turn reads in the order the editor's template shows: the
  /// prompt's own instruction, the marked transcript, the closing one.
  @Test func requestPlacesPreInstructionBeforeTheMarkersAndPostAfter() {
    let request = Self.fullPrompt.request(wrapping: "raw words")
    #expect(request == """
      Fix the grammar.
      Rewrite the transcript between the markers.
      <transcript>raw words</transcript>
      Keep the tone.
      """)
  }

  /// The instructions hold the invariant defence: the data framing and a
  /// question-shaped example that stays a question — the known mitigations
  /// for a model answering the words.
  @Test func instructionsFrameTheTranscriptAsDataWithAnExample() {
    for prompt in ShapingPrompt.defaults {
      let instructions = prompt.instructions
      #expect(instructions.contains("never a question for you to answer"))
      #expect(instructions.contains("<transcript>\(prompt.exampleInput)</transcript>"))
      #expect(instructions.contains(prompt.exampleOutput))
    }
  }

  /// The prompt's editable wording lives only in the user turn: if it could
  /// reach the instructions, editing it could weaken the framing.
  @Test func instructionsNeverCarryThePromptsEditableWording() {
    let instructions = Self.fullPrompt.instructions
    #expect(!instructions.contains(Self.fullPrompt.preInstruction))
    #expect(!instructions.contains(Self.fullPrompt.postInstruction))
    #expect(instructions.contains("never a question for you to answer"))
  }

  /// A half-filled example teaches nothing, so it is dropped whole.
  @Test(arguments: [("", ""), ("input only", ""), ("", "output only"), ("  \n", " ")])
  func incompleteExampleLeavesOnlyTheFraming(input: String, output: String) {
    var prompt = Self.fullPrompt
    prompt.exampleInput = input
    prompt.exampleOutput = output
    #expect(!prompt.instructions.contains("Example"))
    #expect(prompt.instructions.hasSuffix("return it unchanged."))
  }

  /// Empty editable fields collapse without leaving blank lines at either
  /// end of the user turn.
  @Test func emptyPreAndPostInstructionsCollapseCleanly() {
    let prompt = ShapingPrompt(
      id: "bare",
      name: "Bare",
      preInstruction: "  \n",
      postInstruction: "",
      exampleInput: "",
      exampleOutput: ""
    )
    #expect(prompt.request(wrapping: "raw words") == """
      Rewrite the transcript between the markers.
      <transcript>raw words</transcript>
      """)
  }

  /// A question-shaped transcript round-trips the pipeline untouched when
  /// the model echoes the marked data back: nothing between recognition
  /// and insertion depends on the words not looking like a question.
  @Test func questionShapedTranscriptRoundTripsThroughAnEchoingClient() async {
    let transcript = "what time does the meeting start tomorrow"
    let service = PromptShapingService(
      client: availableClient { _, prompt in
        // Echo exactly what sits between the markers, as a faithful
        // rewrite-nothing model would.
        let opened = prompt.components(separatedBy: "<transcript>")[1]
        return opened.components(separatedBy: "</transcript>")[0]
      }
    )

    let result = await service.shape(transcript, with: Self.prompt)

    #expect(result == transcript)
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

  @Test func lookupFindsEachSeedPromptById() {
    for prompt in ShapingPrompt.defaults {
      #expect(ShapingPrompt.defaults.prompt(for: prompt.id) == prompt)
    }
    #expect(ShapingPrompt.defaults.prompt(for: "no-such-prompt") == nil)
  }

  @Test func seedIdsAreUnique() {
    let ids = ShapingPrompt.defaults.map(\.id)
    #expect(Set(ids).count == ids.count)
  }
}
