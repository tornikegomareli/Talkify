import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Drop Transcription preview: the same HUD surface the feature uses,
/// walking its four states on a loop against the same simulated display the
/// Appearance preview uses.
///
/// It runs the states rather than posing one, because the states are the
/// feature — a still picture of the open target says nothing about the notch
/// growing, the file landing in it, or the card coming back. Accent and HUD
/// size follow the live preferences, so a palette change shows here at once.
struct DropPreviewCard: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let settings: AppSettings

  @State private var drop = DropHUDContent()

  private static let fileName = "Interview.m4a"

  var body: some View {
    SettingsPreviewStage(
      title: "Live preview",
      subtitle: "The notch taking a file and handing back a transcript"
    ) {
      DropHUDView(
        screen: HUDPreviewScreen.notched,
        settings: settings.sessionSettings,
        drop: drop,
        acceptsDrops: false
      )
    }
    .task(id: reduceMotion) {
      await runLoop()
    }
  }

  /// One pass of the gesture, repeated: approach, open, take the file, hand
  /// back the card, close. Reduce Motion holds the open target instead —
  /// a surface that changes on its own every second is the thing Reduce Motion
  /// exists to stop.
  private func runLoop() async {
    drop.fileName = Self.fileName
    drop.heldIcon = NSWorkspace.shared.icon(for: .mpeg4Audio)

    guard !reduceMotion else {
      drop.mode = .armed
      drop.isOpen = true
      drop.isRevealed = true
      return
    }

    while !Task.isCancelled {
      drop.mode = .armed
      drop.isOpen = false
      drop.isRevealed = true
      guard await pause(.milliseconds(900)) else { return }

      drop.isOpen = true
      guard await pause(.milliseconds(1600)) else { return }

      drop.mode = .held
      guard await pause(.milliseconds(1400)) else { return }

      drop.mode = .transcript
      drop.transcript = DropHUDContent.Transcript(
        url: URL(filePath: "/Interview.txt"),
        text: "",
        wordCount: 1240,
        duration: 723
      )
      drop.remainingFraction = 1
      guard await pause(.milliseconds(2200)) else { return }

      drop.isRevealed = false
      guard await pause(.milliseconds(700)) else { return }
      drop.mode = .none
      drop.transcript = nil
      guard await pause(.milliseconds(500)) else { return }
    }
  }

  /// Sleeps, and reports whether the loop should keep going.
  private func pause(_ duration: Duration) async -> Bool {
    try? await Task.sleep(for: duration)
    return !Task.isCancelled
  }
}
