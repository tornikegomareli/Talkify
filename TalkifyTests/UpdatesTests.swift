import Foundation
import Testing
@testable import Talkify

@MainActor
struct UpdatesTests {
  /// The updater is inert until `start()`, which the composition root calls
  /// last. A preview or a test must never reach the network by constructing it.
  @Test func anUnstartedUpdaterCannotCheck() {
    let updater = SparkleUpdaterService()
    #expect(!updater.canCheckForUpdates)
    #expect(updater.availableVersion == nil)
    #expect(updater.lastCheckedAt == nil)
  }

  @Test func theUpdatesSectionIsRegistered() {
    #expect(SettingsSection.allCases.contains(.updates))
    #expect(SettingsSection.updates.title == "Updates")
    #expect(!SettingsSection.updates.icon.isEmpty)
  }

  /// Sparkle is the one third-party dependency and it stays behind
  /// `Talkify/Updates/` (CLAUDE.md). This fails the moment another file imports
  /// it, which is the point: the rule is only real if something checks.
  @Test func onlyTheUpdatesModuleImportsSparkle() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "Talkify")

    let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
      .compactMap { $0 as? URL }
      .filter { $0.pathExtension == "swift" } ?? []
    #expect(!files.isEmpty, "no Swift sources found under \(root.path)")

    let importers = try files
      .filter { url in
        try String(contentsOf: url, encoding: .utf8)
          .split(separator: "\n")
          .contains { $0.trimmingCharacters(in: .whitespaces) == "import Sparkle" }
      }
      .map { $0.lastPathComponent }
      .sorted()

    #expect(importers == ["SparkleUpdaterService.swift"])
  }

  /// The feed Sparkle polls has to parse and name the app, even before the
  /// first release adds an item: a missing or broken file reports a failed
  /// check instead of "you're up to date".
  @Test func theCommittedAppcastParses() throws {
    let appcast = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appending(path: "appcast.xml")

    let xml = try String(contentsOf: appcast, encoding: .utf8)
    #expect(xml.contains("<title>Talkify</title>"))
    #expect(try XMLDocument(contentsOf: appcast, options: []).rootElement()?.name == "rss")
  }
}
