import SwiftUI

/// The Updates section: the running version, a manual check, and the two
/// automatic behaviours. Sparkle owns the update UI itself, so this pane only
/// states what is true and gets out of the way.
struct UpdatesSettingsView: View {
  let updater: SparkleUpdaterService

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(title: "Version") {
        SettingsRow(
          title: "Talkify \(Self.version)",
          description: updater.availableVersion.map { "Version \($0) is available." }
            ?? lastCheckedDescription
        ) {
          Button("Check Now") {
            updater.checkForUpdates()
          }
          .buttonStyle(SettingsButtonStyle())
          .disabled(!updater.canCheckForUpdates)
        }
      }

      SettingsCard(title: "Automatic") {
        SettingsRow(
          title: "Check for updates automatically",
          description: "Once a day, in the background"
        ) {
          Toggle("", isOn: automaticChecks)
            .labelsHidden()
            .toggleStyle(.switch)
        }

        SettingsRow(
          title: "Download updates automatically",
          description: "Fetch the update in advance. Installing still waits "
            + "for you, and never interrupts a dictation session."
        ) {
          Toggle("", isOn: automaticDownloads)
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!updater.automaticallyChecksForUpdates)
        }
      }

      Text(
        "Updates are downloaded from GitHub and verified with an EdDSA "
          + "signature before they are installed. An update that fails "
          + "verification is discarded."
      )
      .font(.caption)
      .foregroundStyle(.white.opacity(contrast == .increased ? 0.7 : 0.45))
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 6)
    }
  }

  private var lastCheckedDescription: String {
    guard let date = updater.lastCheckedAt else {
      return "Talkify has not checked for updates yet."
    }
    return "Last checked \(date.formatted(.relative(presentation: .named)))."
  }

  private var automaticChecks: Binding<Bool> {
    Binding(
      get: { updater.automaticallyChecksForUpdates },
      set: { updater.automaticallyChecksForUpdates = $0 }
    )
  }

  private var automaticDownloads: Binding<Bool> {
    Binding(
      get: { updater.automaticallyDownloadsUpdates },
      set: { updater.automaticallyDownloadsUpdates = $0 }
    )
  }

  static var version: String {
    let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    return "\(short) (\(build))"
  }
}
