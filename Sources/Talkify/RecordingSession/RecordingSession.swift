//
//  RecordingSession.swift
//  
//
//  Created by Tornike on 05/08/2023.
//

import Foundation
import AVFAudio

public protocol RecordingSession {
  func __prepareSession() throws
  func getInputNode(audioEngine: AVAudioEngine) -> AVAudioNode
}
