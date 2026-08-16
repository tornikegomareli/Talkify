import SwiftUI

/// One binding: its keys as separate caps on the leading edge, then what it
/// does. Each cap is one physical key, rather than a single label with the
/// whole combination crammed into it.
struct ShortcutRow: View {
  let caps: [String]
  let title: String
  let description: String
  let isRecording: Bool
  let accent: Color
  /// What has been clicked on the keyboard so far, shown in place of the
  /// binding while the row is armed.
  var pickedCaps: [String] = []
  /// Present once something is picked; a bare modifier has no following key to
  /// finish it, so it needs somewhere to say "that one".
  var onConfirm: (() -> Void)?

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    HStack(spacing: 15) {
      HStack(spacing: 6) {
        if isRecording, !pickedCaps.isEmpty {
          ForEach(Array(pickedCaps.enumerated()), id: \.offset) { _, symbol in
            cap(symbol, isArmed: true)
          }
        } else if isRecording {
          cap("…", isArmed: true)
        } else {
          ForEach(Array(caps.enumerated()), id: \.offset) { _, symbol in
            cap(symbol, isArmed: false)
          }
        }
      }

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.white)
        Text(isRecording ? armedPrompt : description)
          .font(.system(size: 11.5))
          .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.48))
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(.leading)
      }

      Spacer(minLength: 0)

      if let onConfirm {
        Button("Use these", action: onConfirm)
          .buttonStyle(SettingsButtonStyle())
      }
    }
    .padding(.vertical, 11)
    .contentShape(Rectangle())
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.white.opacity(contrast == .increased ? 0.16 : 0.07))
        .frame(height: 1)
    }
  }

  private var armedPrompt: String {
    pickedCaps.isEmpty
      ? "Press the keys you want, or click them on the keyboard above."
      : "Click one more key to finish, or use what you picked."
  }

  private func cap(_ symbol: String, isArmed: Bool) -> some View {
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    return Text(symbol)
      .font(.system(size: symbol.count > 2 ? 10 : 13, weight: .medium))
      .foregroundStyle(isArmed ? accent : .white.opacity(0.9))
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .padding(.horizontal, 4)
      .frame(width: 34, height: 32)
      .background(
        shape.fill(
          LinearGradient(
            colors: [Color(white: 0.16), Color(white: 0.11)],
            startPoint: .top,
            endPoint: .bottom
          )
        )
      )
      .overlay {
        shape.strokeBorder(
          isArmed ? accent.opacity(0.8) : .white.opacity(0.1),
          lineWidth: 1
        )
      }
  }
}
