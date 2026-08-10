import Testing
@testable import Talkify

struct SpeechResultAccumulatorTests {
  @Test func keepsLastVolatileResultWhenFinalizationEndsTheStream() {
    var accumulator = SpeechRecognitionService.ResultAccumulator()

    _ = accumulator.receive("Hello world", isFinal: false)

    #expect(accumulator.completedText == "Hello world")
  }

  @Test func replacesVolatileTextWhenAResultBecomesFinal() {
    var accumulator = SpeechRecognitionService.ResultAccumulator()

    _ = accumulator.receive("Hello", isFinal: false)
    _ = accumulator.receive("Hello", isFinal: true)
    _ = accumulator.receive(" world", isFinal: false)

    #expect(accumulator.completedText == "Hello world")
  }
}
