import SwiftUI

/// The Prompt Shaping section: the beta toggle and the prompt library.
///
/// The library is rows rather than a dropdown. A prompt is a paragraph of
/// instructions, and a menu showing only its name asks the reader to remember
/// what three names mean; the row shows the instruction under the name, so the
/// choice is made by reading rather than by recall.
struct PromptShapingSettingsView: View {
  @Bindable var settings: AppSettings

  @Environment(\.colorSchemeContrast) private var contrast
  @State private var editingPromptID: String?
  @State private var isConfirmingRestore = false

  /// Read once per appearance: the answer needs Apple Intelligence and cannot
  /// change while the pane is open.
  private var unavailability: String? {
    PromptShapingService.Client.live.unavailabilityReason()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SettingsCard(title: "Shaping") {
        SettingsRow(
          title: "Shape dictation with a prompt",
          description: "Finished dictation is rewritten by Apple's on-device "
            + "model before it is inserted. Nothing leaves this Mac."
        ) {
          Toggle("Shape dictation with a prompt", isOn: $settings.promptShapingEnabled)
            .labelsHidden()
            .toggleStyle(.switch)
        }

        if let unavailability {
          SettingsRow(title: "Not available here", description: unavailability) {
            EmptyView()
          }
        }
      }

      SettingsCard(title: "Prompts") {
        ForEach(settings.shapingPrompts) { prompt in
          promptRow(prompt)
        }

        SettingsRow(
          title: "Library",
          description: hasSelection
            ? "\(settings.shapingPrompts.count) prompt"
              + (settings.shapingPrompts.count == 1 ? "" : "s")
            : "No prompt is picked, so dictation is inserted unchanged."
        ) {
          HStack(spacing: 8) {
            Button("Restore Defaults…") { isConfirmingRestore = true }
              .buttonStyle(SettingsButtonStyle())
            Button("Add Prompt") { addPrompt() }
              .buttonStyle(SettingsButtonStyle())
          }
        }
      }

      Text(
        "This is a beta. Any failure, refusal, or slow answer inserts the raw "
          + "words unchanged, and transcription history always keeps what you "
          + "said. While dictating, ← and → switch prompt for that session."
      )
      .font(.caption)
      .foregroundStyle(.white.opacity(contrast == .increased ? 0.7 : 0.45))
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 6)
    }
    .sheet(item: editingPrompt) { prompt in
      if let index = settings.shapingPrompts.firstIndex(where: { $0.id == prompt.id }) {
        ShapingPromptEditorView(
          prompt: binding(at: index),
          onDelete: { deletePrompt(prompt.id) }
        )
      }
    }
    .confirmationDialog(
      "Restore the built-in prompts?",
      isPresented: $isConfirmingRestore
    ) {
      Button("Restore Defaults", role: .destructive) {
        settings.restoreDefaultShapingPrompts()
        selectFirstPromptIfNothingIsPicked()
      }
    } message: {
      Text("This replaces every prompt in the library with the three built-in "
        + "defaults. It cannot be undone.")
    }
  }

  /// One prompt: the pick, what it does, and the way in to edit it. Selecting
  /// is the whole row, because the row is the choice.
  private func promptRow(_ prompt: ShapingPrompt) -> some View {
    let isSelected = prompt.id == settings.promptShapingPromptID
    return SettingsRow(
      title: prompt.name.isEmpty ? "Untitled" : prompt.name,
      description: summary(of: prompt)
    ) {
      HStack(spacing: 10) {
        Button("Edit") { editingPromptID = prompt.id }
          .buttonStyle(SettingsButtonStyle())
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 15))
          .foregroundStyle(isSelected ? SettingsTheme.accent : .white.opacity(0.25))
          .accessibilityLabel(isSelected ? "Selected" : "Select")
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { settings.promptShapingPromptID = prompt.id }
  }

  /// What the prompt does, in the prompt's own words. Its instruction is
  /// already a sentence saying exactly that, so nothing else describes it
  /// better and nothing has to be kept in step with it.
  private func summary(of prompt: ShapingPrompt) -> String {
    let instruction = prompt.preInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
    return instruction.isEmpty ? "No instruction yet" : instruction
  }

  private var editingPrompt: Binding<ShapingPrompt?> {
    Binding(
      get: { settings.shapingPrompts.first { $0.id == editingPromptID } },
      set: { editingPromptID = $0?.id }
    )
  }

  private func binding(at index: Int) -> Binding<ShapingPrompt> {
    Binding(
      get: { settings.shapingPrompts[index] },
      set: { settings.shapingPrompts[index] = $0 }
    )
  }

  private func addPrompt() {
    let prompt = ShapingPrompt(
      id: UUID().uuidString,
      name: "New Prompt",
      preInstruction: "",
      postInstruction: "",
      exampleInput: "",
      exampleOutput: ""
    )
    settings.shapingPrompts.append(prompt)
    editingPromptID = prompt.id
  }

  private func deletePrompt(_ id: String) {
    editingPromptID = nil
    settings.shapingPrompts.removeAll { $0.id == id }
    selectFirstPromptIfNothingIsPicked()
  }

  private func selectFirstPromptIfNothingIsPicked() {
    settings.promptShapingPromptID = Self.resolvedSelection(
      picked: settings.promptShapingPromptID,
      in: settings.shapingPrompts
    )
  }

  /// Whether the picked id still names a prompt in the library. A stale id can
  /// also arrive from a library edited before this pane existed.
  private var hasSelection: Bool {
    settings.shapingPrompts.contains { $0.id == settings.promptShapingPromptID }
  }

  /// Which prompt should be picked, given a library and the stored pick.
  ///
  /// A stored id resolving to no prompt inserts the raw words silently, which
  /// reads as shaping being broken rather than as nothing being picked.
  /// Deleting the picked prompt, or restoring defaults over it, is how a user
  /// reaches that, so both fall back to the first prompt in the library.
  static func resolvedSelection(picked: String, in prompts: [ShapingPrompt]) -> String {
    prompts.contains { $0.id == picked } ? picked : (prompts.first?.id ?? "")
  }
}
