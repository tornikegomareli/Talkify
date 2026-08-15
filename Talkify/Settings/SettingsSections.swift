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
  case appearance
  case sounds
  case readAloud
  case language
  case vocabulary
  case shortcuts
  case updates
  case insights

  var id: Self { self }
  var group: SettingsSectionGroup { .settings }

  var title: String {
    switch self {
    case .appearance: "Appearance"
    case .sounds: "Sounds"
    case .readAloud: "Read Aloud"
    case .language: "Language"
    case .vocabulary: "Vocabulary"
    case .shortcuts: "Shortcuts"
    case .updates: "Updates"
    case .insights: "Insights"
    }
  }

  var subtitle: String {
    switch self {
    case .appearance: "Customize the Direct Dictation HUD"
    case .sounds: "Choose and preview Direct Dictation sounds"
    case .readAloud: "Choose the voice that reads selected text"
    case .language: "Pick your dictation languages and their keys"
    case .vocabulary: "Teach Talkify the words it keeps getting wrong"
    case .shortcuts: "Rebind the Direct Dictation and Read Aloud keys"
    case .updates: "Keep Talkify current"
    case .insights: "Review your local Direct Dictation activity"
    }
  }

  var icon: String {
    switch self {
    case .appearance: "sparkles"
    case .sounds: "waveform"
    case .readAloud: "speaker.wave.2"
    case .language: "globe"
    case .vocabulary: "character.book.closed"
    case .shortcuts: "keyboard"
    case .updates: "arrow.down.circle"
    case .insights: "chart.bar.xaxis"
    }
  }
}
