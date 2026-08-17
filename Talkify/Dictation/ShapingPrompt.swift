/// A named rewrite applied to finished dictation text while the alpha
/// prompt shaping setting is on. The ids are stored in UserDefaults, so
/// renaming one silently resets the pick.
struct ShapingPrompt: Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let instructions: String

  /// The built-in library. Alpha ships a fixed set; user-authored prompts
  /// are a decision for after the feel test.
  static let library: [ShapingPrompt] = [
    ShapingPrompt(
      id: "tighten-grammar",
      name: "Tighten grammar",
      instructions: "You clean up dictated text. Fix grammar, spelling, and "
        + "punctuation. Keep the wording, meaning, and tone. Return only the "
        + "corrected text with no commentary."
    ),
    ShapingPrompt(
      id: "bullet-lists",
      name: "Bullet my lists",
      instructions: "You clean up dictated text. Where the text enumerates "
        + "items, format them as a bulleted list, one item per line with a "
        + "leading dash. Leave everything else as spoken. Return only the "
        + "reformatted text with no commentary."
    ),
    ShapingPrompt(
      id: "remove-fillers",
      name: "Remove filler words",
      instructions: "You clean up dictated text. Remove filler words and "
        + "false starts such as um, uh, you know, and repeated words. Change "
        + "nothing else. Return only the cleaned text with no commentary."
    ),
  ]

  static func prompt(for id: String) -> ShapingPrompt? {
    library.first { $0.id == id }
  }
}
