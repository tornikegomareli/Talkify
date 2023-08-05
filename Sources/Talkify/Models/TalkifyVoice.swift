//
//  TalkifyVoice.swift
//
//
//  Created by Tornike on 19/03/2023.
//

import Foundation
import AVFoundation

/**
 A class representing a voice used for text-to-speech synthesis.
 */
@available(macOS 10.14, *)
@available(iOS 9.0, *)
public class TalkifyVoice: AVSpeechSynthesisVoice {

  // MARK: - Properties

  /// The identifier of the voice.
  private var voiceIdentifier: TalkifyVoiceIdentifier

  /// The quality of the voice.
  private var voiceQuality: AVSpeechSynthesisVoiceQuality

  // MARK: - Overridden Properties

  @available(iOS 13.0, *)
  @available(macOS 10.15, *)
  @available(macOS 10.15, *)
  public override var gender: AVSpeechSynthesisVoiceGender {
    return super.gender
  }

  override public var identifier: String {
    return voiceIdentifier.rawValue
  }

  public override var quality: AVSpeechSynthesisVoiceQuality {
    return voiceQuality
  }

  // MARK: - Initializers

  /**
   Initializes a new instance of `TalkifyVoice`.

   - Parameters:
   - voice: The identifier of the voice.
   - language: The language of the voice.
   - quality: The quality of the voice.
   */
  public init(voice: TalkifyVoiceIdentifier = .samantha, quality: AVSpeechSynthesisVoiceQuality = .default) {
    self.voiceQuality = quality
    self.voiceIdentifier = voice
    super.init()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Public Methods

  /**
   Resets the voice to its default values.

   - Returns: A new instance of `TalkifyVoice` with default values.
   */
  public func reset() -> TalkifyVoice {
    return TalkifyVoice()
  }

  /**
   Sets the voice to the specified values.

   - Parameters:
   - voice: The identifier of the voice.
   - language: The language of the voice.
   - quality: The quality of the voice.
   */
  public func setVoice(voice: TalkifyVoiceIdentifier, quality: AVSpeechSynthesisVoiceQuality) {
    self.voiceQuality = quality
    self.voiceIdentifier = voice
  }
}
