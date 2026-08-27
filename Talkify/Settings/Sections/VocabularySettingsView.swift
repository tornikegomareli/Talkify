import SwiftUI

/// The Vocabulary section: words Apple Speech is told to expect.
///
/// A list and a text field, and nothing else. What may join the list is
/// `Vocabulary`'s business, so this only reports which rule refused a term.
struct VocabularySettingsView: View {
  @Bindable var settings: AppSettings

  @State private var entry = ""
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(title: "Your words") {
        SettingsRow(
          title: "Add a word",
          description: "Up to \(Vocabulary.maximumTermLength) characters each"
        ) {
          HStack(spacing: 10) {
            TextField("Name, acronym, jargon", text: $entry)
              .textFieldStyle(.roundedBorder)
              .frame(width: 190)
              .onSubmit(add)
              .disabled(isFull)
            Button("Add", action: add)
              .buttonStyle(SettingsButtonStyle())
              .disabled(isFull || entry.trimmingCharacters(in: .whitespaces).isEmpty)
            // The count is the readout, the way the HUD size row reads out its
            // percentage. Monospaced and fixed width so it does not shift the
            // button as the digits grow.
            Text("\(settings.vocabularyTerms.count)/\(Vocabulary.maximumTermCount)")
              .font(.system(size: 12, weight: .medium))
              .monospacedDigit()
              .foregroundStyle(.white.opacity(isFull ? 0.85 : 0.62))
              .frame(width: 54, alignment: .trailing)
              .accessibilityLabel(
                "\(settings.vocabularyTerms.count) of \(Vocabulary.maximumTermCount) words used"
              )
          }
        }

        ForEach(settings.vocabularyTerms, id: \.self) { term in
          SettingsRow(title: term) {
            Button("Remove") { remove(term) }
              .buttonStyle(SettingsButtonStyle())
          }
        }
      }

      Text(
        "Apple Speech has never heard your colleague's name or your product's, "
          + "so it guesses. These words tell it what to expect before you "
          + "speak, rather than correcting the text afterwards. They stay on "
          + "this Mac and are never sent anywhere."
      )
      .font(.caption)
      .foregroundStyle(.white.opacity(contrast == .increased ? 0.7 : 0.45))
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 6)
    }
  }

  /// Apple's ceiling, reached. The field and the button go dead rather than
  /// refusing silently, which reads as broken.
  private var isFull: Bool {
    settings.vocabularyTerms.count >= Vocabulary.maximumTermCount
  }

  private func add() {
    guard let terms = Vocabulary.adding(entry, to: settings.vocabularyTerms) else { return }
    settings.vocabularyTerms = terms
    entry = ""
  }

  private func remove(_ term: String) {
    settings.vocabularyTerms.removeAll { $0 == term }
  }
}
