//
//  MacOSRecordingSession.swift
//  
//
//  Created by Tornike on 05/08/2023.
//

import Foundation

#if os(macOS)
import AVFoundation

struct MacOSRecordingSession: RecordingSession {
  func __prepareSession() throws {
    return
  }

  func getInputNode(audioEngine: AVAudioEngine) -> AVAudioNode {
    return audioEngine.inputNode
  }
}
#endif
