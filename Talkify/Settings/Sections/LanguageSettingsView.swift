import SwiftUI

/// The Language section: the dictation language, an optional second language,
/// and the key that dictates in it. Two keys rather than automatic detection —
/// Apple Speech transcribes one language per session, and a wrong guess
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
          description: "The language the trigger key transcribes",
          options: [""] + languages.map(\.id),
          optionLabel: label(for:),
          selection: $settings.recognitionLocaleIdentifier,
          controlWidth: 260
        )

        SettingsPickerRow(
          title: "Second language",
          description: settings.isSecondLanguageEnabled
            ? "Its own key, so you never switch a setting to switch language"
            : "Off. Choose one to dictate in two languages",
          options: [""] + secondaryOptions,
          optionLabel: secondaryLabel(for:),
          selection: $settings.secondaryRecognitionLocaleIdentifier,
          controlWidth: 260
        )

        if settings.isSecondLanguageEnabled {
          SettingsRow(
            title: "Second language key",
            description: "Hold it to dictate in \(secondaryName)"
          ) {
            KeyRecorderView(
              keyBinding: $settings.secondaryTriggerBinding,
              isRecording: $isRecordingSecondKey,
              allowsBareModifier: true,
              onRecordingChanged: { settings.isRecordingKeybind = $0 }
            )
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
}
