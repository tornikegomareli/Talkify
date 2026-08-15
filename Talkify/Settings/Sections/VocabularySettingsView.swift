import SwiftUI

/// The Vocabulary section: the words Apple Speech should expect to hear.
/// The user writes this list; Talkify never adds to it from what was
/// dictated (CONTEXT.md: no recognized text is persisted).
struct VocabularySettingsView: View {
  let vocabulary: VocabularyList

  @Environment(\.colorSchemeContrast) private var contrast
  @State private var draft = ""
  @FocusState private var isDraftFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(title: "Add a term") {
        SettingsRow(
          title: "New term",
          description: "A name or an acronym, spelled the way you want it typed. "
            + "One or two words works best."
        ) {
          HStack(spacing: 8) {
            TextField("Talkify", text: $draft)
              .textFieldStyle(.plain)
              .font(.system(size: 13))
              .foregroundStyle(.white)
              .focused($isDraftFocused)
              .padding(.horizontal, 10)
              .padding(.vertical, 7)
              .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
              .overlay {
                RoundedRectangle(cornerRadius: 8)
                  .stroke(.white.opacity(contrast == .increased ? 0.26 : 0.12), lineWidth: 1)
              }
              .frame(width: 200)
              .onSubmit(submit)
              .onChange(of: draft) { vocabulary.clearRejection() }

            Button("Add", action: submit)
              .buttonStyle(SettingsButtonStyle())
              .disabled(Vocabulary.normalize(draft).isEmpty)
          }
        }

        if let message = rejectionMessage {
          noticeRow(message, isError: true)
        }

        if let errorMessage = vocabulary.errorMessage {
          noticeRow("Could not save your vocabulary: \(errorMessage)", isError: true)
        }
      }

      SettingsCard(title: listTitle) {
        if vocabulary.terms.isEmpty {
          noticeRow(
            "No terms yet. Add the words Talkify keeps mishearing and it will "
              + "favor them from the next session on.",
            isError: false
          )
        } else {
          ForEach(vocabulary.terms) { term in
            SettingsRow(title: term.text) {
              Button {
                Task { await vocabulary.remove(term) }
              } label: {
                Image(systemName: "trash")
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundStyle(.white.opacity(contrast == .increased ? 0.9 : 0.6))
                  .frame(width: 26, height: 26)
                  .background(.white.opacity(0.07), in: Circle())
                  .contentShape(Circle())
              }
              .buttonStyle(.plain)
              .help("Remove \(term.text)")
            }
          }
        }
      }

      Text(
        "Talkify hands these words to Apple Speech as a hint before you start "
          + "talking, so it leans toward them when what it hears is close. It "
          + "is a nudge, not a rule — a term you never say costs you nothing, "
          + "and recognition still runs entirely on device. Apple caps the "
          + "hint at \(Vocabulary.maximumTermCount) phrases and recognizes "
          + "short ones best, so spend them on the words it actually gets "
          + "wrong. Edits apply from your next session; one already recording "
          + "keeps the list it started with."
      )
      .font(.caption)
      .foregroundStyle(.white.opacity(contrast == .increased ? 0.7 : 0.45))
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 6)
    }
    .task { await vocabulary.load() }
  }

  private var listTitle: String {
    vocabulary.terms.isEmpty
      ? "Your vocabulary"
      : "Your vocabulary — \(vocabulary.terms.count) of \(Vocabulary.maximumTermCount)"
  }

  /// Named rules rather than a generic failure: each one tells the user what
  /// to do differently.
  private var rejectionMessage: String? {
    switch vocabulary.rejection {
    case .none, .empty:
      nil
    case .tooLong:
      "That is longer than \(Vocabulary.maximumTermLength) characters. "
        + "Vocabulary works on words and short phrases, not sentences."
    case .duplicate:
      "That term is already in your vocabulary."
    case .full:
      "Your vocabulary is full at \(Vocabulary.maximumTermCount) terms. "
        + "Remove one to add another."
    }
  }

  private func noticeRow(_ message: String, isError: Bool) -> some View {
    HStack {
      Text(message)
        .font(.caption)
        .foregroundStyle(
          isError
            ? Color.orange.opacity(0.95)
            : .white.opacity(contrast == .increased ? 0.72 : 0.48)
        )
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.vertical, 13)
  }

  private func submit() {
    let entry = draft
    Task {
      if await vocabulary.add(entry) {
        draft = ""
      }
      // Focus stays put either way: adding several terms in a row is the
      // normal way this list gets filled.
      isDraftFocused = true
    }
  }
}

#Preview {
  VocabularySettingsView(
    vocabulary: VocabularyList(store: VocabularyStore(
      fileURL: FileManager.default.temporaryDirectory
        .appending(path: "TalkifyVocabularyPreview-\(UUID().uuidString).json")
    ))
  )
  .frame(width: 620)
  .padding(30)
  .background(SettingsTheme.background)
  .preferredColorScheme(.dark)
}
