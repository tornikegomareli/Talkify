import SwiftUI

/// The fixed Settings surface: header, sidebar navigation, and the selected
/// section's scrolling pane. Preferences persist through AppSettings, active
/// sessions keep their snapshot, and Insights reads aggregate usage.
struct SettingsView: View {
  @Bindable var settings: AppSettings
  let sounds: HUDSounds
  let runtimeState: SettingsRuntimeState
  let usageTracker: UsageTracker
  let updater: SparkleUpdaterService
  let onClose: () -> Void

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var selectedSection: SettingsSection = .appearance

  var body: some View {
    VStack(spacing: 0) {
      SettingsHeader(onClose: onClose)

      if runtimeState.isDictating && selectedSection != .insights {
        ActiveSessionNotice()
      }

      HStack(spacing: 0) {
        SettingsSidebar(selectedSection: $selectedSection)

        Rectangle()
          .fill(.white.opacity(contrast == .increased ? 0.18 : 0.08))
          .frame(width: 1)

        ZStack(alignment: .topLeading) {
          SettingsContent(
            section: selectedSection,
            settings: settings,
            sounds: sounds,
            usageTracker: usageTracker,
            runtimeState: runtimeState,
            updater: updater
          )
          .id(selectedSection)
          .transition(.opacity)
        }
        .animation(
          reduceMotion ? nil : .easeOut(duration: 0.14),
          value: selectedSection
        )
      }
    }
    .frame(width: 860, height: 600)
    .background {
      ZStack {
        SettingsTheme.background
        LinearGradient(
          colors: [.white.opacity(0.035), .clear, .black.opacity(0.12)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(.white.opacity(contrast == .increased ? 0.24 : 0.1), lineWidth: 1)
    }
    .tint(SettingsTheme.accent)
    .preferredColorScheme(.dark)
    .onExitCommand(perform: onClose)
  }
}

private struct SettingsHeader: View {
  let onClose: () -> Void

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    ZStack {
      // Close sits on the leading edge, where native macOS windows
      // keep their window controls.
      HStack {
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(contrast == .increased ? 0.92 : 0.7))
            .frame(width: 28, height: 28)
            .background(.white.opacity(0.07), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        Spacer()
      }

      // Talkify identity, dead-center regardless of the close button.
      HStack(spacing: 9) {
        Image("MenuBarIcon")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 15, height: 15)
          .foregroundStyle(.white.opacity(0.92))
          .frame(width: 26, height: 26)
          .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))

        Text("Talkify")
          .font(.system(size: 15, weight: .semibold, design: .rounded))
      }
    }
    .padding(.horizontal, 16)
    .frame(height: 56)
    .background(SettingsWindowDragHandle())
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.white.opacity(contrast == .increased ? 0.18 : 0.08))
        .frame(height: 1)
    }
  }
}

private struct ActiveSessionNotice: View {
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "info.circle.fill")
        .foregroundStyle(SettingsTheme.accent)
      Text("Changes apply to the next Direct Dictation session.")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(contrast == .increased ? 0.92 : 0.72))
      Spacer()
    }
    .padding(.horizontal, 18)
    .frame(height: 36)
    .background(SettingsTheme.accent.opacity(0.08))
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(SettingsTheme.accent.opacity(contrast == .increased ? 0.35 : 0.18))
        .frame(height: 1)
    }
  }
}

private struct SettingsSidebar: View {
  @Binding var selectedSection: SettingsSection

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      ForEach(SettingsSectionGroup.allCases) { group in
        SettingsSidebarGroup(title: group.title) {
          ForEach(group.sections) { section in
            Button {
              withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                selectedSection = section
              }
            } label: {
              Label(section.title, systemImage: section.icon)
                .labelStyle(SettingsSidebarLabelStyle())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                  selectedSection == section
                    ? .white
                    : .white.opacity(contrast == .increased ? 0.82 : 0.62)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background {
                  if selectedSection == section {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                      .fill(.white.opacity(contrast == .increased ? 0.15 : 0.09))
                      .overlay(alignment: .leading) {
                        Capsule()
                          .fill(SettingsTheme.accent)
                          .frame(width: 2)
                          .padding(.vertical, 7)
                      }
                  }
                }
            }
            .buttonStyle(.plain)
          }
        }
      }

      Spacer()
    }
    .padding(.top, 20)
    .frame(width: 190)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .background(SettingsTheme.sidebar)
  }
}

private struct SettingsSidebarGroup<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.8)
        .foregroundStyle(.white.opacity(contrast == .increased ? 0.62 : 0.35))
        .padding(.horizontal, 18)

      VStack(spacing: 2) {
        content
      }
      .padding(.horizontal, 10)
    }
  }
}

private struct SettingsContent: View {
  let section: SettingsSection
  @Bindable var settings: AppSettings
  let sounds: HUDSounds
  let usageTracker: UsageTracker
  let runtimeState: SettingsRuntimeState
  let updater: SparkleUpdaterService

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 6) {
          Text(section.title)
            .font(.system(size: 26, weight: .semibold, design: .rounded))
          Text(section.subtitle)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(contrast == .increased ? 0.76 : 0.52))
        }

        switch section {
        case .appearance:
          AppearanceSettingsView(settings: settings)
        case .sounds:
          SoundsSettingsView(settings: settings, sounds: sounds)
        case .dropTranscription:
          DropTranscriptionSettingsView(settings: settings)
        case .readAloud:
          ReadAloudSettingsView(settings: settings)
        case .language:
          LanguageSettingsView(settings: settings, runtimeState: runtimeState)
        case .shortcuts:
          ShortcutsSettingsView(settings: settings)
        case .updates:
          UpdatesSettingsView(updater: updater)
        case .insights:
          InsightsSettingsView(tracker: usageTracker)
        }
      }
      .frame(maxWidth: 620, alignment: .leading)
      .padding(.horizontal, 34)
      .padding(.vertical, 30)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

#Preview {
  let settings = AppSettings.previewStore()
  SettingsView(
    settings: settings,
    sounds: HUDSounds(),
    runtimeState: SettingsRuntimeState(),
    usageTracker: UsageTracker(store: UsageStore(
      fileURL: FileManager.default.temporaryDirectory
        .appending(path: "TalkifySettingsPreview-usage.json")
    )),
    // Never started, so the preview shows the pane's disabled state rather
    // than reaching for the network.
    updater: SparkleUpdaterService(),
    onClose: {}
  )
}
