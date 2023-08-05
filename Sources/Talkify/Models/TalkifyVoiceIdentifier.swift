import Foundation
import AVFoundation

/// A list of available `AVSpeechSynthesisVoiceIdentifier` options supported by Apple for text-to-speech conversion.
@available(macOS 10.14, *)
public enum TalkifyVoiceIdentifier: String, CaseIterable {
  // Case representing Maged voice identifier for Arabic language (ar-001) for AVSynthesizer
  case maged = "com.apple.voice.compact.ar-001.Maged"

  /// Case representing Daria voice identifier for Bulgarian language (bg-BG) for AVSynthesizer
  case daria = "com.apple.voice.compact.bg-BG.Daria"

  /// Case representing Montserrat voice identifier for Catalan language (ca-ES) for AVSynthesizer
  case montserrat = "com.apple.voice.compact.ca-ES.Montserrat"

  /// Case representing Zuzana voice identifier for Czech language (cs-CZ) for AVSynthesizer
  case zuzana = "com.apple.voice.compact.cs-CZ.Zuzana"

  /// Case representing Sara voice identifier for Danish language (da-DK) for AVSynthesizer
  case sara = "com.apple.voice.compact.da-DK.Sara"

  /// Case representing Anna voice identifier for German language (de-DE) for AVSynthesizer
  case anna = "com.apple.voice.compact.de-DE.Anna"

  /// Case representing Melina voice identifier for Greek language (el-GR) for AVSynthesizer
  case melina = "com.apple.voice.compact.el-GR.Melina"

  /// Case representing Karen voice identifier for Australian English language (en-AU) for AVSynthesizer
  case karen = "com.apple.voice.compact.en-AU.Karen"

  /// Case representing Daniel voice identifier for British English language (en-GB) for AVSynthesizer
  case daniel = "com.apple.voice.compact.en-GB.Daniel"

  /// Case representing Moira voice identifier for Irish English language (en-IE) for AVSynthesizer
  case moira = "com.apple.voice.compact.en-IE.Moira"

  /// Case representing Rishi voice identifier for Indian English language (en-IN) for AVSynthesizer
  case rishi = "com.apple.voice.compact.en-IN.Rishi"

  /// Case representing Trinoids voice identifier for Trinidadian English language for AVSynthesizer
  case trinoids = "com.apple.speech.synthesis.voice.Trinoids"

  /// Case representing Albert voice identifier for South African English language for AVSynthesizer
  case albert = "com.apple.speech.synthesis.voice.Albert"

  /// Case representing Hysterical voice identifier for South African English language for AVSynthesizer
  case hysterical = "com.apple.speech.synthesis.voice.Hysterical"

  /// Case representing Samantha voice identifier for US English language (en-US) for AVSynthesizer
  case samantha = "com.apple.voice.compact.en-US.Samantha"

  /// Case representing Whisper voice identifier for US English language (en-US) for AVSynthesizer
  case whisper = "com.apple.speech.synthesis.voice.Whisper"

  /// Case representing Princess voice identifier for US English language (en-US) for AVSynthesizer
  case princess = "com.apple.speech.synthesis.voice.Princess"

  /// Case representing Bells voice identifier for US English language (en-US) for AVSynthesizer
  case bells = "com.apple.speech.synthesis.voice.Bells"

  /// Case representing Organ voice identifier for US English language (en-US) for AVSynthesizer
  case organ = "com.apple.speech.synthesis.voice.Organ"

  /// Case representing BadNews voice identifier for US English language (en-US) for AVSynthesizer

  /// English, male voice with a sarcastic tone
  case badNews = "com.apple.speech.synthesis.voice.BadNews"

  /// English, female voice with a high-pitched, bubbly tone
  case bubbles = "com.apple.speech.synthesis.voice.Bubbles"

  /// English, child's voice
  case junior = "com.apple.speech.synthesis.voice.Junior"

  /// English, male voice with a sheep-like bahh sound in his speech
  case bahh = "com.apple.speech.synthesis.voice.Bahh"

  /// English, male voice with a crazed tone
  case deranged = "com.apple.speech.synthesis.voice.Deranged"

  /// English, male voice with a boing sound in his speech
  case boing = "com.apple.speech.synthesis.voice.Boing"

  /// English, male voice with a positive, cheerful tone
  case goodNews = "com.apple.speech.synthesis.voice.GoodNews"

  /// English, male voice with a robotic, futuristic tone
  case zarvox = "com.apple.speech.synthesis.voice.Zarvox"

  /// English, male voice with a New York accent
  case ralph = "com.apple.speech.synthesis.voice.Ralph"

