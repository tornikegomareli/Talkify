//
//  TalkifySpeechRecognition.swift
//
//
//  Created by Tornike on 20/03/2023.
//

import Foundation
import AVFoundation

/// A protocol for delegates that receive recording-related events
public protocol TalkifySpeechRecognizerProvider: AnyObject {
  /// Called when recording finishes with recognized text
  ///
  /// - Parameters:
  ///     - text: The recognized text
  func recordingDidFinishWithResults(text: String)

  /// Called when recording starts
  func recordingDidStart()

  /// Called when recording stops
  func recordingDidStop()

  /// Called when an error occurs during recording
  ///
  /// - Parameters:
  ///     - error: The error that occurred
  func recordingDidEncounterError(error: Error)

  /// Called when microphone permission status changes
  ///
  /// - Parameters:
  ///     - status: The new microphone permission status
  func microphonePermissionDidChange(with status: AudioPermissionStatus)

  /// Called when permission to access the microphone is requested
  ///
  /// - Parameters:
  ///     - granted: Whether permission was granted or not
  func permissionDidRequest(granted: Bool)
}


/// A protocol for delegates that receive speech synthesis-related events
public protocol TalkifySpeechRecognitionSpeakingDelegate: AnyObject {
  /// Called when speech synthesis finishes
  func speakingDidFinish()

  /// Called when speech synthesis pauses
  func speakingDidPause()

  /// Called when speech synthesis continues
  func speakingDidContinue()

  /// Called when speech synthesis stops
  func speakingDidStop()

  /// Called when speech synthesis starts
  func speakingDidStart()
}

/// A class that handles speech synthesis and recognition
@available(macOS 10.15, *)
public class TalkifySpeechRecognizer {

  /// The delegate for recording-related events
  public weak var recordingDelegate: TalkifySpeechRecognizerProvider?

  /// The delegate for speech synthesis-related events
  public weak var speakingDelegate: TalkifySpeechRecognitionSpeakingDelegate?

  /// The recognized text from the most recent recording
  public private(set) var recognizedText: String?

  private var synthesizer = AVSpeechSynthesizer()
  private var voice = TalkifyVoice()
  private var voiceRate: Float = 0.5
  private var multiplier: Float = 0.5
  private var volume: Float = 1.0
  private var voiceRecorder: VoiceRecorder

  /// Creates a new `TalkifySpeechRecognizer` instance
  public init() {
    voiceRecorder = .init(
      microphonePermission: MicrophonePermission(),
      recordingSession: TalkifyRecordingSession()
    )
  }

  /// Begins speech synthesis with the given text
  ///
  /// - Parameters:
  ///     - text: The text to synthesize
  public func startSpeaking(with text: String) {
    let utternace = TalkifyUtternace(string: text)
    utternace.setupTalkifyValues(customVoice: voice, customRate: voiceRate, customMultiplier: multiplier, customVolume: volume)
    synthesizer.speak(utternace)
    speakingDelegate?.speakingDidStart()
  }

  /// Stops speech synthesis if it is currently speaking or paused
  public func stopSpeaking() {
    guard synthesizer.isSpeaking || synthesizer.isPaused else {
      return
    }
    synthesizer.stopSpeaking(at: .immediate)
    speakingDelegate?.speakingDidStop()
  }

  /// Resumes speech synthesis if it is currently paused
  public func continueSpeaking() {
    guard synthesizer.isPaused else {
      return
    }

    synthesizer.continueSpeaking()
    speakingDelegate?.speakingDidContinue()
  }

  /// Sets up the voice recorder and returns the receiver
  ///
  /// - Returns: The receiver
  @discardableResult
  public func setupRecording() -> Self {
    voiceRecorder.delegate = self
    return self
  }

  /// Stops the current recording and sends the recognized text to the recording delegate
  public func stopRecording() {
    voiceRecorder.stopRecording()
    guard let recognizedText else {
      return
    }

    recordingDelegate?.recordingDidFinishWithResults(text: recognizedText)
  }

  /// Starts recording
  ///
  /// - Returns: The receiver
  @discardableResult
  public func startRecording() -> Self {
    voiceRecorder.requestListening()
    return self
  }

