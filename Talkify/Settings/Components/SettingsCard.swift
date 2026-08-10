import SwiftUI

/// A labeled group of related Settings rows on one rounded card
/// (CONTEXT.md: related rows share rounded cards with subtle separators).
struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(contrast == .increased ? 0.7 : 0.44))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(contrast == .increased ? 0.22 : 0.09), lineWidth: 1)
        }
    }
}
