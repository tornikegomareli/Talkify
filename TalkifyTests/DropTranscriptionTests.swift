import AppKit
import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Talkify

@Suite("Media file types")
struct MediaFileTypesTests {
  @Test(arguments: ["memo.m4a", "podcast.mp3", "take.wav", "note.aiff", "clip.mp4", "screen.mov"])
  func audioAndVideoAreTranscribable(name: String) {
    #expect(MediaFileTypes.isTranscribable(url: URL(filePath: "/tmp/\(name)")))
  }

  @Test(arguments: ["paper.pdf", "notes.txt", "shot.png", "archive.zip"])
  func everythingElseIsNot(name: String) {
    #expect(!MediaFileTypes.isTranscribable(url: URL(filePath: "/tmp/\(name)")))
  }

  /// A drag can carry a folder, and a folder conforms to neither parent type.
  @Test func aFolderIsNotTranscribable() {
    #expect(!MediaFileTypes.isTranscribable(.folder))
    #expect(!MediaFileTypes.isTranscribable(nil))
  }

  /// The extension is only the fallback, so a file with none at all has to
  /// resolve to nothing rather than to some default.
  @Test func anExtensionlessNameResolvesToNothing() {
    #expect(!MediaFileTypes.isTranscribable(url: URL(filePath: "/tmp/recording")))
  }
}

@Suite("Transcript destination")
struct TranscriptDestinationTests {
  private let source = URL(filePath: "/Users/x/Recordings/memo.m4a")
  private let desktop = URL(filePath: "/Users/x/Desktop")
  private let chosen = URL(filePath: "/Users/x/Transcripts")

  /// A directory URL renders with a trailing slash and a file URL without, so
  /// the fake normalizes; the live probe hands both to FileManager, which does
  /// not care either way.
  private func probe(
    writable: Set<String> = [],
    existing: Set<String> = []
  ) -> TranscriptDestination.Probe {
    let key: @Sendable (URL) -> String = { url in
      let path = url.path(percentEncoded: false)
      return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
    return TranscriptDestination.Probe(
      isDirectoryWritable: { writable.contains(key($0)) },
      fileExists: { existing.contains(key($0)) }
    )
  }

  @Test func besideTheSourceByDefault() {
    let url = TranscriptDestination.resolve(
      for: source,
      preference: .besideSource,
      chosenFolder: chosen,
      desktop: desktop,
      probe: probe(writable: ["/Users/x/Recordings", "/Users/x/Transcripts", "/Users/x/Desktop"])
    )
    #expect(url.path(percentEncoded: false) == "/Users/x/Recordings/memo.txt")
  }

  @Test func theChosenFolderWinsWhenItIsThePick() {
    let url = TranscriptDestination.resolve(
      for: source,
      preference: .chosenFolder,
      chosenFolder: chosen,
      desktop: desktop,
      probe: probe(writable: ["/Users/x/Recordings", "/Users/x/Transcripts", "/Users/x/Desktop"])
    )
    #expect(url.path(percentEncoded: false) == "/Users/x/Transcripts/memo.txt")
  }

  /// A source on a read-only volume or a mounted image: the transcript still
  /// has to land somewhere the user can find it.
  @Test func anUnwritableSourceFallsBackToTheChosenFolder() {
    let url = TranscriptDestination.resolve(
      for: source,
      preference: .besideSource,
      chosenFolder: chosen,
      desktop: desktop,
      probe: probe(writable: ["/Users/x/Transcripts", "/Users/x/Desktop"])
    )
    #expect(url.path(percentEncoded: false) == "/Users/x/Transcripts/memo.txt")
  }

  @Test func withNothingElseWritableItFallsBackToTheDesktop() {
    let url = TranscriptDestination.resolve(
      for: source,
      preference: .besideSource,
      chosenFolder: nil,
      desktop: desktop,
      probe: probe(writable: ["/Users/x/Desktop"])
    )
    #expect(url.path(percentEncoded: false) == "/Users/x/Desktop/memo.txt")
  }

  /// The second run of a file is usually the one being compared against the
  /// first, so a transcript must never overwrite an earlier one.
  @Test func acollidingNameIsUniqued() {
    let url = TranscriptDestination.resolve(
      for: source,
      preference: .besideSource,
      chosenFolder: nil,
      desktop: desktop,
      probe: probe(
        writable: ["/Users/x/Recordings"],
        existing: ["/Users/x/Recordings/memo.txt", "/Users/x/Recordings/memo-2.txt"]
      )
    )
    #expect(url.path(percentEncoded: false) == "/Users/x/Recordings/memo-3.txt")
  }

  @Test func theDestinationKeepsTheSourceNameWithoutItsExtension() {
    let url = TranscriptDestination.resolve(
      for: URL(filePath: "/Users/x/Movies/Screen Recording 2026.mov"),
      preference: .besideSource,
      chosenFolder: nil,
      desktop: desktop,
      probe: probe(writable: ["/Users/x/Movies"])
    )
    #expect(url.lastPathComponent == "Screen Recording 2026.txt")
  }
}

@Suite("Drop zone")
struct DropZoneTests {
  /// A 1512×982 display with its origin at zero, so the top edge is y = 982.
  private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