  /// English, male voice with a deep, mellow tone
  case cellos = "com.apple.speech.synthesis.voice.Cellos"

  /// English, female voice with a warm, friendly tone
  case kathy = "com.apple.speech.synthesis.voice.Kathy"

  /// English, male voice with a nasal quality
  case fred = "com.apple.speech.synthesis.voice.Fred"

  /// English, female voice with a South African accent
  case tessa = "com.apple.voice.compact.en-ZA.Tessa"

  /// Spanish, female voice with a neutral accent
  case monica = "com.apple.voice.compact.es-ES.Monica"

  /// Spanish, female voice with a Mexican accent
  case paulina = "com.apple.voice.compact.es-MX.Paulina"

  /// Finnish, female voice with a neutral accent
  case satu = "com.apple.voice.compact.fi-FI.Satu"

  /// French, female voice with a Canadian accent
  case amelie = "com.apple.voice.compact.fr-CA.Amelie"

  /// French, male voice with a neutral accent
  case thomas = "com.apple.voice.compact.fr-FR.Thomas"

  /// Hebrew, female voice with an Israeli accent
  case carmit = "com.apple.voice.compact.he-IL.Carmit"

  /// Hindi, female voice with an Indian accent
  case lekha = "com.apple.voice.compact.hi-IN.Lekha"

  /// Croatian, female voice with a neutral accent
  case lana = "com.apple.voice.compact.hr-HR.Lana"

  /// Hungarian, female voice with a neutral accent
  case mariska = "com.apple.voice.compact.hu-HU.Mariska"

  /// Indonesian, female voice with a neutral accent
  case damayanti = "com.apple.voice.compact.id-ID.Damayanti"

  /// Italian, female voice with a neutral accent
  case alice = "com.apple.voice.compact.it-IT.Alice"

  /// Japanese, female voice with a neutral accent
  case kyoko = "com.apple.voice.compact.ja-JP.Kyoko"

  /// Korean, female voice with a neutral accent
  case yuna = "com.apple.voice.compact.ko-KR.Yuna"


  /// Malay, female voice with a neutral accent
  case amira = "com.apple.voice.compact.ms-MY.Amira"

  /// Norwegian, female voice with a neutral accent
  case nora = "com.apple.voice.compact.nb-NO.Nora"

  /// Dutch (Belgium), female voice
  case ellen = "com.apple.voice.compact.nl-BE.Ellen"

  /// Dutch (Netherlands), male voice
  case xander = "com.apple.voice.compact.nl-NL.Xander"

  /// Polish, female voice
  case zosia = "com.apple.voice.compact.pl-PL.Zosia"

  /// Portuguese (Brazil), female voice
  case luciana = "com.apple.voice.compact.pt-BR.Luciana"

  /// Portuguese (Portugal), female voice
  case joana = "com.apple.voice.compact.pt-PT.Joana"

  /// Romanian, female voice
  case ioana = "com.apple.voice.compact.ro-RO.Ioana"

  /// Russian, female voice
  case milena = "com.apple.voice.compact.ru-RU.Milena"

  /// Slovak, female voice
  case laura = "com.apple.voice.compact.sk-SK.Laura"

  /// Swedish, female voice
  case alva = "com.apple.voice.compact.sv-SE.Alva"

  /// Thai, female voice
  case kanya = "com.apple.voice.compact.th-TH.Kanya"

  /// Turkish (Turkey) - Yelda
  case yelda = "com.apple.voice.compact.tr-TR.Yelda"

  /// Ukrainian (Ukraine) - Lesya
  case lesya = "com.apple.voice.compact.uk-UA.Lesya"

  /// Vietnamese (Vietnam) - Linh
  case linh = "com.apple.voice.compact.vi-VN.Linh"

  /// Chinese (China) - Tingting
  case tingting = "com.apple.voice.compact.zh-CN.Tingting"

  /// Chinese (Hong Kong) - Sinji
  case sinji = "com.apple.voice.compact.zh-HK.Sinji"

  /// Chinese (Taiwan) - Meijia
  case meijia = "com.apple.voice.compact.zh-TW.Meijia"


  // MARK: - Method to get available voice identifiers for a language

  static func availableVoices(forLanguage language: TalkifyLanguage) -> [TalkifyVoiceIdentifier] {
    let voices = AVSpeechSynthesisVoice.speechVoices().filter {
      $0.language.contains(language.rawValue)
    }

    let identifiers = voices.map {
      TalkifyVoiceIdentifier(rawValue: $0.identifier) ?? .samantha
    }
    return identifiers
  }
}
