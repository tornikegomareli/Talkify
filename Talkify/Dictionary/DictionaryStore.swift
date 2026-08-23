import Foundation
import Observation

@MainActor
@Observable
final class DictionaryStore {
  static let shared = DictionaryStore()

  private(set) var entries: [DictionaryEntry] = []
  private(set) var revision = 0

  private var watcher: DispatchSourceFileSystemObject?
  private var isSaving = false

  static var fileURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Talkify", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent("dictionary.txt")
  }

  init(fileURL: URL? = nil, watchFile: Bool = true) {
    if let fileURL {
      self.customFileURL = fileURL
    }
    load()
    if watchFile {
      startWatching()
    }
  }

  private var customFileURL: URL?

  private var resolvedFileURL: URL {
    customFileURL ?? Self.fileURL
  }

  func add(_ entry: DictionaryEntry) {
    guard entry.isValidForFile else { return }
    entries.append(entry)
    save()
  }

  func update(_ entry: DictionaryEntry) {
    guard entry.isValidForFile else { return }
    guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
    entries[index] = entry
    save()
  }

  func delete(_ entry: DictionaryEntry) {
    entries.removeAll { $0.id == entry.id }
    save()
  }

  func delete(ids: Set<UUID>) {
    entries.removeAll { ids.contains($0.id) }
    save()
  }

  func filtered(by query: String) -> [DictionaryEntry] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return entries }
    return entries.filter {
      $0.write.localizedStandardContains(trimmed) || $0.hear.localizedStandardContains(trimmed)
    }
  }

  var corrector: DictionaryCorrector { DictionaryCorrector(entries: entries) }

  var biasPhrases: [String] { DictionaryCorrector.biasPhrases(from: entries) }

  func contains(write: String, hear: String) -> Bool {
    let normalizedWrite = write.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedHear = hear.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    return entries.contains {
      $0.write.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedWrite
        && $0.hear.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedHear
    }
  }

  func reloadFromDisk() {
    load()
  }

  private func load() {
    let url = resolvedFileURL
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
      entries = []
      revision += 1
      return
    }
    entries = Self.parse(text)
    revision += 1
  }

  static func parse(_ text: String) -> [DictionaryEntry] {
    text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine in
      var line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { return nil }
      var isEnabled = true
      if line.hasPrefix("#") {
        let stripped = line.dropFirst().trimmingCharacters(in: .whitespaces)
        guard stripped.lowercased().hasPrefix("off:") else { return nil }
        line = stripped.dropFirst(4).trimmingCharacters(in: .whitespaces)
        isEnabled = false
        guard !line.isEmpty else { return nil }
      }
      if let arrow = line.range(of: "->") {
        let hear = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        let write = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !hear.isEmpty, !write.isEmpty else { return nil }
        return DictionaryEntry(kind: .correction, write: String(write), hear: String(hear), isEnabled: isEnabled)
      }
      return DictionaryEntry(kind: .term, write: line, isEnabled: isEnabled)
    }
  }

  private func save() {
    revision += 1
    isSaving = true
    defer { isSaving = false }
    let body = entries.map(\.fileLine).joined(separator: "\n")
    let text = Self.header + body + "\n"
    let url = resolvedFileURL
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try? text.write(to: url, atomically: true, encoding: .utf8)
  }

  private static let header = """
    # Talkify dictionary
    #
    #   Anthropic                 a term — the engine is told this word exists
    #   cloud code -> Claude Code a correction — when you hear X, write Y
    #   # off: some rule -> Rule  a disabled entry
    #
    # Edit this file directly if you like; the app picks up changes immediately.

    """

  private func startWatching() {
    watcher?.cancel()
    let url = resolvedFileURL
    let descriptor = open(url.path, O_EVTONLY)
    guard descriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .delete, .rename, .extend],
      queue: .main
    )
    source.setEventHandler { [weak self] in
      guard let self else { return }
      if !self.isSaving { self.load() }
      self.startWatching()
    }
    source.setCancelHandler { close(descriptor) }
    source.resume()
    watcher = source
  }

  func learn(correction: DictionaryEntry) {
    guard correction.isValidForFile else { return }
    let normalizedWrite = correction.write.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedHear = correction.hear.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedWrite.isEmpty else { return }
    if correction.kind == .correction, normalizedHear.isEmpty { return }
    let exists = entries.contains {
      $0.kind == correction.kind
        && $0.write.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedWrite
        && $0.hear.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalizedHear
    }
    guard !exists else { return }
    add(correction)
  }
}
