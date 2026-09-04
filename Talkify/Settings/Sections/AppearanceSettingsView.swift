import SwiftUI

/// The Appearance section: the live preview first, then the Voice visual
/// and Motion and layout groups (CONTEXT.md). Waveform, palette, and glow
/// center rows are conditional on the selected visual; hidden values stay
/// persisted.
struct AppearanceSettingsView: View {
  @Bindable var settings: AppSettings

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Which conditional rows the selected visual exposes; hidden values
  /// stay persisted (CONTEXT.md). Waveform + Draft is a designed Chart
  /// Line, so it does not offer the concert style picker. It takes the
  /// glow palette (beam, shaping caption, status ghost) but not a center.
  static func showsWaveformOptions(for visual: HUDVoiceVisualStyle) -> Bool {
    visual == .waveform
  }

  static func showsGlowPalette(for visual: HUDVoiceVisualStyle) -> Bool {
    visual.usesEdgeGlow
  }

  static func showsGlowCenter(for visual: HUDVoiceVisualStyle) -> Bool {
    visual == .glow
  }

  static func showsWaveDraftRibbon(for visual: HUDVoiceVisualStyle) -> Bool {
    visual == .waveDraft
  }

  /// Waveform + Draft uses a recent-word line instead of the global long
  /// draft behaviors. Reduce Motion restores the plain band, where the
  /// existing pick still applies.
  static func showsLongDraftBehavior(
    for visual: HUDVoiceVisualStyle,
    reduceMotion: Bool
  ) -> Bool {
    !(visual == .waveDraft && !reduceMotion)
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

        if Self.showsGlowPalette(for: settings.voiceVisual) {
          SettingsPickerRow(
            title: "Glow palette",
            description: "The colors used by the edge beam",
            options: HUDGlowPalette.allCases,
            optionLabel: { $0.rawValue },
            selection: $settings.glowPalette
          )
        }

        if Self.showsGlowCenter(for: settings.voiceVisual) {
          SettingsPickerRow(
            title: "Glow center",
            description: "The visual inside the edge beam",
            options: HUDGlowCenterStyle.settingsCases,
            optionLabel: { $0.rawValue },
            selection: $settings.glowCenter
          )
        }

        if Self.showsWaveDraftRibbon(for: settings.voiceVisual) {
          SettingsRow(
            title: "Chart Line ribbon",
            description: "The slim waveform under the housing. Off leaves "
              + "the live draft and the glow."
          ) {
            Toggle("Chart Line ribbon", isOn: $settings.waveDraftShowsRibbon)
              .labelsHidden()
              .toggleStyle(.switch)
          }
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

        SettingsRow(
          title: "Clear the menu bar on other displays",
          description: "A display with no notch has nothing to hug, so the "
            + "shape sits where a notch would be. Turn this on if it covers "
            + "your menu bar icons."
        ) {
          Toggle("Clear the menu bar on other displays", isOn: $settings.hudClearsMenuBar)
            .labelsHidden()
            .toggleStyle(.switch)
        }

        SettingsPickerRow(
          title: "Reveal style",
          description: "How the HUD appears when Direct Dictation starts",
          options: HUDRevealStyle.allCases,
          optionLabel: { $0.rawValue },
          selection: $settings.revealStyle
        )

        if Self.showsLongDraftBehavior(
          for: settings.voiceVisual,
          reduceMotion: reduceMotion
        ) {
          SettingsPickerRow(
            title: "Long draft behavior",
            description: "How the HUD handles longer dictated text",
            options: HUDLongDraftStyle.allCases,
            optionLabel: { $0.rawValue },
            selection: $settings.longDraftStyle
          )
        }
      }
    }
  }
}