  private func point(depth: CGFloat, offset: CGFloat = 0) -> CGPoint {
    CGPoint(x: screen.midX + offset, y: screen.maxY - depth)
  }

  @Test func rightAtTheNotchIsOpen() {
    #expect(DropZone.next(after: .outside, at: point(depth: 4), in: screen) == .open)
    #expect(DropZone.next(after: .outside, at: point(depth: 60, offset: 200), in: screen) == .open)
  }

  @Test func approachingFromBelowPeeksFirst() {
    #expect(DropZone.next(after: .outside, at: point(depth: 100), in: screen) == .peek)
    #expect(DropZone.next(after: .outside, at: point(depth: 130, offset: 400), in: screen) == .peek)
  }

  @Test func theMiddleOfTheScreenIsOutside() {
    #expect(DropZone.next(after: .outside, at: point(depth: 500), in: screen) == .outside)
  }

  /// Wide of the notch but still near the top: the catch area is generous
  /// vertically and bounded horizontally, so dragging to a menu-bar item on
  /// the far right never arms the HUD.
  @Test func theFarEdgesOfTheMenuBarAreOutside() {
    #expect(DropZone.next(after: .outside, at: point(depth: 10, offset: 700), in: screen) == .outside)
    #expect(DropZone.next(after: .outside, at: point(depth: 10, offset: -700), in: screen) == .outside)
  }

  /// Directly under the notch but too far down to receive: it hints, it does
  /// not take the drop.
  @Test func justBelowTheOpenBandOnlyPeeks() {
    #expect(DropZone.next(after: .outside, at: point(depth: DropZone.openHeight + 1), in: screen) == .peek)
  }

  /// A pointer above the top edge happens on a display whose frame sits below
  /// another one; it is not this display's business.
  @Test func aboveTheTopEdgeIsOutside() {
    #expect(DropZone.next(after: .outside, at: point(depth: -5), in: screen) == .outside)
  }

  /// The bug this hysteresis exists for: the band that opens the target is a
  /// narrow strip, but the shape it opens is far bigger, so judging both with
  /// one number closed the target while the pointer was still on it.
  @Test func anOpenTargetHoldsWhileThePointerIsStillOnTheShape() {
    for depth in [70.0, 110.0, 165.0] {
      #expect(DropZone.next(after: .open, at: point(depth: depth), in: screen) == .open)
    }
    #expect(DropZone.next(after: .open, at: point(depth: 60, offset: 300), in: screen) == .open)
  }

  /// It gives up only once the pointer is genuinely clear of the shape, and
  /// it goes straight out rather than back to a hint: collapsing while the
  /// user is still aiming at it reads as the target refusing them.
  @Test func anOpenTargetLetsGoOnlyWhenTheDragLeaves() {
    #expect(DropZone.next(after: .open, at: point(depth: 200), in: screen) == .outside)
    #expect(DropZone.next(after: .open, at: point(depth: 60, offset: 400), in: screen) == .outside)
  }

