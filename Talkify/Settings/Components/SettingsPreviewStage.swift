import SwiftUI

/// The chrome the Settings previews share: a titled card holding a dark
/// display, so whatever HUD surface is placed in it reads as floating with
/// its housing cap at the bottom edge of a screen rather than inside a box.
///
/// Both previews use the fixed notched reference geometry (CONTEXT.md), which
/// is why the stage can own the strip's dimensions: they are the same picture
/// with a different shape inside it.
struct SettingsPreviewStage<HUD: View>: View {
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let title: String
  let subtitle: String
  @ViewBuilder let hud: HUD

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 14, weight: .semibold))
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.48))
        }
        Spacer()
        Circle()
          .fill(SettingsTheme.accent)
          .frame(width: 7, height: 7)
          .shadow(color: SettingsTheme.accent, radius: reduceMotion ? 0 : 7)
      }

      ZStack(alignment: .top) {
        LinearGradient(
          colors: [Color(red: 0.055, green: 0.065, blue: 0.09), .black],
          startPoint: .top,
          endPoint: .bottom
        )

        simulatedMenuBar

        hud
          .scaleEffect(0.48, anchor: .bottom)
          .frame(width: 300, height: 105, alignment: .bottom)
          .clipped()
      }
      .frame(height: 118)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(.white.opacity(contrast == .increased ? 0.2 : 0.07), lineWidth: 1)
      }
    }
    .padding(16)
    .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(.white.opacity(contrast == .increased ? 0.22 : 0.1), lineWidth: 1)
    }
  }

  /// A simulated menu bar strip so the shape reads as a notch at the top
  /// of a display: matches the housing strip's scaled height, with the
  /// Talkify ghost among the status items. The shell's black housing
  /// draws over its center.
  private var simulatedMenuBar: some View {
    HStack(spacing: 0) {
      HStack(spacing: 7) {
        Image(systemName: "apple.logo")
          .font(.system(size: 8))
        Text("Finder")
          .font(.system(size: 8.5, weight: .semibold))
      }
      Spacer()
      HStack(spacing: 8) {
        Image("MenuBarIcon")
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(height: 8.5)
        Image(systemName: "wifi")
          .font(.system(size: 8))
        Text("11:41")
          .font(.system(size: 8.5, weight: .medium))
      }
    }
    .foregroundStyle(.white.opacity(0.55))
    .padding(.horizontal, 10)
    .frame(height: 15.4)
    .background(.white.opacity(0.05))
  }
}
