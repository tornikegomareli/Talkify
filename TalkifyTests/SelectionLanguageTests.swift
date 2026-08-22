import Foundation
import Testing
@testable import Talkify

/// What Read Aloud is allowed to guess. Dictation guesses nothing, because
/// Apple Speech offers no identification for audio. Text identification does
/// exist, so these are the rules for using it.
struct SelectionLanguageTests {
  @Test func realSentencesAreIdentified() {
    let cases = [
      "こんにちは、レビューありがとうございます。修正をプッシュしました。": "ja",
      "Vielen Dank für die Überprüfung, ich habe die Korrektur gepusht.": "de",
      "Merci beaucoup pour la relecture, j'ai poussé le correctif.": "fr",
      "Gracias por la revisión, he subido la corrección.": "es",
    ]
    for (text, expected) in cases {
      let detected = SelectionLanguage.detect(in: text)
      #expect(detected?.languageCode?.identifier == expected, "for \(text.prefix(20))")
    }
  }

  /// Two words are not evidence. Guessing here would translate a selection on
  /// a coin flip, and reading it as written is never wrong.
  @Test func tooShortToBeSureIsNoAnswer() {
    #expect(SelectionLanguage.detect(in: "ok") == nil)
    #expect(SelectionLanguage.detect(in: "") == nil)
    #expect(SelectionLanguage.detect(in: "   \n ") == nil)
  }

  /// A British voice reading American text is not a translation.
  @Test func regionsOfOneLanguageAreNotTranslated() {
    let american = Locale.Language(identifier: "en-US")
    let british = Locale.Language(identifier: "en-GB")
    #expect(!SelectionLanguage.needsTranslation(from: american, to: british))
  }

  @Test func differentLanguagesAreTranslated() {
    let japanese = Locale.Language(identifier: "ja")
    let english = Locale.Language(identifier: "en-US")
    #expect(SelectionLanguage.needsTranslation(from: japanese, to: english))
  }
}
