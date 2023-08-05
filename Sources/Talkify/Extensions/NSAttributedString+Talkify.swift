//
//  NSAttributedString+Talkify.swift
//
//
//  Created by Tornike on 19/03/2023.
//

import Foundation

/// Extension of `NSAttributedString.Key` to define a custom attribute for the speech voice to use when speaking the string.
extension NSAttributedString.Key {
  /// The custom attribute key to specify the speech voice to use.
  static let speechVoice = NSAttributedString.Key("com.example.SpeechVoice")
  static let speechRate = NSAttributedString.Key("com.example.SpeechRate")
  static let speechPitch = NSAttributedString.Key("com.example.SpeechPitch")
  static let speechVolume = NSAttributedString.Key("com.example.SpeechVolume")
}
