import Foundation
import Testing
@testable import Talkify

struct DictionaryLearningTests {
  @Test func simpleWordReplacementProducesCorrection() {
    let entries = DictionaryLearning.learnableEntries(
      rawText: "please open cloud code",
      editedText: "please open Claude Code"
    )
    #expect(entries.count == 1)
    #expect(entries.first?.kind == .correction)
    #expect(entries.first?.hear == "cloud code")
    #expect(entries.first?.write == "Claude Code")
  }

  @Test func whitespaceOnlyDoesNotLearn() {
    let entries = DictionaryLearning.learnableEntries(
      rawText: "hello world",
      editedText: "hello  world"
    )
    #expect(entries.isEmpty)
  }

  @Test func punctuationOnlyDoesNotLearn() {
    let entries = DictionaryLearning.learnableEntries(
      rawText: "hello world",
      editedText: "hello, world!"
    )
    #expect(entries.isEmpty)
  }

  @Test func wholeSentenceRewriteDoesNotLearn() {
    let raw = "The quick brown fox jumps over the lazy dog"
    let edited = "Everything is completely different now in this sentence"
    let entries = DictionaryLearning.learnableEntries(rawText: raw, editedText: edited)
    #expect(entries.isEmpty)
  }

  @Test func insertionProducesTerm() {
    let entries = DictionaryLearning.learnableEntries(
      rawText: "hello world",
      editedText: "hello wonderful world"
    )
    let terms = entries.filter { $0.kind == .term }
    #expect(!terms.isEmpty)
    #expect(terms.contains { $0.write == "wonderful" })
  }

  @Test func deduplicationSkipsExisting() {
    let existing = [DictionaryEntry.correction(hear: "cloud code", write: "Claude Code")]
    let entries = DictionaryLearning.learnableEntries(
      rawText: "cloud code",
      editedText: "Claude Code",
      existing: existing
    )
    #expect(entries.isEmpty)
  }

  @Test func doesNotLearnFromAutoCorrectionOnly() {
    let raw = "cloud code"
    let corrected = "Claude Code"
    let edited = "Claude Code"
    let entries = DictionaryLearning.learnableEntries(
      rawText: raw,
      correctedText: corrected,
      editedText: edited
    )
    #expect(entries.isEmpty)
  }

  @Test func learnsWhenUserActuallyChangesBeyondCorrection() {
    let raw = "cloud code"
    let corrected = "Claude Code"
    let edited = "Claude Code Studio"
    let entries = DictionaryLearning.learnableEntries(
      rawText: raw,
      correctedText: corrected,
      editedText: edited
    )
    #expect(!entries.isEmpty)
  }

  @Test func noLearnOnEmpty() {
    #expect(DictionaryLearning.learnableEntries(rawText: "", editedText: "hello").isEmpty)
    #expect(DictionaryLearning.learnableEntries(rawText: "hello", editedText: "").isEmpty)
    #expect(DictionaryLearning.learnableEntries(rawText: "hello", editedText: "hello").isEmpty)
  }

  @Test func caseChangeIsNotNoiseButIsIgnoredIfOnlyCase() {
    let entries = DictionaryLearning.learnableEntries(rawText: "Hello World", editedText: "hello world")
    #expect(entries.isEmpty)
  }
}
