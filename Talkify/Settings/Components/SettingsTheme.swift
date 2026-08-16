import AppKit
import SwiftUI

/// The Settings surface's dark palette — the design tokens every Settings
/// component and the Insights section draw from. The accent is Talkify blue
/// (CONTEXT.md: Settings navigation uses a fixed accent; Glow palettes never
/// recolor the shell).
enum SettingsTheme {
  static let background = Color(red: 0.025, green: 0.027, blue: 0.035)
  static let sidebar = Color(red: 0.035, green: 0.038, blue: 0.049)
  static let card = Color(red: 0.065, green: 0.069, blue: 0.087)
  static let accent = Color(nsColor: accentColor)
  /// The same blue for the places that draw into an `NSImage` rather than into
  /// SwiftUI — the status item's icons. Defined once here so the two can never
  /// drift to slightly different blues.
  static let accentColor = NSColor(red: 0.36, green: 0.58, blue: 1.0, alpha: 1)
}
