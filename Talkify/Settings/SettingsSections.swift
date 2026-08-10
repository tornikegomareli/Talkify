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
  case shortcuts
  case insights

  var id: Self { self }
  var group: SettingsSectionGroup { .settings }

  var title: String {
    switch self {
    case .appearance: "Appearance"
    case .sounds: "Sounds"
    case .readAloud: "Read Aloud"
    case .shortcuts: "Shortcuts"
    case .insights: "Insights"
    }
  }

  var subtitle: String {
    switch self {
    case .appearance: "Customize the Direct Dictation HUD"
    case .sounds: "Choose and preview Direct Dictation sounds"
    case .readAloud: "Choose the voice that reads selected text"
    case .shortcuts: "Rebind the Direct Dictation and Read Aloud keys"
    case .insights: "Review your local Direct Dictation activity"
    }
  }

  var icon: String {
    switch self {
    case .appearance: "sparkles"
    case .sounds: "waveform"
    case .readAloud: "speaker.wave.2"
    case .shortcuts: "keyboard"
    case .insights: "chart.bar.xaxis"
    }
  }
}