  /// A peek is still free to grow into the target or fall away; only the open
  /// state is sticky.
  @Test func aPeekStillProgresses() {
    #expect(DropZone.next(after: .peek, at: point(depth: 10), in: screen) == .open)
    #expect(DropZone.next(after: .peek, at: point(depth: 300), in: screen) == .outside)
  }
}

@MainActor
@Suite("Reading the drag pasteboard")
struct DragWatcherTests {
  private func pasteboard(_ urls: [URL], name: String) -> NSPasteboard {
    let board = NSPasteboard(name: NSPasteboard.Name("com.tgomareli.Talkify.test.\(name)"))
    board.clearContents()
    board.writeObjects(urls as [NSURL])
    return board
  }

  @Test func oneMediaFileIsPickedUp() {
    let url = URL(filePath: "/tmp/memo.m4a")
    #expect(DragWatcher.transcribableURL(on: pasteboard([url], name: "one")) == url)
  }

  @Test func aNonMediaFileIsIgnored() {
    let url = URL(filePath: "/tmp/paper.pdf")
    #expect(DragWatcher.transcribableURL(on: pasteboard([url], name: "pdf")) == nil)
  }

  /// Guessing which of several files was meant is worse than declining, and
  /// only one job runs at a time anyway.
  @Test func aMultipleFileDragIsRefused() {
    let urls = [URL(filePath: "/tmp/a.m4a"), URL(filePath: "/tmp/b.m4a")]
    #expect(DragWatcher.transcribableURL(on: pasteboard(urls, name: "many")) == nil)
  }

  @Test func anEmptyDragIsIgnored() {
    let board = NSPasteboard(name: NSPasteboard.Name("com.tgomareli.Talkify.test.empty"))
    board.clearContents()
    #expect(DragWatcher.transcribableURL(on: board) == nil)
  }
}

@MainActor
@Suite("Drop Transcription preferences")
struct DropTranscriptionSettingsTests {
  private func freshDefaults() -> UserDefaults {
    let name = "com.tgomareli.Talkify.tests.drop"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
  }

  @Test func transcriptsSaveBesideTheSourceByDefault() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(settings.transcriptDestination == .besideSource)
    #expect(settings.transcriptFolder == nil)
  }

  @Test func theDestinationAndFolderSurviveARelaunch() {
    let defaults = freshDefaults()
    let settings = AppSettings(defaults: defaults)
    settings.transcriptDestination = .chosenFolder
    settings.transcriptFolder = URL(filePath: "/Users/x/Transcripts")

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.transcriptDestination == .chosenFolder)
    #expect(reloaded.transcriptFolder?.path(percentEncoded: false) == "/Users/x/Transcripts")
    #expect(defaults.string(forKey: "transcriptDestination") == "Chosen folder")
  }

  /// One language means an undivided target and the primary language always.
  @Test func oneLanguageLeavesTheTargetWhole() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.recognitionLocaleIdentifier = "en-US"
    #expect(settings.languageTagsForDrop.isEmpty)
    #expect(settings.localeIdentifierForDrop(languageIndex: 0) == "en-US")
    #expect(settings.localeIdentifierForDrop(languageIndex: 1) == "en-US")
  }

  /// With two configured, the half the file lands on is the language choice.
  @Test func twoLanguagesSplitTheTargetAndTheDropPicks() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.recognitionLocaleIdentifier = "en-US"
    settings.secondaryRecognitionLocaleIdentifier = "ka-GE"

    #expect(settings.languageTagsForDrop == ["EN", "KA"])
    #expect(settings.localeIdentifierForDrop(languageIndex: 0) == "en-US")
    #expect(settings.localeIdentifierForDrop(languageIndex: 1) == "ka-GE")
  }
}

@Suite("Transcript card numbers")
struct TranscriptCardTests {
  private func card(words: Int, seconds: TimeInterval) -> DropHUDContent.Transcript {
    DropHUDContent.Transcript(
      url: URL(filePath: "/tmp/memo.txt"),
      text: "",
      wordCount: words,
      duration: seconds
    )
  }

