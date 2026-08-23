import Foundation
import Testing
@testable import Talkify

@MainActor
struct DictionaryTests {
  private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "DictionaryTests-\(UUID().uuidString).txt")
  }

  @Test func parseTermAndCorrection() {
    let text = """
      Anthropic
      cloud code -> Claude Code
      # off: whisper flow -> Wispr Flow
      # a comment

      Vercel
      """
    let entries = DictionaryStore.parse(text)
    #expect(entries.count == 4)
    #expect(entries[0].kind == .term && entries[0].write == "Anthropic" && entries[0].isEnabled)
    #expect(entries[1].kind == .correction && entries[1].hear == "cloud code" && entries[1].write == "Claude Code" && entries[1].isEnabled)
    #expect(entries[2].kind == .correction && entries[2].hear == "whisper flow" && entries[2].write == "Wispr Flow" && !entries[2].isEnabled)
    #expect(entries[3].kind == .term && entries[3].write == "Vercel")
  }

  @Test func fileLineRoundTrips() {
    let term = DictionaryEntry.term("Anthropic")
    #expect(term.fileLine == "Anthropic")
    let correction = DictionaryEntry.correction(hear: "cloud code", write: "Claude Code")
    #expect(correction.fileLine == "cloud code -> Claude Code")
    var disabled = DictionaryEntry.term("Old")
    disabled.isEnabled = false
    #expect(disabled.fileLine == "# off: Old")
    var disabledCorr = DictionaryEntry.correction(hear: "a", write: "b")
    disabledCorr.isEnabled = false
    #expect(disabledCorr.fileLine == "# off: a -> b")
  }

  @Test func persistenceIsHumanEditableText() async {
    let url = tempURL()
    let store = DictionaryStore(fileURL: url, watchFile: false)
    store.add(.term("Anthropic"))
    store.add(.correction(hear: "cloud code", write: "Claude Code"))
    var disabled = DictionaryEntry.term("OldTerm")
    disabled.isEnabled = false
    store.add(disabled)
    let text = try? String(contentsOf: url, encoding: .utf8)
    #expect(text != nil)
    #expect(text?.contains("Anthropic") == true)
    #expect(text?.contains("cloud code -> Claude Code") == true)
    #expect(text?.contains("# off: OldTerm") == true)
    let reloaded = DictionaryStore(fileURL: url, watchFile: false)
    #expect(reloaded.entries.count == 3)
  }

  @Test func correctorAppliesLongestFirst() {
    let entries = [
      DictionaryEntry.correction(hear: "cloud", write: "Claude"),
      DictionaryEntry.correction(hear: "cloud code", write: "Claude Code"),
    ]
    let corrector = DictionaryCorrector(entries: entries)
    let (text, applied) = corrector.apply(to: "cloud code")
    #expect(text == "Claude Code")
    #expect(applied.count == 1)
    #expect(applied.first?.to == "Claude Code")
  }

  @Test func correctorRespectsWholeBoundaries() {
    let entries = [DictionaryEntry.correction(hear: "cloud code", write: "Claude Code")]
    let corrector = DictionaryCorrector(entries: entries)
    let (a, _) = corrector.apply(to: "CloudCode is great")
    #expect(a == "Claude Code is great")
    let (b, _) = corrector.apply(to: "Cloudflare is not a match")
    #expect(b == "Cloudflare is not a match")
    let (c, _) = corrector.apply(to: "cloud-code also")
    #expect(c == "Claude Code also")
  }

  @Test func correctorIsCaseInsensitiveAndGlued() {
    let entries = [DictionaryEntry.correction(hear: "clawed code", write: "Claude Code")]
    let corrector = DictionaryCorrector(entries: entries)
    let (text, _) = corrector.apply(to: "The ClawedCode project")
    #expect(text == "The Claude Code project")
  }

  @Test func correctorDisabledEntriesAreIgnored() {
    var disabled = DictionaryEntry.correction(hear: "cloud code", write: "Claude Code")
    disabled.isEnabled = false
    let corrector = DictionaryCorrector(entries: [disabled])
    let (text, applied) = corrector.apply(to: "cloud code")
    #expect(text == "cloud code")
    #expect(applied.isEmpty)
  }

  @Test func biasPhrasesAreBoundedAndDeduped() {
    var entries: [DictionaryEntry] = []
    for i in 0..<50 {
      entries.append(.term("Word\(i)"))
    }
    entries.append(.term("word0"))
    let phrases = DictionaryCorrector.biasPhrases(from: entries)
    #expect(phrases.count == DictionaryCorrector.biasLimit)
    #expect(phrases.first == "Word0")
    let seenLower = Set(phrases.map { $0.lowercased() })
    #expect(seenLower.count == phrases.count)
  }

  @Test func biasIncludesCorrectionWriteNotHear() {
    let entries = [DictionaryEntry.correction(hear: "cloud code", write: "Claude Code")]
    let phrases = DictionaryCorrector.biasPhrases(from: entries)
    #expect(phrases.contains("Claude Code"))
    #expect(!phrases.contains("cloud code"))
  }

  @Test func filteringIsCaseInsensitive() async {
    let url = tempURL()
    let store = DictionaryStore(fileURL: url, watchFile: false)
    store.add(.term("Anthropic"))
    store.add(.correction(hear: "cloud code", write: "Claude Code"))
    #expect(store.filtered(by: "anth").count == 1)
    #expect(store.filtered(by: "CLAUDE").count == 1)
    #expect(store.filtered(by: "cloud").count == 1)
    #expect(store.filtered(by: "").count == 2)
  }

  @Test func warningForCommonWord() {
    let entry = DictionaryEntry.correction(hear: "the", write: "Thee")
    let warnings = DictionaryWarning.check(entry)
    #expect(!warnings.isEmpty)
    let term = DictionaryEntry.term("the")
    #expect(DictionaryWarning.check(term).isEmpty)
  }
}
