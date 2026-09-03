import SwiftUI

/// One prompt, open for editing.
///
/// Edits write straight back to settings, like every other Settings control:
/// there is no Save step and no draft to lose. Only the prompt's own wording is
/// editable. The transcript-is-data framing around it stays fixed, because an
/// editable framing could delete the never-answer rule and bring the answered
/// question back.
///
/// The sheet can run the prompt. Writing an instruction for a model without
/// seeing what it does to a sentence is guesswork, and the model is already
/// here: the same service a session uses answers the Try button, so what the
/// sheet shows and what a session gets cannot drift apart.
struct ShapingPromptEditorView: View {
  @Binding var prompt: ShapingPrompt
  let onDelete: () -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorSchemeContrast) private var contrast
  @State private var sample = Self.defaultSample
  @State private var result: TryResult?
  @State private var isTrying = false
  @State private var showsAdvanced = false
  @State private var isConfirmingDelete = false

  /// Question-shaped on purpose. It is the input the fixed framing exists to
  /// protect, so trying it shows that rule holding rather than an easy case.
  private static let defaultSample = "um what time does does the meeting start you know tomorrow"

  /// What came back, held apart from the sample so the two can be compared.
  private enum TryResult: Equatable {
    case shaped(String)
    /// The service passes the words through on every failure, so a result
    /// equal to the input is the one answer that needs saying out loud.
    case unchanged
    case unavailable(String)
  }

  private var hasInstruction: Bool {
    !prompt.preInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          promptCard
          tryCard
          advancedCard
        }
        .padding(16)
      }
      footer
    }
    // Inside the fixed 860x600 Settings window: a taller sheet is clipped by
    // it, and the first thing to go is the footer. The cards scroll instead.
    .frame(width: 560, height: 540)
    .background(SettingsTheme.background)
    .confirmationDialog(
      "Delete “\(displayName)”?",
      isPresented: $isConfirmingDelete
    ) {
      Button("Delete", role: .destructive) {
        onDelete()
        dismiss()
      }
    } message: {
      Text("This removes the prompt from the library. It cannot be undone.")
    }
  }

  private var displayName: String {
    prompt.name.isEmpty ? "Untitled" : prompt.name
  }

  private var promptCard: some View {
    SettingsCard(title: "Prompt") {
      SettingsRow(title: "Name") {
        TextField("Name", text: $prompt.name)
          .textFieldStyle(.roundedBorder)
          .frame(width: 220)
      }

      FieldBlock(
        title: "What it does",
        description: "Sent to the model as an instruction. One or two plain "
          + "sentences work better than a list of rules.",
        text: $prompt.preInstruction,
        height: 68
      )
    }
  }

  /// The point of the sheet: change a sentence, press Try, read what the model
  /// did with it.
  private var tryCard: some View {
    SettingsCard(title: "Try it") {
      FieldBlock(
        title: "Sample",
        description: "Pretend you dictated this, then run the prompt over it.",
        text: $sample,
        height: 48
      ) {
        Button(isTrying ? "Trying…" : "Try") { runTry() }
          .buttonStyle(SettingsButtonStyle())
          .disabled(isTrying || !hasInstruction)
      }

      if let result {
        resultView(result)
      }
    }
  }

  @ViewBuilder
  private func resultView(_ result: TryResult) -> some View {
    switch result {
    case let .shaped(text):
      VStack(alignment: .leading, spacing: 6) {
        Text("Result")
          .font(.system(size: 13, weight: .medium))
        block(Text(text).font(.system(size: 13)))
      }
      .padding(.vertical, 13)
    case .unchanged:
      note("The model returned the words unchanged. That is what a session "
        + "would insert too, so this instruction may not ask for anything "
        + "this sentence needs.")
    case let .unavailable(reason):
      note(reason)
    }
  }

  /// Everything most prompts never touch. Folded away because all three
  /// built-in prompts leave it empty, and a field nobody fills is in the way.
  private var advancedCard: some View {
    SettingsCard(title: "Advanced") {
      SettingsRow(
        title: "Show the rest",
        description: "A closing instruction, a worked example, and the exact "
          + "text the model receives."
      ) {
        Toggle("Show the rest", isOn: $showsAdvanced)
          .labelsHidden()
          .toggleStyle(.switch)
      }

      if showsAdvanced {
        FieldBlock(
          title: "Closing instruction",
          description: "Placed after the transcript, for a rule that reads "
            + "better last.",
          text: $prompt.postInstruction,
          height: 56
        )

        VStack(alignment: .leading, spacing: 8) {
          label(
            "Example",
            "One worked pair, sent with every request. A question-shaped input "
              + "whose output stays a question is what teaches the model to "
              + "rewrite a question instead of answering it. Used only when "
              + "both halves are filled in."
          )
          TextField("Dictated", text: $prompt.exampleInput)
            .textFieldStyle(.roundedBorder)
          TextField("Rewritten", text: $prompt.exampleOutput)
            .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { separatorLine }

        VStack(alignment: .leading, spacing: 8) {
          label(
            "What the model receives",
            "The framing around your wording is fixed. It is what keeps a "
              + "question-shaped dictation from being answered."
          )
          block(
            Text(prompt.request(wrapping: Self.defaultSample))
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(.white.opacity(contrast == .increased ? 0.82 : 0.66))
          )
        }
        .padding(.vertical, 13)
      }
    }
  }

  private func label(_ title: String, _ description: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 13, weight: .medium))
      Text(description)
        .font(.caption)
        .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.48))
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func block(_ content: some View) -> some View {
    content
      .textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(
        SettingsTheme.background,
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.5))
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 13)
  }

  private var separatorLine: some View {
    Rectangle()
      .fill(.white.opacity(contrast == .increased ? 0.16 : 0.07))
      .frame(height: 1)
  }

  private var footer: some View {
    HStack {
      Button("Delete…") { isConfirmingDelete = true }
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

  /// Runs the real service, so the answer is the one a session would get.
  private func runTry() {
    let client = PromptShapingService.Client.live
    if let reason = client.unavailabilityReason() {
      result = .unavailable(reason)
      return
    }
    let input = sample.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !input.isEmpty else { return }

    isTrying = true
    result = nil
    let prompt = prompt
    Task {
      let shaped = await PromptShapingService(client: client).shape(input, with: prompt)
      isTrying = false
      result = shaped == input ? .unchanged : .shaped(shaped)
    }
  }
}

/// A labelled block whose control is a multi-line editor under the label
/// rather than a switch beside it.
///
/// `SettingsRow` cannot do this: it puts its control on the trailing edge and
/// closes with a separator, which would cut a label away from the box it
/// describes. A prompt is a paragraph, so its field has to be a paragraph.
private struct FieldBlock<Trailing: View>: View {
  let title: String
  var description = ""
  @Binding var text: String
  var height: CGFloat = 76
  @ViewBuilder var trailing: Trailing

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 13, weight: .medium))
          if !description.isEmpty {
            Text(description)
              .font(.caption)
              .foregroundStyle(.white.opacity(contrast == .increased ? 0.72 : 0.48))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 12)
        trailing
      }

      TextEditor(text: $text)
        .font(.system(size: 12))
        .scrollContentBackground(.hidden)
        .padding(6)
        .frame(height: height)
        .background(
          SettingsTheme.background,
          in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(.white.opacity(contrast == .increased ? 0.24 : 0.1), lineWidth: 1)
        }
        .accessibilityLabel(title)
    }
    .padding(.vertical, 13)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.white.opacity(contrast == .increased ? 0.16 : 0.07))
        .frame(height: 1)
    }
  }
}

extension FieldBlock where Trailing == EmptyView {
  init(
    title: String,
    description: String = "",
    text: Binding<String>,
    height: CGFloat = 76
  ) {
    self.init(
      title: title,
      description: description,
      text: text,
      height: height,
      trailing: { EmptyView() }
    )
  }
}
