//
//  Talkify.swift
//
//
//  Created by Tornike on 20/03/2023.
//

import Foundation
import AVFoundation

/// A class that handles speech synthesis and recognition
@available(iOS 13.0, *)
@available(macOS 10.15, *)
public class Talkify {
  /// The delegate for recording-related events
  public weak var recordingDelegate: TalkifyRecordingDelegate?

  /// The delegate for speech synthesis-related events
  public weak var speakingDelegate: TalkifySpeakingDelegate?

  /// The recognized text from the most recent recording
  public private(set) var recognizedText: String?

  private var voiceRecorder: TalkifySpeechRecognizer
  private var talkifySpeaker: TalkifySpeaker

  /// Creates a new `TalkifySpeechRecognizer` instance
  public init(voiceRecorder: TalkifySpeechRecognizer = .inital(), speaker: TalkifySpeaker = .init()) {
    self.voiceRecorder = voiceRecorder
    self.talkifySpeaker = speaker
  }

  @discardableResult
  public func setupRecording() -> Self {
    voiceRecorder.delegate = self
    return self
  }

  @discardableResult
  public func startRecording() -> Self {
    voiceRecorder.requestListening()
    return self
  }

  public func stopRecording() {
    voiceRecorder.stopRecording()
    guard let recognizedText else {
      return
    }

    recordingDelegate?.recordingDidFinishWithResults(text: recognizedText)
  }

  public func startSpeaking(with text: String) {
    talkifySpeaker.startSpeaking(with: text)
  }


  public func stopSpeaking() {
    talkifySpeaker.stopSpeaking()
  }

  public func pauseSpeaking() {
    talkifySpeaker.pauseSpeaking()
  }

  public func continueSpeaking() {
    talkifySpeaker.continueSpeaking()
  }
}

// MARK: - Recording Delegate
@available(iOS 13.0, *)
@available(macOS 10.15, *)
extension Talkify: VoiceRecorderDelegate {
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
    recordingDelegate?.recordingDidFinishWithResults(text: recognizedText)
  }
}
