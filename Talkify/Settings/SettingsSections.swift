/// The Settings navigation model: labeled groups of sections with stable
/// typed IDs (CONTEXT.md: sections are registered in code; no empty or
/// disabled sections render).
enum SettingsSectionGroup: String, CaseIterable, Identifiable {
  case settings

  var id: Self { self }
  var title: String { rawValue.uppercased() }

  var sections: [SettingsSection] {
    SettingsSection.allCases.filter { $0.group == self }
  }
}

enum SettingsSection: String, CaseIterable, Identifiable {
  case general
  case appearance
  case sounds
  case dictation
  case promptShaping
  case dropTranscription
  case readAloud
  case language
  case shortcuts
  case updates
  case insights

  var id: Self { self }
  var group: SettingsSectionGroup { .settings }

  var title: String {
    switch self {
    case .general: "General"
    case .appearance: "Appearance"
    case .sounds: "Sounds"
    case .dictation: "Dictation"
    case .promptShaping: "Prompt Shaping"
    case .dropTranscription: "Drop Transcription"
    case .readAloud: "Read Aloud"
    case .language: "Language"
    case .shortcuts: "Shortcuts"
    case .updates: "Updates"
    case .insights: "Insights"
    }
  }

  var subtitle: String {
    switch self {
    case .general: "Choose how Talkify starts"
    case .appearance: "Customize the Direct Dictation HUD"
    case .sounds: "Choose and preview the session sounds"
    case .dictation: "Choose where finished dictation text goes"
    case .promptShaping: "Rewrite what you dictate, on device"
    case .dropTranscription: "Transcribe audio and video files"
    case .readAloud: "Choose the voice that reads selected text"
    case .language: "Choose your languages"
    case .shortcuts: "Rebind Direct Dictation triggers and Read Aloud"
    case .updates: "Keep Talkify current"
    case .insights: "Review your local Direct Dictation activity"
    }
  }

  var icon: String {
    switch self {
    case .general: "gearshape"
    case .appearance: "sparkles"
    case .sounds: "waveform"
    case .dictation: "text.cursor"
    case .promptShaping: "wand.and.sparkles"
    case .dropTranscription: "square.and.arrow.down"
    case .readAloud: "speaker.wave.2"
    case .language: "globe"
    case .shortcuts: "keyboard"
    case .updates: "arrow.down.circle"
    case .insights: "chart.bar.xaxis"
    }
  }
}
