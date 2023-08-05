//
//  TalkifyRecordingSession.swift
//  
//
//  Created by Tornike on 05/08/2023.
//

import Foundation
import AVFAudio

public class TalkifyRecordingSession {
  private let recordingSession: RecordingSession

  init(recordingSession: RecordingSession = defaultRecordingSession()) {
    self.recordingSession = recordingSession
  }

  public func prepareSession() throws {
    try recordingSession.__prepareSession()
  }

  public func getInputNode(audioEngine: AVAudioEngine) -> AVAudioNode {
    return recordingSession.getInputNode(audioEngine: audioEngine)
  }

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