  /// Sets the voice for speech synthesis and returns the receiver
  ///
  /// - Parameters:
  ///     - customVoice: The new voice
  /// - Returns: The receiver
  @discardableResult
  public func withVoice(customVoice: TalkifyVoice) -> Self {
    voice = customVoice
    return self
  }

  /// Sets the speech rate and returns the receiver
  ///
  /// - Parameters:
  ///     - value: The new speech rate
  /// - Returns: The receiver
  @discardableResult
  public func withVoiceRate(value: Float) -> Self {
    voiceRate = value
    return self
  }

  /// Sets the multiplier and returns the receiver
  ///
  /// - Parameters:
  ///     - value: The new multiplier
  /// - Returns: The receiver
  @discardableResult
  public func withMultiplier(value: Float) -> Self {
    multiplier = value
    return self
  }

  /// Sets the volume and returns the receiver
  ///
  /// - Parameters:
  ///     - value: The new volume
  /// - Returns: The receiver
  @discardableResult
  public func withVolume(value: Float) -> Self {
    volume = value
    return self
  }

  public static func samantha() -> TalkifySpeechRecognizer {
    return TalkifySpeechRecognizer()
      .withMultiplier(value: 1)
      .withVoiceRate(value: 0.5)
      .withVolume(value: 1)
      .withVoice(
        customVoice: .init(voice: .samantha)
      )
  }

  public static func ralph() -> TalkifySpeechRecognizer {
    return TalkifySpeechRecognizer()
      .withMultiplier(value: 1)
      .withVoiceRate(value: 0.5)
      .withVolume(value: 1)
      .withVoice(
        customVoice: .init(voice: .ralph)
      )
  }

  public static func zarvox() -> TalkifySpeechRecognizer {
    return TalkifySpeechRecognizer()
      .withMultiplier(value: 1)
      .withVoiceRate(value: 0.5)
      .withVolume(value: 1)
      .withVoice(
        customVoice: .init(voice: .zarvox)
      )
  }

  public static func rishi() -> TalkifySpeechRecognizer {
    return TalkifySpeechRecognizer()
      .withMultiplier(value: 1)
      .withVoiceRate(value: 0.5)
      .withVolume(value: 1)
      .withVoice(
        customVoice: .init(voice: .rishi)
      )
  }
}

// MARK: - VoiceRecorderDelegate
@available(macOS 10.15, *)
extension TalkifySpeechRecognizer: VoiceRecorderDelegate {
  /// Notifies the delegate that the voice recorder has started recording audio.
  public func voiceRecorderDidStartRecording() {
    recordingDelegate?.recordingDidStart()
  }

  /// Notifies the delegate that the voice recorder has stopped recording audio.
  public func voiceRecorderDidStopRecording() {
    recordingDelegate?.recordingDidStop()
  }

  /// Notifies the delegate that the voice recorder has encountered an error.
  ///
  /// - Parameters:
  ///     - error: The error that occurred.
  public func voiceRecorderDidEncounterError(_ error: Error) {
    recordingDelegate?.recordingDidEncounterError(error: error)
  }

  /// Notifies the delegate that the voice recorder has checked the microphone permission status.
  ///
  /// - Parameters:
  ///     - status: The current microphone permission status.
  public func voiceRecorderDidCheckMicrophonePermission(status: AudioPermissionStatus) {
    recordingDelegate?.microphonePermissionDidChange(with: status)
  }

  /// Notifies the delegate that the voice recorder has requested microphone permission.
  ///
  /// - Parameters:
  ///     - granted: A boolean value indicating whether the permission was granted or not.
  public func voiceRecorderDidRequestMicrophonePermission(granted: Bool) {
    recordingDelegate?.permissionDidRequest(granted: granted)
  }

  /// Notifies the delegate that the voice recorder has finished recording and recognized the text.
  ///
  /// - Parameters:
  ///     - text: The recognized text.
  public func voiceRecorderDidFinishRecordingWithText(_ text: String) {
    recognizedText = text
    print(text)
  }
}
