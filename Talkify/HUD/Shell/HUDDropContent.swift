import Foundation
import Observation

/// What the HUD is showing for Drop Transcription. Separate from
/// `DictationHUDContent` because these two never overlap: a session is either
/// dictating or handling a file, and one model holding both would be a state
/// machine pretending to be a value.
@MainActor
@Observable
final class HUDDropContent {
  enum Mode: Equatable {
    /// Not involved; the HUD belongs to dictation.
    case none
    /// A media file is being dragged toward the notch.
    case armed
    /// A finished transcript is being offered.
    case transcript
  }

  /// The written transcript the card offers, and the numbers it prints.
  struct Transcript: Equatable {
    let url: URL
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
  /// Present only when a second dictation language is configured, in which
  /// case the open target splits and the drop chooses the language.
  var languageTags: [String] = []
  var transcript: Transcript?
  /// Drains the five-second dismissal hairline, 1 down to 0. Frozen while the
  /// pointer is over the card.
  var remainingFraction: Double = 1
}
