//
//  TalkifyRecordingSession.swift
//
//
//  Created by Tornike on 05/08/2023.
//
//
// `TalkifyRecordingSession` is a public class that wraps a `RecordingSession` object.
// It provides methods to prepare the recording session and get the input node from an `AVAudioEngine`.

import Foundation
import AVFAudio

public class TalkifyRecordingSession {
  private let recordingSession: RecordingSession

  /// Initializes a new `TalkifyRecordingSession` object with the given `RecordingSession`.
  ///
  /// - Parameter recordingSession: The `RecordingSession` instance.
  init(recordingSession: RecordingSession = defaultRecordingSession()) {
    self.recordingSession = recordingSession
  }

  /// Prepares the recording session.
  public func prepareSession() throws {
    try recordingSession.__prepareSession()
  }

  /// Returns the input node from the given `AVAudioEngine`.
  ///
  /// - Parameter audioEngine: The `AVAudioEngine` instance.
  public func getInputNode(audioEngine: AVAudioEngine) -> AVAudioNode {
    return recordingSession.getInputNode(audioEngine: audioEngine)
  }

  /// Returns the default `RecordingSession` for the current platform.
  private static func defaultRecordingSession() -> RecordingSession {
  #if os(iOS)
    return iOSRecordingSession()
  #elseif os(macOS)
    return MacOSRecordingSession()
  #else
    fatalError("Unsupported platform")
  #endif
  }
}
