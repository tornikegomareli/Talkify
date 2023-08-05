//
//  TalkifySpeakingDelegate.swift
//  
//
//  Created by Tornike on 05/08/2023.
//

import Foundation
import AVFAudio

@available(macOS 10.15, *)
public class TalkifySpeaker {
  public weak var delegate: TalkifySpeakingDelegate?
  private var synthesizer = AVSpeechSynthesizer()
  private var voice = TalkifyVoice()
  private var voiceRate: Float = 0.5
  private var multiplier: Float = 0.5
  private var volume: Float = 1.0

  public init() {}

  @discardableResult
  public func withVoice(customVoice: TalkifyVoice) -> Self {
    voice = customVoice
    return self
  }

  @discardableResult
  public func withVoiceRate(value: Float) -> Self {
    voiceRate = value
    return self
  }

  @discardableResult
  public func withMultiplier(value: Float) -> Self {
    multiplier = value
    return self
  }

  @discardableResult
  public func withVolume(value: Float) -> Self {
    volume = value
    return self
  }

  public func startSpeaking(with text: String) {
    let utterance = TalkifyUtternace(string: text)
    utterance.setupTalkifyValues(customVoice: voice, customRate: voiceRate, customMultiplier: multiplier, customVolume: volume)
    synthesizer.speak(utterance)
    delegate?.speakingDidStart()
  }

  public func stopSpeaking() {
    guard synthesizer.isSpeaking || synthesizer.isPaused else {
      return
    }
    synthesizer.stopSpeaking(at: .immediate)
    delegate?.speakingDidStop()
  }

  public func pauseSpeaking() {
    guard synthesizer.isSpeaking else {
      return
    }
    synthesizer.pauseSpeaking(at: .immediate)
    delegate?.speakingDidPause()
  }

  public func continueSpeaking() {
    guard synthesizer.isPaused else {
      return
    }
    synthesizer.continueSpeaking()
    delegate?.speakingDidContinue()
  }
}
