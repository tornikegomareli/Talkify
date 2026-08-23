import AppKit
import SwiftUI

struct DictionarySettingsView: View {
  @State private var store = DictionaryStore.shared
  @State private var query = ""
  @State private var editing: DictionaryEntry?
  @State private var isAdding = false
  @Environment(\.colorSchemeContrast) private var contrast

  private var entries: [DictionaryEntry] { store.filtered(by: query) }

  var body: some View {
    VStack(spacing: 16) {
      SettingsCard(title: "Personal Dictionary") {
        SettingsRow(
          title: "Search",
          description: "Filter by the word or phrase on either side"
        ) {
          TextField("Search dictionary", text: $query)
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
        }

        HStack {
          Text("\(store.entries.count) entries")
            .font(.caption)
            .foregroundStyle(.white.opacity(contrast == .increased ? 0.76 : 0.52))
          Spacer()
          Button("Add Entry") { isAdding = true }
            .buttonStyle(SettingsButtonStyle())
          Button("Reveal File") { revealFile() }
            .buttonStyle(SettingsButtonStyle())
        }
        .padding(.vertical, 8)
      }

      SettingsCard(title: "Entries") {
        if entries.isEmpty {
          Text(store.entries.isEmpty ? "No entries yet. Add words it keeps getting wrong." : "No matches")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
        } else {
          ForEach(entries) { entry in
            DictionaryRowView(
              entry: entry,
              onEdit: { editing = entry },
              onToggle: {
                var updated = entry
                updated.isEnabled.toggle()
                store.update(updated)
              },
              onDelete: { store.delete(entry) }
            )
          }
        }
      }

      SettingsCard(title: "About") {
        Text("Terms bias recognition; corrections rewrite text after. The file at \(DictionaryStore.fileURL.path(percentEncoded: false)) is editable by hand and updates live.")
          .font(.caption)
          .foregroundStyle(.white.opacity(contrast == .increased ? 0.76 : 0.52))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .sheet(isPresented: $isAdding) {
      DictionaryEditorView(entry: nil) { store.add($0) }
    }
    .sheet(item: $editing) { entry in
      DictionaryEditorView(entry: entry) { store.update($0) }
    }
  }

  private func revealFile() {
    NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
  }
}

private struct DictionaryRowView: View {
  let entry: DictionaryEntry
  let onEdit: () -> Void
  let onToggle: () -> Void
  let onDelete: () -> Void
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(entry.isEnabled ? Color.green : Color.gray)
        .frame(width: 8, height: 8)
      Text(entry.kind == .correction ? "Fix" : "Term")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.5))
        .frame(width: 32, alignment: .leading)
      if entry.kind == .correction {
        Text(entry.hear)
          .font(.system(size: 13))
          .foregroundStyle(.white.opacity(0.6))
        Image(systemName: "arrow.right")
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(.white.opacity(0.4))
      }
      Text(entry.write)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .lineLimit(1)
      Spacer()
      Button(entry.isEnabled ? "Disable" : "Enable", action: onToggle)
        .buttonStyle(SettingsButtonStyle())
      Button("Edit", action: onEdit)
        .buttonStyle(SettingsButtonStyle())
      Button("Delete", action: onDelete)
        .buttonStyle(SettingsButtonStyle())
    }
    .opacity(entry.isEnabled ? 1 : 0.5)
    .padding(.vertical, 6)
    .overlay(alignment: .bottom) {
      Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
    }
  }
}

private struct DictionaryEditorView: View {
  let entry: DictionaryEntry?
  let onSave: (DictionaryEntry) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var kind: DictionaryEntry.Kind
  @State private var hear: String
  @State private var write: String
  @Environment(\.colorSchemeContrast) private var contrast

  init(entry: DictionaryEntry?, onSave: @escaping (DictionaryEntry) -> Void) {
    self.entry = entry
    self.onSave = onSave
    _kind = State(initialValue: entry?.kind ?? .term)
    _hear = State(initialValue: entry?.hear ?? "")
    _write = State(initialValue: entry?.write ?? "")
  }

  private var draft: DictionaryEntry {
    DictionaryEntry(
      id: entry?.id ?? UUID(),
      kind: kind,
      write: write.trimmingCharacters(in: .whitespacesAndNewlines),
      hear: kind == .correction ? hear.trimmingCharacters(in: .whitespacesAndNewlines) : "",
      isEnabled: entry?.isEnabled ?? true
    )
  }

  private var warnings: [DictionaryWarning] { DictionaryWarning.check(draft) }
  private var isValid: Bool { !draft.write.isEmpty && (kind == .term || !draft.hear.isEmpty) }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(entry == nil ? "New Entry" : "Edit Entry")
        .font(.system(size: 16, weight: .semibold))
      Picker("Type", selection: $kind) {
        Text("Term").tag(DictionaryEntry.Kind.term)
        Text("Correction").tag(DictionaryEntry.Kind.correction)
      }
      .pickerStyle(.segmented)
      VStack(alignment: .leading, spacing: 12) {
        if kind == .correction {
          VStack(alignment: .leading, spacing: 4) {
            Text("When you hear").font(.caption).foregroundStyle(.white.opacity(0.6))
            TextField("cloud code", text: $hear)
              .textFieldStyle(.roundedBorder)
          }
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(kind == .correction ? "Write" : "Word or phrase").font(.caption).foregroundStyle(.white.opacity(0.6))
          TextField(kind == .correction ? "Claude Code" : "Anthropic", text: $write)
            .textFieldStyle(.roundedBorder)
        }
      }
      ForEach(warnings) { warning in
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.yellow)
          Text(warning.message)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(8)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .buttonStyle(SettingsButtonStyle())
        Button("Save") {
          guard isValid else { return }
          onSave(draft)
          dismiss()
        }
        .buttonStyle(SettingsButtonStyle())
        .disabled(!isValid)
      }
    }
    .padding(20)
    .frame(width: 460)
    .background(SettingsTheme.card)
  }
}
