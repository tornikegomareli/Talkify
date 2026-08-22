import SwiftUI

/// The Language section: the dictation language, an optional second language,
/// and the trigger that dictates in it. Two triggers rather than automatic
/// detection — Apple Speech transcribes one language per session, and a wrong guess
/// produces confident nonsense rather than an error (CONTEXT.md).
struct LanguageSettingsView: View {
  /// Said before the sheet appears, because the sheet is Apple's and it lists
  /// the dictation language too, which reads as a mistake until explained.
  private static let downloadExplanation =
    "macOS may also ask for your dictation language. Translation models are "
    + "separate from dictation ones."

  @State private var isRecordingSecondKey = false
  @Bindable var settings: AppSettings
  let runtimeState: SettingsRuntimeState

  @Environment(\.colorSchemeContrast) private var contrast
  @State private var languages: [SpeechLanguage] = []
  /// The target the user picked that needs a download, while they decide. The
  /// only piece of this flow that is genuinely this view's: an install has to
  /// outlive the section being switched, so it lives in the runtime state.
  @State private var confirmingTarget: TranslationTarget?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(title: "Languages") {
        SettingsPickerRow(
          title: "Dictation language",
          description: "What the main trigger transcribes",
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
          options: translationOptions,
          optionLabel: translationLabel(for:),
          selection: confirmedTarget,
          controlWidth: 260
        )

        installRow

        // A model download can take minutes. Naming the language and its
        // progress is what separates "working" from "stuck".
        ForEach(downloads, id: \.name) { download in
          SettingsRow(
            title: "Downloading \(download.name)",
            description: "You can keep using your other language."
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
          "Both languages stay loaded, so either key answers as fast. "
            + "Everything runs on device."
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
    .confirmationDialog(
      "Download \(confirmingTarget?.name ?? "") to translate into it?",
      isPresented: isConfirmingDownload,
      presenting: confirmingTarget
    ) { target in
      Button("Download") { install(target) }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text(Self.downloadExplanation)
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
      return "Off. Choose one and the Translate key inserts it"
    }
    return "Speak your language, insert this one"
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

  /// The picker's selection, which only commits a language this Mac can
  /// already translate into. Choosing one that needs a model asks first
  /// instead, so the setting never names a language Translate cannot use.
  private var confirmedTarget: Binding<String> {
    Binding(
      get: { settings.translationTargetIdentifier },
      set: { picked in
        runtimeState.translationInstallFailure = nil
        let target = runtimeState.translationTargets.first { $0.id == picked }
        guard let target, target.availability == .downloadable else {
          confirmingTarget = nil
          settings.translationTargetIdentifier = picked
          return
        }
        confirmingTarget = target
      }
    )
  }

  private var isConfirmingDownload: Binding<Bool> {
    Binding(
      get: { confirmingTarget != nil },
      set: { isPresented in
        if !isPresented { confirmingTarget = nil }
      }
    )
  }

  /// The row under the picker while an install is in flight, or left over from
  /// one that never finished.
  @ViewBuilder
  private var installRow: some View {
    if let pair = runtimeState.installingTranslationPair {
      SettingsRow(
        title: "Getting the \(name(of: pair.target)) model",
        description: "Downloading in the background. Dictation keeps working."
      ) {
        installingControl
      }
    } else if let name = runtimeState.translationInstallFailure {
      SettingsRow(
        title: "\(name) did not finish downloading",
        description: "Pick it again to retry."
      ) {
        Button("Dismiss") { runtimeState.translationInstallFailure = nil }
          .buttonStyle(SettingsButtonStyle())
      }
    } else if let target = chosenTarget, let problem = modelProblem {
      SettingsRow(title: "\(target.name) \(problem.title)", description: problem.detail) {
        Button(problem.button) { install(target) }
          .buttonStyle(SettingsButtonStyle())
      }
    }
  }

  /// Every target, plus a stored pick this source cannot reach.
  ///
  /// Without that last one the picker holds a selection with no matching tag
  /// and shows nothing at all, which is worse than saying the language is
  /// unavailable: the translate key stays bound and stays useless.
  private var translationOptions: [String] {
    var options = [""] + runtimeState.translationTargets.map(\.id)
    let stored = settings.translationTargetIdentifier
    if !stored.isEmpty, !options.contains(stored) {
      options.append(stored)
    }
    return options
  }

  private var chosenTarget: TranslationTarget? {
    runtimeState.translationTargets.first {
      $0.id == settings.translationTargetIdentifier
    }
  }

  /// What is wrong with the chosen model, when anything is.
  ///
  /// `needsDownload` is only reachable when the app was quit mid-download,
  /// because the picker otherwise never commits a language whose model is
  /// missing. `failed` is a model this Mac has that will not load.
  private var modelProblem: (title: String, detail: String, button: String)? {
    switch runtimeState.translationModelState {
    case .needsDownload:
      ("still needs its model", "Translate cannot run until it downloads.", "Download")
    case .failed:
      ("could not be prepared", "Translate cannot run until it loads.", "Try Again")
    case .none, .ready, .downloading:
      nil
    }
  }

  /// The bar and the way out of it. Apple reports nothing when its download
  /// sheet is dismissed without downloading, so a wait has to be abandonable
  /// by hand — which also covers a download that stalls or a network that dies.
  private var installingControl: some View {
    HStack(spacing: 10) {
      ProgressView().progressViewStyle(.linear).frame(width: 120)
      Button("Stop") { runtimeState.stopInstallingTranslationModel() }
        .buttonStyle(SettingsButtonStyle())
    }
  }

  private func name(of language: Locale.Language) -> String {
    guard let code = language.languageCode?.identifier else { return "" }
    return SpeechLanguageCatalog.shortName(for: Locale(identifier: code))
  }

  /// Commits the pick, presents Apple's sheet, and waits for the model.
  ///
  /// The commit is optimistic so the picker reads as the user's choice while
  /// the download runs, and reverted if the model never arrives.
  private func install(_ target: TranslationTarget) {
    guard let source = runtimeState.translationSource else { return }
    let previous = settings.translationTargetIdentifier
    settings.translationTargetIdentifier = target.id
    let pair = TranslationPair(
      source: source,
      target: Locale.Language(identifier: target.id)
    )
    confirmingTarget = nil
    runtimeState.installingTranslationPair = pair

    Task {
      // A cancelled wait reports not-ready, so abandoning it lands on the
      // same revert as a model that never arrived.
      let outcome = await runtimeState.installTranslationModel(pair)
      // Read after the wait, not before it: a pick made while this ran owns
      // the state by now, and may already be installing something of its own.
      if runtimeState.installingTranslationPair == pair {
        runtimeState.installingTranslationPair = nil
      }
      switch outcome {
      case .installed, .superseded:
        // Superseded is not a failure. The dictation language can change under
        // an install while the target the user chose stays exactly as it is,
        // and reverting there would turn Translate off behind their back.
        break
      case .unavailable:
        // Checked against the stored pick, which outlives this view: leaving
        // the Language section replaces it, and fresh state would let a wait
        // that started ten minutes ago revert a language chosen since.
        guard settings.translationTargetIdentifier == target.id else { return }
        settings.translationTargetIdentifier = previous
        runtimeState.translationInstallFailure = target.name
      }
    }
  }

  private var secondaryTriggerDescription: String {
    let binding = settings.secondaryTriggerBinding
    var description = "Hold it to dictate in \(secondaryName), or tap it to start and tap again to finish"
    if binding.isMouseButton {
      description += ". Keeps its usual action unless that exact combination "
        + "is pressed"
    }
    if let other = settings.roleUsing(binding, excluding: .secondLanguage) {
      description += ". Also used by \(other.title)"
    }
    return description
  }
}
