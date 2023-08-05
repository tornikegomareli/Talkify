//
//  iOSRecordingSession.swift
//  
//
//  Created by Tornike on 05/08/2023.
//

#if os(iOS)
import AVFoundation

struct iOSRecordingSession: RecordingSession {
  private let audioSession = AVAudioSession.sharedInstance()

  func __prepareSession() throws {
    try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
  }

  func getInputNode(audioEngine: AVAudioEngine) -> AVAudioNode {
    return audioEngine.inputNode
  }
}
#endif
