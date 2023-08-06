///
///  Talkify.swift
///
///
///  Created by Tornike on 20/03/2023.
///
///
/// `Talkify` is a public class that provides high-level APIs for managing speech synthesis and recognition tasks.
/// This class is available on iOS 13.0 and macOS 10.15 or later.

import Foundation
import AVFoundation

@available(iOS 13.0, *)
@available(macOS 10.15, *)
public class Talkify {
  /// A delegate object that handles recording-related events.
  public weak var recordingDelegate: TalkifyRecordingDelegate?
  
  /// A delegate object that handles speech synthesis-related events.
  public weak var speakingDelegate: TalkifySpeakingDelegate?
  
  /// The recognized text from the most recent recording. This is a read-only property.
  public private(set) var recognizedText: String?
  
  private var voiceRecorder: TalkifySpeechRecognizer
  private var talkifySpeaker: TalkifySpeaker
  
  /// Creates a new `Talkify` instance. By default, it initializes a `TalkifySpeechRecognizer` and a `TalkifySpeaker` instance.
  public init(voiceRecorder: TalkifySpeechRecognizer = .inital(), speaker: TalkifySpeaker = .init()) {
    self.voiceRecorder = voiceRecorder
    self.talkifySpeaker = speaker
  }

  /// Configures the speaker. This method returns a reference to the receiver for chaining purposes.
  @discardableResult
  public func setSpeaker(with speaker: TalkifySpeaker) -> Self {
    talkifySpeaker = speaker
    return self
  }
  
  /// Configures the voice recorder for recording. This method returns a reference to the receiver for chaining purposes.
  @discardableResult
  public func setupRecording() -> Self {
    voiceRecorder.delegate = self
    return self
  }
  
  /// Starts the voice recording process. This method returns a reference to the receiver for chaining purposes.
  @discardableResult
  public func startRecording() -> Self {
    voiceRecorder.requestListening()
    return self
  }
  
  /// Stops the voice recording process and triggers the delegate method for text recognition.
  public func stopRecording() {
    voiceRecorder.stopRecording()
    guard let recognizedText else {
      return
    }
    recordingDelegate?.recordingDidFinishWithResults(text: recognizedText)
  }
  
  /// Starts the speech synthesis process with the given text.
  public func startSpeaking(with text: String) {
    talkifySpeaker.startSpeaking(with: text)
  }
  
  /// Stops the speech synthesis process.
  public func stopSpeaking() {
    talkifySpeaker.stopSpeaking()
  }
  
  /// Pauses the speech synthesis process.
  public func pauseSpeaking() {
    talkifySpeaker.pauseSpeaking()
  }
  
  /// Resumes the speech synthesis process.
  public func continueSpeaking() {
    talkifySpeaker.continueSpeaking()
  }
}

// MARK: - Recording Delegate
@available(iOS 13.0, *)
@available(macOS 10.15, *)
extension Talkify: VoiceRecorderDelegate {
  /// Notifies the delegate when the voice recorder starts recording.
  public func voiceRecorderDidStartRecording() {
    recordingDelegate?.recordingDidStart()
  }
  
  /// Notifies the delegate when the voice recorder stops recording.
  public func voiceRecorderDidStopRecording() {
    recordingDelegate?.recordingDidStop()
  }
  
  /// Notifies the delegate when the voice recorder encounters an error.
  ///
  /// - Parameters:
  ///     - error: The error that occurred.
  public func voiceRecorderDidEncounterError(_ error: Error) {
    recordingDelegate?.recordingDidEncounterError(error: error)
  }
  
  /// Notifies the delegate when the voice recorder checks the microphone permission status.
  ///
  /// - Parameters:
  ///     - status: The current microphone permission status.
  public func voiceRecorderDidCheckMicrophonePermission(status: AudioPermissionStatus) {
    recordingDelegate?.microphonePermissionDidChange(with: status)
  }
  
  /// Notifies the delegate when the voice recorder requests microphone permission.
  ///
  /// - Parameters:
  ///     - granted: A boolean value indicating whether the permission was granted or not.
  public func voiceRecorderDidRequestMicrophonePermission(granted: Bool) {
    recordingDelegate?.permissionDidRequest(granted: granted)
  }
  
  /// Notifies the delegate when the voice recorder finishes recording and recognizes the text.
  ///
  /// - Parameters:
  ///     - text: The recognized text.
  public func voiceRecorderDidFinishRecordingWithText(_ text: String) {
    recognizedText = text
    recordingDelegate?.recordingDidFinishWithResults(text: recognizedText)
  }
}
