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
      respond: { instructions, text in
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text)
        return response.content
      }
    )
  }
}
