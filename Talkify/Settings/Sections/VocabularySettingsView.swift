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
        SettingsRow(title: "Add a word", description: description) {
          HStack(spacing: 8) {
            TextField("Name, acronym, jargon", text: $entry)
              .textFieldStyle(.roundedBorder)
              .frame(width: 200)
              .onSubmit(add)
            Button("Add", action: add)
              .buttonStyle(SettingsButtonStyle())
              .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
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

  /// Says which rule refused a term, rather than letting the field look broken.
  private var description: String {
    let remaining = Vocabulary.maximumTermCount - settings.vocabularyTerms.count
    guard remaining > 0 else {
      return "The list is full at \(Vocabulary.maximumTermCount) words, which "
        + "is Apple's limit. Remove one to add another"
    }
    return "\(remaining) of \(Vocabulary.maximumTermCount) left. "
      + "Up to \(Vocabulary.maximumTermLength) characters each"
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
