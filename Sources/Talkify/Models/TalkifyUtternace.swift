//
//  TalkativeUtternace.swift
//
//
//  Created by Tornike on 19/03/2023.
//

import Foundation
import AVFoundation

/// A subclass of `AVSpeechUtterance` that allows for metadata to be associated with the utterance.
class TalkifyUtternace: AVSpeechUtterance {

  /// A dictionary of metadata associated with the utterance.
  var metadata: [String: Any] = [:]

  // MARK: - Private Properties

  /// The string to speak.
  private var stringToSpeak: String = ""

  /// The attributed string to speak.
  private var attributedStringToSpeak: NSAttributedString = NSAttributedString(string: "")

  // MARK: - Overrides

  override public var speechString: String {
    get {
      return stringToSpeak
    }
    set {
      stringToSpeak = newValue
      attributedStringToSpeak = NSAttributedString(string: newValue)
    }
  }

  override public var attributedSpeechString: NSAttributedString {
    get {
      return attributedStringToSpeak
    }
    set {
      stringToSpeak = newValue.string
      attributedStringToSpeak = newValue
      addAttributesFrom(attributedStringToSpeak)
    }
  }

  // MARK: - Initialization

  override init(string: String) {
    super.init(string: string)
    setupTalkifyValues()
  }

  convenience override init(attributedString: NSAttributedString) {
    self.init(string: attributedString.string)
    addAttributesFrom(attributedString)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Private Methods

  /// Sets up the values for the utterance.
  public func setupTalkifyValues(
    customVoice: TalkativeVoice = TalkativeVoice(),
    customRate: Float = 1.0,
    customMultiplier: Float = 1.0,
    customVolume: Float = 1.0
  ) {
    voice = customVoice
    rate = customRate
    pitchMultiplier = customMultiplier
    volume = customVolume
  }

  /// Adds attributes from an attributed string to the utterance.
  ///
  /// - Parameter attributedString: The attributed string to add attributes from.
  private func addAttributesFrom(_ attributedString: NSAttributedString) {
    attributedString.enumerateAttributes(in: NSRange(location: 0, length: attributedString.length), options: []) { attributes, range, _ in
      attributes.forEach { key, value in
        switch key {
        case .speechVoice:
          self.voice = value as? AVSpeechSynthesisVoice ?? self.voice
        case .speechRate:
          self.rate = value as? Float ?? self.rate
        case .speechPitch:
          self.pitchMultiplier = value as? Float ?? self.pitchMultiplier
        case .speechVolume:
          self.volume = value as? Float ?? self.volume
        default:
          self.metadata[String(describing: key)] = value
        }
      }
    }
  }

}
