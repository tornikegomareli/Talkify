import SwiftUI

/// The Spelling replacements section: whole-word swaps after recognition.
///
/// Apple Speech cannot be taught a word it does not know. These pairs fix
/// the spelling it produces, and only when the user wrote both sides.
struct ReplacementsSettingsView: View {
  @Bindable var settings: AppSettings

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(title: "Words") {
        ForEach($settings.spellingReplacements) { $pair in
          replacementRow($pair)
        }

        SettingsRow(
          title: "Add a replacement",
          description: settings.spellingReplacements.isEmpty
            ? "Nothing is rewritten until you add a pair."
            : "\(settings.spellingReplacements.count) pair"
              + (settings.spellingReplacements.count == 1 ? "" : "s")
        ) {
          Button("Add") { add() }
            .buttonStyle(SettingsButtonStyle())
        }
      }

      Text(
        "After recognition, each complete pair swaps that whole word or "
          + "phrase for the spelling you typed. Matching ignores case, a "
          + "possessive keeps its 's, and nothing leaves this Mac."
      )
      .font(.caption)
      .foregroundStyle(.white.opacity(contrast == .increased ? 0.7 : 0.45))
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 6)
    }
  }

  private func replacementRow(_ pair: Binding<SpellingReplacement>) -> some View {
    HStack(spacing: 10) {
      TextField("Misspelled word or phrase", text: pair.from)
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 110)
      Image(systemName: "arrow.right")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(contrast == .increased ? 0.7 : 0.35))
      TextField("Correct", text: pair.to)
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 110)
      Spacer(minLength: 8)
      Button("Remove") { remove(pair.wrappedValue.id) }
        .buttonStyle(SettingsButtonStyle())
    }
    .padding(.vertical, 13)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.white.opacity(contrast == .increased ? 0.16 : 0.07))
        .frame(height: 1)
    }
  }

  private func add() {
    settings.spellingReplacements.append(
      SpellingReplacement(id: UUID().uuidString, from: "", to: "")
    )
  }

  private func remove(_ id: String) {
    settings.spellingReplacements.removeAll { $0.id == id }
  }
}
