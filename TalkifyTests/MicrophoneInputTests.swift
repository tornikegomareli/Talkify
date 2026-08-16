import AVFAudio
import Testing
@testable import Talkify

struct MicrophoneInputTests {
  @Test func rejectsMissingHardwareInput() throws {
    let format = try #require(AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: 0,
      channels: 0,
      interleaved: false
    ))

    #expect(!MicrophoneInput.hasUsableHardwareInput(format))
  }

  @Test func acceptsAvailableHardwareInput() throws {
    let format = try #require(AVAudioFormat(
      standardFormatWithSampleRate: 48_000,
      channels: 1
    ))

    #expect(MicrophoneInput.hasUsableHardwareInput(format))
  }
}
