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

  /// A Bluetooth headset switches to its 16 kHz hands-free profile the moment
  /// the microphone opens, so buffers after a route change arrive in a format
  /// the session did not start with. A converter kept from the old format
  /// would go on resampling from a rate nothing is sending.
  @Test func theConverterFollowsAChangeOfInputFormat() throws {
    let analyzerFormat = try #require(AVAudioFormat(
      standardFormatWithSampleRate: 16_000,
      channels: 1
    ))
    let a2dp = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    let handsFree = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))

    let box = MicrophoneInput.ConverterBox(outputFormat: analyzerFormat)
    let first = try box.converter(for: a2dp)
    #expect(first.inputFormat.sampleRate == 44_100)

    let afterSwitch = try box.converter(for: handsFree)
    #expect(afterSwitch.inputFormat.sampleRate == 16_000)
    #expect(afterSwitch !== first, "the converter must be rebuilt, not reused")
  }

  /// Rebuilding on every buffer would allocate a converter at the tap rate.
  @Test func theConverterIsKeptWhileTheFormatHolds() throws {
    let analyzerFormat = try #require(AVAudioFormat(
      standardFormatWithSampleRate: 16_000,
      channels: 1
    ))
    let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))

    let box = MicrophoneInput.ConverterBox(outputFormat: analyzerFormat)
    #expect(try box.converter(for: input) === (try box.converter(for: input)))
  }
}
