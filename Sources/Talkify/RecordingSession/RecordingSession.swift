//
//  RecordingSession.swift
//
//
//  Created by Tornike on 05/08/2023.
//
//
// `RecordingSession` is a public protocol that defines the requirements for a recording session.
// It provides methods to prepare a recording session and get the input node from an `AVAudioEngine`.

import Foundation
import AVFAudio

public protocol RecordingSession {
  /// Prepares the recording session.
  func __prepareSession() throws

  /// Returns the input node from the given `AVAudioEngine`.
  ///
  /// - Parameter audioEngine: The `AVAudioEngine` instance.
  func getInputNode(audioEngine: AVAudioEngine) -> AVAudioNode
}
