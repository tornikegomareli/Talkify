import AppKit
import Foundation
import Observation

/// What the HUD is showing for Drop Transcription. Separate from
/// `DictationHUDContent` because these two never overlap: a session is either
/// dictating or handling a file, and one model holding both would be a state
/// machine pretending to be a value.
@MainActor
@Observable
final class DropHUDContent {
  enum Mode: Equatable {
    /// Not involved; the HUD belongs to dictation.
    case none
    /// A media file is being dragged toward the notch.
    case armed
    /// The file has landed and the shape is holding it. Nothing is
    /// transcribing yet: the drop is shown back to the user first, so the
    /// gesture ends with the file visibly inside the notch.
    case held
    /// A finished transcript is being offered.
    case transcript
    /// The offer is over — copied, or written to the Save-to location — and
    /// the shape says which before it retracts.
    case notice
  }

  /// The staged transcript the card offers, and the numbers it prints.
  struct Transcript: Equatable {
    let url: URL
    /// The transcript itself. The card never renders it; it is here because a
    /// drag carries it as plain text beside the file, and a click puts it on
    /// the clipboard.
    let text: String
    let wordCount: Int
    /// The source media's length, not the time transcription took.
    let duration: TimeInterval

    var name: String { url.lastPathComponent }

    /// `12:03`, and `1:02:03` once there is an hour to show.
    var durationText: String {
      let total = Int(duration.rounded())
      let seconds = total % 60
      let minutes = (total / 60) % 60
      let hours = total / 3600
      return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%d:%02d", minutes, seconds)
    }

    var wordCountText: String {
      let formatted = wordCount.formatted(.number.grouping(.automatic))
      return wordCount == 1 ? "1 word" : "\(formatted) words"
    }
  }

  var mode = Mode.none
  var isRevealed = false
  /// Peek versus open. The shape hints first and only becomes a target as the
  /// pointer reaches the notch.
  var isOpen = false
  var fileName = ""
  /// The dropped file's own icon, so what the shape holds is recognisably the
  /// thing that was dragged into it.
  var heldIcon: NSImage?
  /// Present only when a second dictation language is configured, in which
  /// case the open target splits and the drop chooses the language.
  var languageTags: [String] = []
  var transcript: Transcript?
  /// What became of the transcript, shown as the card retracts.
  var noticeText = ""
  var noticeSymbol = "checkmark.circle.fill"
  /// Drives the card's hint line. The two gestures it offers are invisible
  /// otherwise, and a permanent instruction on a five-second card is clutter.
  var isCardHovered = false
  /// Drains the five-second dismissal hairline, 1 down to 0. Frozen while the
  /// pointer is over the card.
  var remainingFraction: Double = 1
}

/// What the pointer did to the finished transcript card.
///
/// One event instead of three callbacks, because all three answer the same
/// question — whether the card's deadline still applies — and they travel
/// together through the HUD, its root view and its controller.
enum HUDCardEvent: Equatable {
  case hover(Bool)
  /// Pressed and released without dragging: the transcript is wanted as text,
  /// not as a file.
  case clicked
  case dragBegan
  /// `handled` is true when a destination accepted the file, which is the user
  /// choosing where the transcript goes.
  case dragEnded(handled: Bool)
}
