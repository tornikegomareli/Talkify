import AppKit
import AVFAudio

/// Read Aloud: speaks the focused application's selected text with the
/// Settings-picked voice. Apple speech synthesis only (CONTEXT.md: Apple
/// frameworks only); playback is on-device and offline. Errors surface
/// through the HUD message surface, matching Direct Dictation.
///
/// It reads the selection through Accessibility where it can, and by copying
/// it where it cannot: no browser answers the Accessibility question, and a
/// read-aloud feature that cannot read a web page is broken.
@MainActor
final class ReadAloudController: NSObject {
  /// Follows the synthesizer's actual state; the status menu mirrors it.
  var onSpeakingStateChange: ((Bool) -> Void)?

  private let settings: AppSettings
  private let hudController: DictationHUDController
  private let selectionReader = FocusedSelectionReader()
  private let synthesizer = AVSpeechSynthesizer()
  /// Only reached while the translate setting is on. Read Aloud does not own
  /// translation and does not configure it; it borrows the same coordinator
  /// dictation uses.
  private let translation: TranslationCoordinator
  /// Borrowed for its clipboard, not for insertion. Shared with dictation so
  /// one read lease covers both.
  private let textInsertion: TextInsertionService

  init(
    settings: AppSettings,
    hudController: DictationHUDController,
    translation: TranslationCoordinator,
    textInsertion: TextInsertionService
  ) {
    self.settings = settings
    self.hudController = hudController
    self.translation = translation
    self.textInsertion = textInsertion
    super.init()
    synthesizer.delegate = self
  }

  func toggle() {
    if synthesizer.isSpeaking {
      stop()
    } else {
      speakSelection()
    }
  }

  func stop() {
    synthesizer.stopSpeaking(at: .immediate)
  }

  private func speakSelection() {
    guard PermissionService.hasAccessibilityAccess else {
      hudController.showMessage("Accessibility permission required")
      return
    }

    switch selectionReader.selection() {
    case let .text(selected):
      speak(selection: selected)
    case .secureField:
      // Speaking a password out loud is a worse leak than pasting one, so
      // Read Aloud refuses the same fields Direct Dictation does.
      hudController.showMessage("Secure field")
    case .none:
      // Accessibility had no answer, which every browser gives. Copy instead.
      Task { [weak self] in
        guard let self else { return }
        guard let copied = await textInsertion.copySelection(),
          !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          hudController.showMessage("No text selected")
          return
        }
        speak(selection: copied)
      }
    }
  }

  /// Speaks one selection, translated first when that is switched on.
  private func speak(selection text: String) {
    let voice = chosenVoice
    guard settings.readAloudTranslates,
      let target = voice.map({ Locale.Language(identifier: $0.language) })
        ?? Self.systemVoiceLanguage,
      let source = SelectionLanguage.detect(in: text),
      SelectionLanguage.needsTranslation(from: source, to: target)
    else {
      // Nothing to translate, nothing confident enough to translate, or it is
      // already the voice's language. Read it as it was written, which is what
      // Read Aloud did before this setting existed.
      speak(text, with: voice)
      return
    }

    speakTranslated(text, from: source, to: target, with: voice)
  }

  /// Speaks a selection in the voice's own language.
  ///
  /// The model is checked first. Read Aloud cannot install one, because Apple
  /// only installs from a View modifier and this gesture has no window, and
  /// reading Japanese aloud in an English voice is a worse answer than saying
  /// why nothing happened.
  private func speakTranslated(
    _ text: String,
    from source: Locale.Language,
    to target: Locale.Language,
    with voice: AVSpeechSynthesisVoice?
  ) {
    let pair = TranslationPair(source: source, target: target)
    Task { [weak self] in
      guard let self else { return }
      guard await translation.canTranslate(pair) else {
        hudController.showMessage("No \(Self.name(of: source)) to \(Self.name(of: target))")
        return
      }
      guard let translated = try? await translation.translate(text, with: pair) else {
        hudController.showMessage("Couldn't translate")
        return
      }
      speak(translated, with: voice)
    }
  }

  private func speak(_ text: String, with voice: AVSpeechSynthesisVoice?) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    synthesizer.speak(utterance)
  }

  private var chosenVoice: AVSpeechSynthesisVoice? {
    guard !settings.readAloudVoiceID.isEmpty else { return nil }
    return AVSpeechSynthesisVoice(identifier: settings.readAloudVoiceID)
  }

  /// The language the synthesizer speaks when no voice is chosen, so the
  /// target is known even then.
  private static var systemVoiceLanguage: Locale.Language? {
    Locale.Language(identifier: AVSpeechSynthesisVoice.currentLanguageCode())
  }

  private static func name(of language: Locale.Language) -> String {
    guard let code = language.languageCode?.identifier else { return "that" }
    return SpeechLanguageCatalog.shortName(for: Locale(identifier: code))
  }
}

extension ReadAloudController: AVSpeechSynthesizerDelegate {
  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didStart utterance: AVSpeechUtterance
  ) {
    Task { @MainActor [weak self] in
      self?.onSpeakingStateChange?(true)
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor [weak self] in
      self?.onSpeakingStateChange?(false)
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor [weak self] in
      self?.onSpeakingStateChange?(false)
    }
  }
}
