//
//  VoiceRecorder.swift
//
//
//  Created by Tornike on 19/03/2023.
//

import Foundation
import AVFoundation
import Speech

/// Delegate protocol to handle voice recording events
public protocol VoiceRecorderDelegate: AnyObject {
  func voiceRecorderDidFinishRecordingWithText(_ text: String)
  func voiceRecorderDidStartRecording()
  func voiceRecorderDidStopRecording()
  func voiceRecorderDidEncounterError(_ error: Error)
  func voiceRecorderDidCheckMicrophonePermission(status: AudioPermissionStatus)
  func voiceRecorderDidRequestMicrophonePermission(granted: Bool)
}

@available(macOS 10.15, *)
public class VoiceRecorder {
  public weak var delegate: VoiceRecorderDelegate?

  public let audioEngine = AVAudioEngine()
  public let speechRecognizer: SFSpeechRecognizer

  public private(set) var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  public private(set) var recognitionTask: SFSpeechRecognitionTask?

  private var microphonePermission: MicrophonePermission
  private var recordingSession: TalkifyRecordingSession

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

  /// Request microphone permission
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
    audioEngine.inputNode.removeTap(onBus: 0) // Remove the tap on the input node
    recognitionTask?.cancel()
    recognitionTask = nil
  }
}

