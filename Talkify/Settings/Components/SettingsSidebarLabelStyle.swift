import SwiftUI

/// Lines the sidebar's titles up with each other.
///
/// `Label`'s default layout sizes the icon to its glyph, and SF Symbols are not
/// one width — `keyboard` is half again as wide as `globe` — so each row's
/// title started at whatever x its own icon happened to end at. A fixed column
/// pins the text edge and lets the glyphs vary inside it, which is how every
/// macOS sidebar reads.
struct SettingsSidebarLabelStyle: LabelStyle {
  /// Wide enough for the widest symbol in the navigation at 13pt, so nothing
  /// overflows the column into the title.
  private let iconColumn: CGFloat = 20

  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 9) {
      configuration.icon
        .frame(width: iconColumn, alignment: .center)
      configuration.title
    }
  }
}
