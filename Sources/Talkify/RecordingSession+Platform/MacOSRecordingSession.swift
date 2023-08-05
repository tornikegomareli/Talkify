//
//  MacOSRecordingSession.swift
//
//
//  Created by Tornike on 05/08/2023.
//
//
// `MacOSRecordingSession` is a structure that conforms to the `RecordingSession` protocol.
// It provides functionality specific to macOS devices.
// This code is only compiled for the macOS platform.

#if os(macOS)
import AVFoundation

struct MacOSRecordingSession: RecordingSession {
  /// Cause macOS does not need any preperation, we are just returning from function
  /// ___ naming tells to dev, that that is not normal and standard function
  func __prepareSession() throws {
    return
  }

  /// Returns the input node from the given `AVAudioEngine`.
  ///
  /// - Parameter audioEngine: The `AVAudioEngine` instance.
  func getInputNode(audioEngine: AVAudioEngine) -> AVAudioNode {
    return audioEngine.inputNode
  }
}
#endif
