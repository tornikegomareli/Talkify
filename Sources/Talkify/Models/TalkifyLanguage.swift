//
//  TalkifyLanguage.swift
//
//
//  Created by Tornike on 19/03/2023.
//

import Foundation
import AVFoundation

/// This enum represents the different languages that are supported by `AVSpeechSynthesisVoice`.
public enum TalkifyLanguage: String, CaseIterable {
  // MARK: - English
  case englishAU = "en-AU"
  case englishGB = "en-GB"
  case englishUS = "en-US"
  case englishIE = "en-IE"
  case englishZA = "en-ZA"

  // MARK: - Chinese
  case chineseCN = "zh-CN"
  case chineseHK = "zh-HK"
  case chineseTW = "zh-TW"

  // MARK: - Dutch
  case dutchBE = "nl-BE"
  case dutchNL = "nl-NL"

  // MARK: - French
  case frenchCA = "fr-CA"
  case frenchFR = "fr-FR"

  // MARK: - German
  case germanDE = "de-DE"
  case germanAT = "de-AT"
  case germanCH = "de-CH"

  // MARK: - Italian
  case italianIT = "it-IT"

  // MARK: - Japanese
  case japaneseJP = "ja-JP"

  // MARK: - Korean
  case koreanKR = "ko-KR"

  // MARK: - Norwegian
  case norwegianNO = "nb-NO"

  // MARK: - Polish
  case polish = "pl-PL"

  // MARK: - Portuguese
  case portugueseBR = "pt-BR"
  case portuguesePT = "pt-PT"

  // MARK: - Romanian
  case romanian = "ro-RO"

  // MARK: - Russian
  case russianRU = "ru-RU"

  // MARK: - Slovak
  case slovak = "sk-SK"

  // MARK: - Spanish
  case spanishAR = "es-AR"
  case spanishMX = "es-MX"
  case spanishES = "es-ES"
  case spanishUS = "es-US"

  // MARK: - Swedish
  case swedishSE = "sv-SE"

  // MARK: - Thai
  case thai = "th-TH"

  // MARK: - Turkish
  case turkishTR = "tr-TR"

  // MARK: - Georgian
  /// There is not such country yet supported by Apple
  case georgian = "ge"

  // MARK: - Computed Properties

  /// The display name of the language in its own script.
  var displayName: String {
    switch self {
    case .englishAU:
      return "English (Australia)"
    case .englishGB:
      return "English (United Kingdom)"
    case .englishUS:
      return "English (United States)"
    case .englishIE:
      return "English (Ireland)"
    case .englishZA:
      return "English (South Africa)"
    case .chineseCN:
      return "中文(中国)"
    case .chineseHK:
      return "中文(香港)"
    case .chineseTW:
      return "中文(台灣)"
    case .dutchBE:
      return "Nederlands (België)"
    case .dutchNL:
      return "Nederlands (Nederland)"
    case .frenchCA:
      return "Français (Canada)"
    case .frenchFR:
      return "Français (France)"
    case .germanDE:
      return "Deutsch (Deutschland)"
    case .germanAT:
      return "Deutsch (Österreich)"

    case .germanCH:
      return "Deutsch (Schweiz)"
    case .italianIT:
      return "Italiano (Italia)"
    case .japaneseJP:
      return "日本語 (日本)"
    case .koreanKR:
      return "한국어 (대한민국)"
    case .norwegianNO:
      return "Norsk (Norge)"
    case .polish:
      return "Polski (Polska)"
    case .portugueseBR:
      return "Português (Brasil)"
    case .portuguesePT:
      return "Português (Portugal)"
    case .romanian:
      return "Română (România)"
    case .russianRU:
      return "Русский (Россия)"
    case .slovak:
      return "Slovenčina (Slovenská republika)"
    case .spanishAR:
      return "Español (Argentina)"
    case .spanishMX:
      return "Español (México)"
    case .spanishES:
      return "Español (España)"
    case .spanishUS:
      return "Español (Estados Unidos)"
    case .swedishSE:
      return "Svenska (Sverige)"
    case .thai:
      return "ไทย (ประเทศไทย)"
    case .turkishTR:
      return "Türkçe (Türkiye)"
    case .georgian:
      return "Georgian"
    }
  }

  // MARK: - Helper methods

  /// Returns the all identifier
  static var allIdentifiers: [String] {
    return allCases.map { $0.rawValue }
  }

  /// Returns the all the `TalkifyLanguage` array of objects which are available for coressponding Language code
  static func languages(forVoiceIdentifier identifier: TalkativeVoiceIdentifier) -> [TalkifyLanguage] {
    let identifierString = identifier.rawValue
    let languageCodes = TalkifyLanguage.allCases.filter { language in
      identifierString.contains(language.rawValue)
    }
    return languageCodes
  }
}