  @Test func minutesAndSecondsAreZeroPadded() {
    #expect(card(words: 1, seconds: 723).durationText == "12:03")
    #expect(card(words: 1, seconds: 61).durationText == "1:01")
  }

  @Test func anHourGetsItsOwnField() {
    #expect(card(words: 1, seconds: 3723).durationText == "1:02:03")
  }

  @Test func oneWordIsNotPluralised() {
    #expect(card(words: 1, seconds: 0).wordCountText == "1 word")
    #expect(card(words: 2, seconds: 0).wordCountText.hasSuffix("words"))
  }
}

@Suite("Staged transcripts")
struct StagedTranscriptTests {
  private let source = URL(filePath: "/Users/x/Recordings/memo.m4a")

  /// Each test gets its own staging root and its own destination, and both are
  /// real directories: staging, moving and cleaning up are the behavior under
  /// test, so faking the filesystem would test nothing.
  private func scratch(_ name: String) throws -> URL {
    let directory = URL.temporaryDirectory
      .appending(path: "TalkifyTests-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  /// A transcript is the user's speech in cleartext and Talkify is
  /// unsandboxed, so nothing else running as the same user should be able to
  /// open it while it waits on the card.
  @Test func stagedFilesAreReadableOnlyByTheirOwner() throws {
    let root = try scratch("permissions")
    defer { try? FileManager.default.removeItem(at: root) }

    let staged = try StagedTranscript.stage(text: "private", source: source, root: root)

    let file = try FileManager.default.attributesOfItem(atPath: staged.url.path)
    #expect(file[.posixPermissions] as? Int == 0o600)
    let directory = try FileManager.default.attributesOfItem(
      atPath: staged.url.deletingLastPathComponent().path
    )
    #expect(directory[.posixPermissions] as? Int == 0o700)
  }

  /// The gap this closes: cleanup only ran on commit or discard, so a crash
  /// with a card on screen left the transcript under $TMPDIR forever.
  @Test func sweepingClearsWhatACrashWouldHaveLeftBehind() throws {
    let root = try scratch("sweep")
    defer { try? FileManager.default.removeItem(at: root) }

    let staged = try StagedTranscript.stage(text: "stranded", source: source, root: root)
    #expect(FileManager.default.fileExists(atPath: staged.url.path))

    StagedTranscript.sweep(root: root)

    #expect(!FileManager.default.fileExists(atPath: staged.url.path))
    #expect(!FileManager.default.fileExists(atPath: root.path))
  }

  /// Sweeping runs at launch on a root that usually is not there, and staging
  /// has to work straight afterwards.
  @Test func sweepingAnAbsentRootIsHarmlessAndStagingStillWorks() throws {
    let root = try scratch("absent")
    try FileManager.default.removeItem(at: root)
    defer { try? FileManager.default.removeItem(at: root) }

    StagedTranscript.sweep(root: root)
    let staged = try StagedTranscript.stage(text: "after", source: source, root: root)

    #expect(try String(contentsOf: staged.url, encoding: .utf8) == "after")
  }

  /// A root replaced by a symlink would put the transcript wherever that link
  /// points, so staging replaces it with a real directory instead.
  @Test func aSymlinkedRootIsReplacedRatherThanFollowed() throws {
    let parent = try scratch("symlink")
    defer { try? FileManager.default.removeItem(at: parent) }
    let elsewhere = parent.appending(path: "elsewhere")
    try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
    let root = parent.appending(path: "root")
    try FileManager.default.createSymbolicLink(at: root, withDestinationURL: elsewhere)

    let staged = try StagedTranscript.stage(text: "safe", source: source, root: root)

    #expect(staged.url.path.hasPrefix(root.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
  }

  /// Staged under the name it will keep, so what the user drags is already
  /// called what it will be called wherever they drop it.
  @Test func stagingKeepsTheNameTheTranscriptWillHave() throws {
    let root = try scratch("name")
    defer { try? FileManager.default.removeItem(at: root) }

    let staged = try StagedTranscript.stage(text: "one two", source: source, root: root)

    #expect(staged.url.lastPathComponent == "memo.txt")
    #expect(try String(contentsOf: staged.url, encoding: .utf8) == "one two")
  }

  /// Two jobs can hold the same source name, and neither may see the other's
  /// file, so each stages into a folder of its own.
  @Test func twoStagedTranscriptsDoNotCollide() throws {
    let root = try scratch("collide")
    defer { try? FileManager.default.removeItem(at: root) }

    let first = try StagedTranscript.stage(text: "first", source: source, root: root)
    let second = try StagedTranscript.stage(text: "second", source: source, root: root)

    #expect(first.url != second.url)
    #expect(try String(contentsOf: first.url, encoding: .utf8) == "first")
    #expect(try String(contentsOf: second.url, encoding: .utf8) == "second")
  }

  /// Committing is what happens when the card is not taken: the file moves to
  /// the Save-to location and the staging folder goes away.
  @Test func committingMovesTheFileAndClearsTheStagingFolder() throws {
    let root = try scratch("commit")
    let folder = try scratch("commit-destination")
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: folder)
    }

    let staged = try StagedTranscript.stage(text: "kept", source: source, root: root)
    let destination = try staged.commit(preference: .chosenFolder, chosenFolder: folder)

    #expect(destination.lastPathComponent == "memo.txt")
    #expect(destination.deletingLastPathComponent().path == folder.path)
    #expect(try String(contentsOf: destination, encoding: .utf8) == "kept")
    #expect(!FileManager.default.fileExists(atPath: staged.url.path))
    #expect(!FileManager.default.fileExists(atPath: staged.url.deletingLastPathComponent().path))
  }

