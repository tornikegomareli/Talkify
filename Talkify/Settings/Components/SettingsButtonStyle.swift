import SwiftUI

/// The capsule button used by Settings preview and action rows.
struct SettingsButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.white.opacity(configuration.isPressed ? 0.18 : 0.1), in: Capsule())
      .overlay {
        Capsule().stroke(.white.opacity(0.12), lineWidth: 1)
      }
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .opacity(isEnabled ? 1 : 0.45)
  }
}
