import Accelerate
import AVFAudio
import Speech

final class MicrophoneInput: @unchecked Sendable {
  enum InputError: LocalizedError, Sendable {
    case unavailable
    case converterCreationFailed
    case conversionFailed(String)
    case analyzerBackpressure

    var errorDescription: String? {
      switch self {
      case .unavailable:
        "No microphone input is available."
      case .converterCreationFailed:
        "The microphone audio format is unsupported."
      case let .conversionFailed(message):
        "Microphone conversion failed: \(message)"
      case .analyzerBackpressure:
        "Speech analysis could not keep up with microphone input."
      }
    }
  }

  private final class ConverterBox: @unchecked Sendable {
    let converter: AVAudioConverter
    let outputFormat: AVAudioFormat

    init(converter: AVAudioConverter, outputFormat: AVAudioFormat) {
      self.converter = converter
      self.outputFormat = outputFormat
    }
  }

  private final class InputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var supplied = false

    init(buffer: AVAudioPCMBuffer) {
      self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
      lock.withLock {
        guard !supplied else {
          status.pointee = .noDataNow
          return nil
        }

        supplied = true
        status.pointee = .haveData
        return buffer
      }
    }
  }

  private let audioEngine = AVAudioEngine()
  private let analyzerContinuation: AsyncStream<AnalyzerInput>.Continuation
  private let failureHandler: @Sendable (InputError) -> Void
  /// Normalized microphone level (0–1) per tap buffer, for the HUD's
  /// voice-reactive visual. Called on the audio thread.
  private let levelHandler: (@Sendable (Float) -> Void)?
  private let stateLock = NSLock()

  private var running = false
  private var reportedFailure = false

  init(
    analyzerContinuation: AsyncStream<AnalyzerInput>.Continuation,
    failureHandler: @escaping @Sendable (InputError) -> Void,
    levelHandler: (@Sendable (Float) -> Void)? = nil
  ) {
    self.analyzerContinuation = analyzerContinuation
    self.failureHandler = failureHandler
    self.levelHandler = levelHandler
  }

  func start(outputFormat: AVAudioFormat) throws {
    let inputNode = audioEngine.inputNode
    let hardwareFormat = inputNode.inputFormat(forBus: 0)
    guard Self.hasUsableHardwareInput(hardwareFormat) else {
      throw InputError.unavailable
    }

    let inputFormat = inputNode.outputFormat(forBus: 0)
    guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
      throw InputError.unavailable
    }

    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw InputError.converterCreationFailed
    }

    let converterBox = ConverterBox(converter: converter, outputFormat: outputFormat)
    inputNode.installTap(
      onBus: 0,
      bufferSize: 1_024,
      format: inputFormat
    ) { [weak self] buffer, _ in
      self?.receive(buffer, converterBox: converterBox)
    }

    audioEngine.prepare()
    do {
      try audioEngine.start()
      stateLock.withLock {
        running = true
      }
    } catch {
      inputNode.removeTap(onBus: 0)
      throw error
    }
  }

  static func hasUsableHardwareInput(_ format: AVAudioFormat) -> Bool {
    format.channelCount > 0 && format.sampleRate > 0
  }

  func stop() {
    let shouldStop = stateLock.withLock { () -> Bool in
      guard running else { return false }
      running = false
      return true
    }

    guard shouldStop else { return }
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
  }

  private func receive(_ buffer: AVAudioPCMBuffer, converterBox: ConverterBox) {
    publishLevel(of: buffer)
    do {
      let convertedBuffer = try convert(buffer, using: converterBox)
      let result = analyzerContinuation.yield(AnalyzerInput(buffer: convertedBuffer))

      if case .dropped = result {
        reportFailure(.analyzerBackpressure)
      }
    } catch let error as InputError {
      reportFailure(error)
    } catch {
      reportFailure(.conversionFailed(error.localizedDescription))
    }
  }

  private func convert(
    _ inputBuffer: AVAudioPCMBuffer,
    using converterBox: ConverterBox
  ) throws -> AVAudioPCMBuffer {
    let ratio = converterBox.outputFormat.sampleRate / inputBuffer.format.sampleRate
    let capacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 1

    guard let outputBuffer = AVAudioPCMBuffer(
      pcmFormat: converterBox.outputFormat,
      frameCapacity: capacity
    ) else {
      throw InputError.conversionFailed("Unable to allocate an audio buffer.")
    }

    let inputProvider = InputProvider(buffer: inputBuffer)
    var conversionError: NSError?
    let status = converterBox.converter.convert(
      to: outputBuffer,
      error: &conversionError
    ) { _, inputStatus in
      inputProvider.next(status: inputStatus)
    }

    if let conversionError {
      throw InputError.conversionFailed(conversionError.localizedDescription)
    }

    guard status == .haveData || status == .inputRanDry else {
      throw InputError.conversionFailed("Unexpected converter status \(status.rawValue).")
    }

    return outputBuffer
  }

  /// RMS of the first channel (vDSP, so the audio thread barely notices)
  /// mapped to 0–1 over a 50 dB window: a quiet room sits near zero and
  /// speech fills most of the range.
  private func publishLevel(of buffer: AVAudioPCMBuffer) {
    guard let levelHandler,
       let samples = buffer.floatChannelData?[0],
       buffer.frameLength > 0
    else { return }

    let rms = vDSP.rootMeanSquare(
      UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength))
    )
    let db = 20 * log10(max(rms, .leastNormalMagnitude))
    levelHandler(min(1, max(0, (db + 50) / 50)))
  }

  private func reportFailure(_ error: InputError) {
    let shouldReport = stateLock.withLock { () -> Bool in
      guard !reportedFailure else { return false }
      reportedFailure = true
      return true
    }

    guard shouldReport else { return }
    analyzerContinuation.finish()
    failureHandler(error)
  }
}
