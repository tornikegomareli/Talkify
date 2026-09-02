import SwiftUI

/// The Manage Prompts sheet: the user-editable shaping prompt library.
///
/// Edits write straight back to settings, like every other Settings control —
/// there is no Save step. Only the prompt's own wording is editable; the
/// transcript-is-data framing stays fixed, because an editable framing could
/// delete the never-answer rule and resurrect the answered-question bug. The
/// template preview renders the real `request(wrapping:)`, so what the sheet
/// shows and what a session sends cannot drift apart.
struct ShapingPromptEditorView: View {
  @Bindable var settings: AppSettings

  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorSchemeContrast) private var contrast
  @State private var selectedID: String?
  @State private var isConfirmingRestore = false

  /// A question-shaped sample, because that is the input the framing exists
  /// to protect: the preview shows where such words sit as data.
  private static let sampleTranscript = "what time does the meeting start tomorrow"

  private var selectedIndex: Int? {
    selectedID.flatMap { id in settings.shapingPrompts.firstIndex { $0.id == id } }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 14) {
        promptList
        Divider().overlay(.white.opacity(0.1))
        if let index = selectedIndex {
          editor(for: binding(at: index))
        } else {
          emptySelection
        }
      }
      .padding(16)

      footer
    }
    .frame(width: 560, height: 640)
    .background(SettingsTheme.background)
    .preferredColorScheme(.dark)
    .onAppear {
      selectedID = settings.shapingPrompts.prompt(for: settings.promptShapingPromptID)?.id
        ?? settings.shapingPrompts.first?.id
    }
    .confirmationDialog(
      "Restore the built-in prompts?",
      isPresented: $isConfirmingRestore
    ) {
      Button("Restore Defaults", role: .destructive) { restoreDefaults() }
    } message: {
      Text("This replaces every prompt in the library with the three "
        + "built-in defaults. It cannot be undone.")
    }
  }

  private var promptList: some View {
    VStack(alignment: .leading, spacing: 8) {
      List(selection: $selectedID) {
        ForEach(settings.shapingPrompts) { prompt in
          Text(prompt.name.isEmpty ? "Untitled" : prompt.name)
            .font(.system(size: 13))
            .tag(prompt.id)
        }
      }
      .scrollContentBackground(.hidden)
      .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

      HStack(spacing: 8) {
        Button { addPrompt() } label: {
          Image(systemName: "plus")
        }
        .buttonStyle(SettingsButtonStyle())
        .accessibilityLabel("Add prompt")

        Button { deleteSelectedPrompt() } label: {
          Image(systemName: "minus")
        }
        .buttonStyle(SettingsButtonStyle())
        .accessibilityLabel("Delete prompt")
        .disabled(selectedIndex == nil)
      }
    }
    .frame(width: 150)
  }

  private var emptySelection: some View {
    VStack {
      Spacer()
      Text("No prompt selected. Add one, or restore the defaults.")
        .font(.caption)
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity)
      Spacer()
    }
  }

  private func editor(for prompt: Binding<ShapingPrompt>) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        field("Name") {
          TextField("Name", text: prompt.name)
            .textFieldStyle(.roundedBorder)
        }

        field("Pre-instruction", caption: "Placed before the transcript.") {
          instructionEditor(prompt.preInstruction)
        }

        field("Post-instruction", caption: "Placed after the transcript.") {
          instructionEditor(prompt.postInstruction)
        }

        field(
          "Example (optional)",
          caption: "A one-shot example sent with every request. A "
            + "question-shaped input whose output stays a question teaches "
            + "the model to rewrite a question instead of answering it. "
            + "Used only when both fields are filled in."
        ) {
          TextField("Example input", text: prompt.exampleInput)
            .textFieldStyle(.roundedBorder)
          TextField("Example output", text: prompt.exampleOutput)
            .textFieldStyle(.roundedBorder)
        }

        templatePreview(for: prompt.wrappedValue)
      }
      .padding(.trailing, 4)
    }
  }

  private func field(
    _ title: String,
    caption: String = "",
    @ViewBuilder content: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
      if !caption.isEmpty {
        Text(caption)
          .font(.caption)
          .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.48))
          .fixedSize(horizontal: false, vertical: true)
      }
      content()
    }
  }

  private func instructionEditor(_ text: Binding<String>) -> some View {
    TextEditor(text: text)
      .font(.system(size: 12))
      .scrollContentBackground(.hidden)
      .padding(6)
      .frame(height: 58)
      .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(.white.opacity(0.12), lineWidth: 1)
      }
  }

  private func templatePreview(for prompt: ShapingPrompt) -> some View {
    field(
      "Template",
      caption: "Every request first tells the model the transcript is text "
        + "to rewrite, never a question to answer — that framing is fixed "
        + "and cannot be edited. Your prompt then wraps the transcript, "
        + "shown here for a sample dictation:"
    ) {
      Text(prompt.request(wrapping: Self.sampleTranscript))
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white.opacity(0.72))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(SettingsTheme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }

  private var footer: some View {
    HStack {
      Button("Restore Defaults…") { isConfirmingRestore = true }
        .buttonStyle(SettingsButtonStyle())
      Spacer()
      Button("Done") { dismiss() }
        .buttonStyle(SettingsButtonStyle())
        .keyboardShortcut(.defaultAction)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(SettingsTheme.sidebar)
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
    selectedID = prompt.id
  }

  private func deleteSelectedPrompt() {
    guard let index = selectedIndex else { return }
    settings.shapingPrompts.remove(at: index)
    let remaining = settings.shapingPrompts
    selectedID = remaining.indices.contains(index) ? remaining[index].id : remaining.last?.id
  }

  private func restoreDefaults() {
    settings.restoreDefaultShapingPrompts()
    if selectedIndex == nil {
      selectedID = settings.shapingPrompts.first?.id
    }
  }
}
