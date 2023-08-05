//
//  iOSRecordingSession.swift
//
//
//  Created by Tornike on 05/08/2023.
//
//
// `iOSRecordingSession` is a structure that conforms to the `RecordingSession` protocol.
// It provides functionality specific to iOS devices.
// This code is only compiled for the iOS platform.

#if os(iOS)
import AVFoundation

struct iOSRecordingSession: RecordingSession {
  private let audioSession = AVAudioSession.sharedInstance()

  /// Prepares the recording session for iOS devices. This involves setting the category and mode of the audio session,
  /// and activating the audio session.
  func __prepareSession() throws {
    try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
  }

  /// Returns the input node from the given `AVAudioEngine`.
  ///
  /// - Parameter audioEngine: The `AVAudioEngine` instance.
  func getInputNode(audioEngine: AVAudioEngine) -> AVAudioNode {
    return audioEngine.inputNode
  }
}
#endif
