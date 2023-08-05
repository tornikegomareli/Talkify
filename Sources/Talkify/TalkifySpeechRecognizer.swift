///
///  TalkifySpeechRecognizer.swift
///
///
///  Created by Tornike on 19/03/2023.
///
///
/// `TalkifySpeechRecognizer` is a public class that offers APIs for managing speech recognition tasks.
/// This class is available on iOS 13.0 and macOS 10.15 or later.


import Foundation
import AVFoundation
import Speech

/// The `VoiceRecorderDelegate` protocol defines the methods a delegate of a `TalkifySpeechRecognizer` object should implement.
/// This protocol notifies your app’s objects when recording has started or stopped, or when errors occur.
public protocol VoiceRecorderDelegate: AnyObject {
  /// Tells the delegate that the voice recorder has finished recording and recognized the text.
  func voiceRecorderDidFinishRecordingWithText(_ text: String)
  /// Tells the delegate that the voice recorder has started recording.
  func voiceRecorderDidStartRecording()
  /// Tells the delegate that the voice recorder has stopped recording.
  func voiceRecorderDidStopRecording()
  /// Tells the delegate that the voice recorder has encountered an error.
  func voiceRecorderDidEncounterError(_ error: Error)
  /// Tells the delegate that the voice recorder has checked the microphone permission status.
  func voiceRecorderDidCheckMicrophonePermission(status: AudioPermissionStatus)
  /// Tells the delegate that the voice recorder has requested microphone permission.
  func voiceRecorderDidRequestMicrophonePermission(granted: Bool)
}

@available(iOS 13.0, *)
@available(macOS 10.15, *)
public class TalkifySpeechRecognizer {
  /// A delegate object that handles voice recording events.
  public weak var delegate: VoiceRecorderDelegate?

  /// An instance of `AVAudioEngine` for audio operations.
  public let audioEngine = AVAudioEngine()

  /// An instance of `SFSpeechRecognizer` for speech recognition.
  public let speechRecognizer: SFSpeechRecognizer

  /// A speech recognition request. This property is read-only.
  public private(set) var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

  /// A speech recognition task. This property is read-only.
  public private(set) var recognitionTask: SFSpeechRecognitionTask?

  private var microphonePermission: MicrophonePermission
  private var recordingSession: TalkifyRecordingSession

  /// Returns a new `TalkifySpeechRecognizer` object.
  public static func inital() -> TalkifySpeechRecognizer {
    return .init(
      microphonePermission: MicrophonePermission(),
      recordingSession: TalkifyRecordingSession()
    )
  }

  /// Initializes a new `TalkifySpeechRecognizer` object with the given parameters.
  public init(
    recognitionRequest: SFSpeechAudioBufferRecognitionRequest? = nil,
    recognitionTask: SFSpeechRecognitionTask? = nil,
    language: TalkifyLanguage = .englishUS,
    microphonePermission: MicrophonePermission,
    recordingSession: TalkifyRecordingSession
  ) {
    self.recognitionRequest = recognitionRequest
    self.recognitionTask = recognitionTask
    self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: language.rawValue))!
    self.microphonePermission = microphonePermission
    self.recordingSession = recordingSession
  }

  /// Requests recorder to ask for permission and if granted, immediately start recording
  public func requestListening() {
    checkMicrophonePermission()
  }

  /// Checks the status of microphone permission.
  public func checkMicrophonePermission() {
    microphonePermission.checkPermissionStatus { [weak self] status in
      guard let self = self else {
        return
      }

      switch status {
      case .granted:
        delegate?.voiceRecorderDidCheckMicrophonePermission(status: .granted)
        startRecording()
      case .denied:
        delegate?.voiceRecorderDidCheckMicrophonePermission(status: .denied)
        print("Microphone permission denied.")
      case .undetermined:
        delegate?.voiceRecorderDidCheckMicrophonePermission(status: .undetermined)
        requestMicrophonePermission()
      }
    }
  }

  /// Requests microphone permission.
  public func requestMicrophonePermission() {
    microphonePermission.requestPermission { [weak self] granted in
      guard let self = self else {
        return
      }

      self.delegate?.voiceRecorderDidRequestMicrophonePermission(granted: granted)
      if granted {
        self.startRecording()
      } else {
        print("Microphone permission denied")
      }
    }
  }

  /// Start audio recording and recognition
  private func startRecording() {
    print("Recording did start")
    SFSpeechRecognizer.requestAuthorization { (authStatus) in
      OperationQueue.main.addOperation {
        switch authStatus {
        case .authorized:
          // The user authorized your app for speech recognition.
          // Update your UI to reflect this authorization status.
          print("Speech recognition authorized")

        case .denied:
          // The user denied your app's use of speech recognition.
          // Update your UI to reflect this authorization status.
          print("User denied access to speech recognition")

        case .restricted, .notDetermined:
          // Speech recognition restricted on this device or user has not yet responded to the access prompt.
          // Update your UI to reflect this authorization status.
          print("Speech recognition restricted/not determined")

        @unknown default:
          print("Unknown authorization status for speech recognition")
        }
      }
    }
    do {
      try recordingSession.prepareSession()
      let inputNode = recordingSession.getInputNode(audioEngine: audioEngine)
      recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
      guard let recognitionRequest = recognitionRequest else {
        fatalError("Unable to create an SFSpeechAudioBufferRecognitionRequest object.")
      }
      recognitionRequest.shouldReportPartialResults = true

      recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
        var isFinal = false
        if let result = result {
          let text = result.bestTranscription.formattedString
          isFinal = result.isFinal
          self.delegate?.voiceRecorderDidFinishRecordingWithText(text)
        }

        if error != nil || isFinal {
          self.audioEngine.stop()
          inputNode.removeTap(onBus: 0)
          self.recognitionRequest = nil
          self.recognitionTask = nil
        }
      }

      // Start recording.
      let recordingFormat = inputNode.outputFormat(forBus: 0)
      inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
        self.recognitionRequest?.append(buffer)
      }
      audioEngine.prepare()
      try audioEngine.start()
      delegate?.voiceRecorderDidStartRecording()
    } catch {
      print("Unable to configure the audio session: \(error.localizedDescription)")
      delegate?.voiceRecorderDidEncounterError(error)
    }
  }

  /// Stops recording
  func stopRecording() {
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    recognitionTask?.cancel()
    recognitionTask = nil
  }
}

