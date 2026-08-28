import FoundationModels

/// The live boundary: Apple's on-device model through FoundationModels.
/// Nothing else in the app imports the framework, and every session is
/// fresh — a rewrite is single-turn, so no transcript should accumulate.
extension PromptShapingService.Client {
  static var live: Self {
    Self(
      unavailabilityReason: {
        switch SystemLanguageModel.default.availability {
        case .available:
          nil
        case .unavailable(.appleIntelligenceNotEnabled):
          "Turn on Apple Intelligence in System Settings to use prompt shaping"
        case .unavailable(.modelNotReady):
          "Apple Intelligence is still preparing its model"
        case .unavailable:
          "Apple Intelligence is not available on this Mac"
        }
      },
      respond: { instructions, prompt in
        // The framing lives in instructions and the transcript arrives inside
        // the prompt's markers: the model weighs instructions over prompt
        // content, which is what keeps a question-shaped transcript from
        // being answered instead of rewritten.
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content
      }
    )
  }
}