  /// The second run of a file is usually the one being compared against the
  /// first, so committing must never overwrite an earlier transcript.
  @Test func committingOverAnExistingTranscriptUniquesTheName() throws {
    let root = try scratch("unique")
    let folder = try scratch("unique-destination")
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: folder)
    }
    try "earlier".write(to: folder.appending(path: "memo.txt"), atomically: true, encoding: .utf8)

    let staged = try StagedTranscript.stage(text: "later", source: source, root: root)
    let destination = try staged.commit(preference: .chosenFolder, chosenFolder: folder)

    #expect(destination.lastPathComponent == "memo-2.txt")
  }

  /// Discarding is what happens when a drag lands: the transcript is the
  /// user's now, wherever they put it, and Talkify keeps no copy (CONTEXT.md).
  @Test func discardingRemovesEverythingStaged() throws {
    let root = try scratch("discard")
    defer { try? FileManager.default.removeItem(at: root) }

    let staged = try StagedTranscript.stage(text: "gone", source: source, root: root)
    staged.discard()

    #expect(!FileManager.default.fileExists(atPath: staged.url.deletingLastPathComponent().path))
    // Called again after a drag already moved the file out, which is the usual
    // case on a same-volume destination.
    staged.discard()
  }
}

@MainActor
@Suite("Drop HUD symbols")
struct DropHUDSymbolTests {
  /// SF Symbol names are strings the compiler never sees. A name that does not
  /// resolve draws nothing at all, which is invisible in a diff and obvious on
  /// screen, so every name the drop surfaces use is checked against this Mac.
  @Test(arguments: [
    DropHUDStyle.transcriptSymbol,
    "waveform",
    "arrow.up.forward",
    "hand.point.up.left.fill",
    "checkmark.circle.fill",
    "folder.fill",
  ])
  func everySymbolTheDropHUDUsesResolves(name: String) {
    #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil)
  }
}

@Suite("Transcript word count")
struct TranscriptTests {
  @Test func wordsAreCountedAcrossWhitespaceAndNewlines() {
    let transcript = FileTranscriptionService.Transcript(
      text: "one two  three\nfour\tfive",
      duration: 12
    )
    #expect(transcript.wordCount == 5)
  }

  @Test func anEmptyTranscriptCountsNothing() {
    #expect(FileTranscriptionService.Transcript(text: "", duration: 0).wordCount == 0)
  }
}
