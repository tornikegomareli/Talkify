import SwiftUI

/// The Appearance section: the live preview first, then the Voice visual
/// and Motion and layout groups (CONTEXT.md). Waveform and Glow rows are
/// conditional on the selected visual; hidden values stay persisted.
struct AppearanceSettingsView: View {
  @Bindable var settings: AppSettings

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Which conditional rows the selected visual exposes; hidden values
  /// stay persisted (CONTEXT.md).
  static func showsWaveformOptions(for visual: HUDVoiceVisualStyle) -> Bool {
    visual == .waveform
  }

  static func showsGlowOptions(for visual: HUDVoiceVisualStyle) -> Bool {
    visual == .glow
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsPreviewCard(settings: settings)

      SettingsCard(title: "Voice visual") {
        SettingsPickerRow(
          title: "While listening",
          description: "The visual shown during Direct Dictation",
          options: HUDVoiceVisualStyle.allCases,
          optionLabel: { $0.rawValue },
          selection: $settings.voiceVisual
        )

        if Self.showsWaveformOptions(for: settings.voiceVisual) {
          SettingsPickerRow(
            title: "Waveform style",
            description: "The shape and motion of the waveform",
            options: HUDWaveformStyle.allCases,
            optionLabel: { $0.rawValue },
            selection: $settings.waveformStyle
          )
        }

        if Self.showsGlowOptions(for: settings.voiceVisual) {
          SettingsPickerRow(
            title: "Glow palette",
            description: "The colors used by the edge beam",
            options: HUDGlowPalette.allCases,
            optionLabel: { $0.rawValue },
            selection: $settings.glowPalette
          )

          SettingsPickerRow(
            title: "Glow center",
            description: "The visual inside the edge beam",
            options: HUDGlowCenterStyle.settingsCases,
            optionLabel: { $0.rawValue },
            selection: $settings.glowCenter
          )
        }
      }

      SettingsCard(title: "Motion and layout") {
        SettingsSliderRow(
          title: "HUD size",
          description: "How much room the HUD takes on screen",
          value: $settings.hudScale,
          range: Double(
            HUDMetrics.minimumScale(for: settings.voiceVisual, reduceMotion: reduceMotion)
          )...Double(HUDMetrics.maximumScale),
          valueLabel: { "\(Int(($0 * 100).rounded()))%" }
        )

        SettingsPickerRow(
          title: "Reveal style",
          description: "How the HUD appears when Direct Dictation starts",
          options: HUDRevealStyle.allCases,
          optionLabel: { $0.rawValue },
          selection: $settings.revealStyle
        )

        SettingsPickerRow(
          title: "Long draft behavior",
          description: "How the HUD handles longer dictated text",
          options: HUDLongDraftStyle.allCases,
          optionLabel: { $0.rawValue },
          selection: $settings.longDraftStyle
        )

        SettingsPickerRow(
          title: "Draft after release",
          description: "Insert the text immediately, or hold it in the HUD for editing before Return",
          options: HUDDraftStyle.allCases,
          optionLabel: { $0.rawValue },
          selection: $settings.draftStyle
        )
      }
    }
  }
}
