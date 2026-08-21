import Foundation
import Testing
@testable import Talkify

@MainActor
struct MyVoiceCaptureTests {
  private func freshDefaults() -> UserDefaults {
    let name = "MyVoiceCaptureTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  @Test func captureDisabledByDefault() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(!settings.myvoiceCaptureEnabled)
  }

  @Test func capturePersistsThroughUserDefaults() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    #expect(!settings.myvoiceCaptureEnabled)
    settings.myvoiceCaptureEnabled = true
    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.myvoiceCaptureEnabled)
    #expect(defaults.object(forKey: "myvoiceCaptureEnabled") as? Bool == true)
    settings.myvoiceCaptureEnabled = false
    let reloaded2 = AppSettings(defaults: defaults)
    #expect(!reloaded2.myvoiceCaptureEnabled)
  }

  @Test func sessionSettingsCapturesMyVoiceFlag() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    settings.myvoiceCaptureEnabled = true
    #expect(settings.sessionSettings.myvoiceCaptureEnabled)
    settings.myvoiceCaptureEnabled = false
    #expect(!settings.sessionSettings.myvoiceCaptureEnabled)
    let snapshot = settings.sessionSettings
    settings.myvoiceCaptureEnabled = true
    #expect(!snapshot.myvoiceCaptureEnabled)
  }

  @Test func directCollectorCreatesCandidateWithRawAndCorrected() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MyVoiceDirect-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = MyVoiceStorage(rootURL: root)
    let collector = MyVoiceCollector(storage: storage)
    let startedAt = Date()
    let stoppedAt = startedAt.addingTimeInterval(1.2)
    let record = try collector.collect(
      rawTranscript: "hello world",
      correctedText: "Hello, world.",
      audioURL: nil,
      startedAt: startedAt,
      stoppedAt: stoppedAt,
      locale: "en-US"
    )
    #expect(record.status == .candidate)
    #expect(record.transcript.asrText == "hello world")
    #expect(record.transcript.correctedText == "Hello, world.")
    #expect(record.provenance.locale == "en-US")
    #expect(record.provenance.sttProvider == "apple_speech")
    #expect(record.audio.sha256 == MyVoiceAudioHelper.emptySHA256)
    let sampleID = record.id
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples/\(sampleID)/record.json").path))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("samples/\(sampleID)/transcript/asr.txt").path))
    let asr = try String(contentsOf: root.appendingPathComponent("samples/\(sampleID)/transcript/asr.txt"), encoding: .utf8)
    #expect(asr == "hello world")
    let corrected = try String(contentsOf: root.appendingPathComponent("samples/\(sampleID)/transcript/corrected.txt"), encoding: .utf8)
    #expect(corrected == "Hello, world.")
    let events = try storage.readEvents()
    #expect(events.contains(where: { $0["type"] == "created" && $0["sample_id"] == sampleID }))
  }

  @Test func directCollectorEditableDraftPreservesRawAndStoresCorrected() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MyVoiceDirect-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let collector = MyVoiceCollector(rootURL: root)
    let record = try collector.collect(
      rawTranscript: "we can sort the array in increasing order",
      correctedText: "We can sort the array in increasing order.",
      audioURL: nil,
      startedAt: Date(timeIntervalSinceNow: -2.0),
      stoppedAt: Date()
    )
    #expect(record.transcript.asrText == "we can sort the array in increasing order")
    #expect(record.transcript.correctedText == "We can sort the array in increasing order.")
    #expect(record.transcript.asrText != record.transcript.correctedText)
    let asr = try String(contentsOf: root.appendingPathComponent("samples/\(record.id)/transcript/asr.txt"), encoding: .utf8)
    let corrected = try String(contentsOf: root.appendingPathComponent("samples/\(record.id)/transcript/corrected.txt"), encoding: .utf8)
    #expect(asr == "we can sort the array in increasing order")
    #expect(corrected == "We can sort the array in increasing order.")
  }

  @Test func directCollectorFailureCleansTmp() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MyVoiceDirect-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = MyVoiceStorage(rootURL: root)
    storage.setNextCommitShouldFail(true)
    let collector = MyVoiceCollector(storage: storage)
    #expect(throws: (any Error).self) {
      try collector.collect(
        rawTranscript: "hello",
        correctedText: "hello",
        audioURL: nil,
        startedAt: Date(timeIntervalSinceNow: -1),
        stoppedAt: Date()
      )
    }
    let stats = try storage.computeStats()
    #expect(stats.total == 0)
    #expect(try storage.listTmpDirectories().isEmpty)
  }

  @Test func captureServiceSkipsEmptyTranscript() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MyVoiceDirect-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = MyVoiceStorage(rootURL: root)
    let collector = MyVoiceCollector(storage: storage)
    let service = MyVoiceCaptureService(collector: collector, enabled: { true })
    service.capture(
      rawTranscript: "   ",
      correctedText: "   ",
      audioURL: nil,
      startedAt: Date(timeIntervalSinceNow: -1),
      stoppedAt: Date(),
      localeIdentifier: "en-US"
    )
    try? await Task.sleep(for: .milliseconds(200))
    let stats = try storage.computeStats()
    #expect(stats.total == 0)
  }

  @Test func captureServiceSkipsWhenDisabled() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MyVoiceDirect-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = MyVoiceStorage(rootURL: root)
    let collector = MyVoiceCollector(storage: storage)
    let service = MyVoiceCaptureService(collector: collector, enabled: { false })
    service.capture(
      rawTranscript: "hello world",
      correctedText: "hello world",
      audioURL: nil,
      startedAt: Date(timeIntervalSinceNow: -1),
      stoppedAt: Date(),
      localeIdentifier: "en-US"
    )
    try? await Task.sleep(for: .milliseconds(200))
    let stats = try storage.computeStats()
    #expect(stats.total == 0)
  }

  @Test func captureServiceIsNonBlockingEvenWhenStorageFails() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MyVoiceDirect-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = MyVoiceStorage(rootURL: root)
    storage.setNextCommitShouldFail(true)
    let collector = MyVoiceCollector(storage: storage)
    let service = MyVoiceCaptureService(collector: collector, enabled: { true })
    let before = Date()
    service.capture(
      rawTranscript: "hello world",
      correctedText: "hello world",
      audioURL: nil,
      startedAt: Date(timeIntervalSinceNow: -1),
      stoppedAt: Date(),
      localeIdentifier: "en-US"
    )
    let elapsed = Date().timeIntervalSince(before)
    #expect(elapsed < 0.1)
    try? await Task.sleep(for: .milliseconds(300))
    let stats = try storage.computeStats()
    #expect(stats.total == 0)
    #expect(try storage.listTmpDirectories().isEmpty)
  }

  @Test func captureServiceCreatesCandidateWhenEnabled() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("MyVoiceDirect-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = MyVoiceStorage(rootURL: root)
    let collector = MyVoiceCollector(storage: storage)
    let service = MyVoiceCaptureService(collector: collector, enabled: { true })
    service.capture(
      rawTranscript: "hello world",
      correctedText: "Hello, world.",
      audioURL: nil,
      startedAt: Date(timeIntervalSinceNow: -1),
      stoppedAt: Date(),
      localeIdentifier: "en-US"
    )
    var record: MyVoiceRecord?
    for _ in 0..<20 {
      try? await Task.sleep(for: .milliseconds(50))
      let records = try storage.listRecords()
      if let first = records.first { record = first; break }
    }
    let r = try #require(record)
    #expect(r.transcript.asrText == "hello world")
    #expect(r.transcript.correctedText == "Hello, world.")
    #expect(r.audio.sha256 == MyVoiceAudioHelper.emptySHA256)
  }
}
