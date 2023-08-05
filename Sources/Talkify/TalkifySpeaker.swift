//  TalkifySpeakingDelegate.swift
//
//
//  Created by Tornike on 05/08/2023.
//

import Foundation
import AVFAudio

/// A macOS 10.15+ class that speaks text using `AVSpeechSynthesizer`.
/// Allows configuration of voice, rate, pitch multiplier, and volume.
/// Speaking events are reported to an optional delegate.
@available(macOS 10.15, *)
public class TalkifySpeaker {
  /// The object that acts as the delegate of the `TalkifySpeaker`.
  public weak var delegate: TalkifySpeakingDelegate?

  private var synthesizer = AVSpeechSynthesizer()
  private var voice = TalkifyVoice()
  private var voiceRate: Float = 0.5
  private var multiplier: Float = 0.5
  private var volume: Float = 1.0

  /// Creates a new `TalkifySpeaker`.
  public init() {}

  /// Configures the voice of the speaker.
  /// - Parameter customVoice: The custom voice to be used.
  /// - Returns: A self-reference, enabling chained calls.
  @discardableResult
  public func withVoice(customVoice: TalkifyVoice) -> Self {
    voice = customVoice
    return self
  }

  /// Configures the speaking rate of the speaker.
  /// - Parameter value: The rate at which the speaker should speak.
  /// - Returns: A self-reference, enabling chained calls.
  @discardableResult
  public func withVoiceRate(value: Float) -> Self {
    voiceRate = value
    return self
  }

  /// Configures the pitch multiplier of the speaker.
  /// - Parameter value: The multiplier for the pitch of the speaker's voice.
  /// - Returns: A self-reference, enabling chained calls.
  @discardableResult
  public func withMultiplier(value: Float) -> Self {
    multiplier = value
    return self
  }

  /// Configures the volume of the speaker.
  /// - Parameter value: The volume at which the speaker should speak.
  /// - Returns: A self-reference, enabling chained calls.
  @discardableResult
  public func withVolume(value: Float) -> Self {
    volume = value
    return self
  }

  /// Starts speaking the provided text.
  /// - Parameter text: The text to be spoken.
  public func startSpeaking(with text: String) {
    let utterance = TalkifyUtternace(string: text)
    utterance.setupTalkifyValues(customVoice: voice, customRate: voiceRate, customMultiplier: multiplier, customVolume: volume)
    synthesizer.speak(utterance)
    delegate?.speakingDidStart()
  }

  /// Stops any ongoing speech immediately.
  public func stopSpeaking() {
    guard synthesizer.isSpeaking || synthesizer.isPaused else {
      return
    }
    synthesizer.stopSpeaking(at: .immediate)
    delegate?.speakingDidStop()
  }

  /// Pauses any ongoing speech immediately.
  public func pauseSpeaking() {
    guard synthesizer.isSpeaking else {
      return
    }
    synthesizer.pauseSpeaking(at: .immediate)
    delegate?.speakingDidPause()
  }

  /// Continues any paused speech.
  public func continueSpeaking() {
    guard synthesizer.isPaused else {
      return
    }
    synthesizer.continueSpeaking()
    delegate?.speakingDidContinue()
  }
}
