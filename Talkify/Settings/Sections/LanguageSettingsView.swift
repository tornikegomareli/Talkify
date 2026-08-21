import SwiftUI

/// The Language section: the dictation language, an optional second language,
/// and the trigger that dictates in it. Two triggers rather than automatic
/// detection — Apple Speech transcribes one language per session, and a wrong guess
/// produces confident nonsense rather than an error (CONTEXT.md).
struct LanguageSettingsView: View {
  @State private var isRecordingSecondKey = false
  @Bindable var settings: AppSettings
  let runtimeState: SettingsRuntimeState

  @Environment(\.colorSchemeContrast) private var contrast
  @State private var languages: [SpeechLanguage] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(title: "Languages") {
        SettingsPickerRow(
          title: "Dictation language",
          description: "The language the primary trigger transcribes",
          options: [""] + languages.map(\.id),
          optionLabel: label(for:),
          selection: $settings.recognitionLocaleIdentifier,
          controlWidth: 260
        )

        SettingsPickerRow(
          title: "Second language",
          description: settings.isSecondLanguageEnabled
            ? "Its own trigger, so you never switch a setting to switch language"
            : "Off. Choose one to dictate in two languages",
          options: [""] + secondaryOptions,
          optionLabel: secondaryLabel(for:),
          selection: $settings.secondaryRecognitionLocaleIdentifier,
          controlWidth: 260
        )

        if settings.isSecondLanguageEnabled {
          SettingsRow(
            title: "Second language trigger",
            description: secondaryTriggerDescription
          ) {
            KeyRecorderView(
              keyBinding: $settings.secondaryTriggerBinding,
              isRecording: $isRecordingSecondKey,
              allowsBareModifier: true,
              allowsMouseButton: true,
              onRecordingChanged: { settings.isRecordingKeybind = $0 }
            )
          }
        }

        SettingsPickerRow(
          title: "Translate into",
          description: translationDescription,
          options: [""] + runtimeState.translationTargets.map(\.id),
          optionLabel: translationLabel(for:),
          selection: $settings.translationTargetIdentifier,
          controlWidth: 260
        )

        if let action = translationModelAction {
          SettingsRow(title: action.title, description: action.description) {
            if runtimeState.translationModelState == .downloading {
              ProgressView().controlSize(.small)
            } else {
              Button(action.button) { downloadTranslationModel() }
                .buttonStyle(SettingsButtonStyle())
            }
          }
        }

        // A model download can take minutes. Naming the language and its
        // progress is what separates "working" from "stuck".
        ForEach(downloads, id: \.name) { download in
          SettingsRow(
            title: "Downloading \(download.name)",
            description: "The model is downloading now. You can keep using "
              + "your other language while it finishes."
          ) {
            HStack(spacing: 8) {
              ProgressView(value: download.fraction)
                .progressViewStyle(.linear)
                .frame(width: 120)
              Text("\(Int(download.fraction * 100))%")
                .font(.system(size: 12, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
            }
          }
        }
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(
          "Both languages stay loaded, so either key answers as fast as the "
            + "other. A language that is not installed yet downloads its model "
            + "the first time you use it, which takes a moment; after that it "
            + "runs on device like the rest."
        )
        .font(.caption)
        .foregroundStyle(.white.opacity(contrast == .increased ? 0.7 : 0.45))
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 6)
    }
    .task {
      languages = await SpeechLanguageCatalog.available()
    }
  }

  /// The first language is not offered as the second: picking it would show the
  /// key row for a language that is already covered, and the key would do
  /// nothing new.
  private var secondaryOptions: [String] {
    languages
      .map(\.id)
      .filter { $0 != settings.recognitionLocaleIdentifier }
  }

  /// Downloads in flight, named for the reader. Sorted by name so the rows
  /// do not reorder while progress changes.
  private var downloads: [(name: String, fraction: Double)] {
    runtimeState.languageDownloads
      .map { identifier, fraction in
        let name = languages.first { $0.id == identifier }?.name ?? identifier
        return (name: name, fraction: fraction)
      }
      .sorted { $0.name < $1.name }
  }

  private func label(for identifier: String) -> String {
    guard !identifier.isEmpty else { return "Automatic (\(automaticName))" }
    guard let language = languages.first(where: { $0.id == identifier }) else {
      return identifier
    }
    return language.isInstalled
      ? language.name
      : "\(language.name) — downloads on first use"
  }

  private func secondaryLabel(for identifier: String) -> String {
    identifier.isEmpty ? "Off" : label(for: identifier)
  }

  /// What "Automatic" resolves to, named rather than left abstract: the Mac's
  /// own language when Apple Speech supports it.
  private var automaticName: String {
    let current = Locale.current.language.languageCode?.identifier
    let match = languages.first {
      $0.locale.language.languageCode?.identifier == current
    }
    return match?.name ?? "English"
  }

  private var secondaryName: String {
    languages
      .first { $0.id == settings.secondaryRecognitionLocaleIdentifier }?
      .name ?? "the second language"
  }

  private var translationDescription: String {
    guard settings.isTranslationEnabled else {
      return "Off. Choose a language and the Translate shortcut speaks in "
        + "yours and inserts it in that one"
    }
    return "The Translate shortcut speaks in your dictation language and "
      + "inserts it in this one"
  }

  private func translationLabel(for identifier: String) -> String {
    guard !identifier.isEmpty else { return "Off" }
    guard let target = runtimeState.translationTargets.first(where: { $0.id == identifier })
    else {
      // A stored pick this source cannot reach. Kept visible rather than
      // silently dropped: it is still the user's choice.
      return SpeechLanguageCatalog.shortName(for: Locale(identifier: identifier))
        + " — not available from your dictation language"
    }
    return target.label
  }

  /// The row under the picker, when the chosen model needs saying something
  /// about. Nothing to say when it is ready.
  private var translationModelAction: (title: String, description: String, button: String)? {
    guard settings.isTranslationEnabled else { return nil }
    let name = SpeechLanguageCatalog.shortName(
      for: Locale(identifier: settings.translationTargetIdentifier)
    )
    switch runtimeState.translationModelState {
    case .ready, .none:
      return nil
    case .needsDownload:
      return (
        "Download the \(name) model",
        "Talkify fetches it the first time you use Translate. You can start "
          + "it now instead.",
        "Download"
      )
    case .downloading:
      return (
        "Downloading the \(name) model",
        "Apple does not report how far along it is, so this stays until it "
          + "finishes. Dictation keeps working while it runs.",
        ""
      )
    case .failed:
      return (
        "\(name) could not be prepared",
        "Translate will keep trying. Dictation is unaffected.",
        "Try Again"
      )
    }
  }

  private func downloadTranslationModel() {
    runtimeState.prepareTranslationModel()
  }

  private var secondaryTriggerDescription: String {
    let binding = settings.secondaryTriggerBinding
    var description = "Hold it to dictate in \(secondaryName), or tap it to start and tap again to finish"
    if binding.isMouseButton {
      description += ". This button keeps its usual action unless that exact "
        + "combination is pressed"
    }
    if let other = settings.roleUsing(binding, excluding: .secondLanguage) {
      description += ". Also used by \(other.title)"
    }
    return description
  }
}
