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
    #expect(DropZone.at(point(depth: 4), in: screen) == .open)
    #expect(DropZone.at(point(depth: 60, offset: 200), in: screen) == .open)
  }

  @Test func approachingFromBelowPeeksFirst() {
    #expect(DropZone.at(point(depth: 100), in: screen) == .peek)
    #expect(DropZone.at(point(depth: 130, offset: 400), in: screen) == .peek)
  }

  @Test func theMiddleOfTheScreenIsOutside() {
    #expect(DropZone.at(point(depth: 500), in: screen) == .outside)
  }

  /// Wide of the notch but still near the top: the catch area is generous
  /// vertically and bounded horizontally, so dragging to a menu-bar item on
  /// the far right never arms the HUD.
  @Test func theFarEdgesOfTheMenuBarAreOutside() {
    #expect(DropZone.at(point(depth: 10, offset: 700), in: screen) == .outside)
    #expect(DropZone.at(point(depth: 10, offset: -700), in: screen) == .outside)
  }

  /// Directly under the notch but too far down to receive: it hints, it does
  /// not take the drop.
  @Test func justBelowTheOpenBandOnlyPeeks() {
    #expect(DropZone.at(point(depth: DropZone.openHeight + 1), in: screen) == .peek)
  }

  /// A pointer above the top edge happens on a display whose frame sits below
  /// another one; it is not this display's business.
  @Test func aboveTheTopEdgeIsOutside() {
    #expect(DropZone.at(point(depth: -5), in: screen) == .outside)
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
  private func card(words: Int, seconds: TimeInterval) -> HUDDropContent.Transcript {
    HUDDropContent.Transcript(
      url: URL(filePath: "/tmp/memo.txt"),
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
