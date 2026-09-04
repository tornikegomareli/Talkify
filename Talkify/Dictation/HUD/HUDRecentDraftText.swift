import NaturalLanguage
import SwiftUI

/// The visible suffix of a live draft: the last `wordLimit` word tokens of
/// the joined committed and volatile strings. Display only — insertion still
/// uses the full transcript.
struct HUDRecentDraftWindow: Equatable {
  static let wordLimit = 8

  let committed: String
  let volatile: String
  /// Character offset of the visible suffix in the joined draft.
  /// Advances when an old word is evicted; a volatile rewrite can move it back.
  let evictionOffset: Int

  init(committed: String, volatile: String, limit: Int = Self.wordLimit) {
    let joined = committed + volatile
    guard !joined.isEmpty else {
      self.committed = ""
      self.volatile = ""
      self.evictionOffset = 0
      return
    }

    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = joined
    var tokens: [Range<String.Index>] = []
    tokenizer.enumerateTokens(in: joined.startIndex..<joined.endIndex) { range, _ in
      tokens.append(range)
      return true
    }

    let start: String.Index
    if tokens.isEmpty || tokens.count <= limit {
      start = joined.startIndex
    } else {
      start = tokens[tokens.count - limit].lowerBound
    }

    let boundary = joined.index(joined.startIndex, offsetBy: committed.count)
    if start >= boundary {
      self.committed = ""
      self.volatile = String(joined[start...])
    } else {
      self.committed = String(joined[start..<boundary])
      self.volatile = String(joined[boundary...])
    }
    self.evictionOffset = joined.distance(from: joined.startIndex, to: start)
  }
}

/// Waveform + Draft's live draft: one leading line of the recent-word
/// window, 18-point type. New text paints immediately; only a departing
/// window fades left.
struct HUDRecentDraftText: View {
  let committed: String
  let volatile: String
  var scale: CGFloat = 1

  @State private var lastEvictionOffset = 0

  private var window: HUDRecentDraftWindow {
    HUDRecentDraftWindow(committed: committed, volatile: volatile)
  }

  var body: some View {
    let window = self.window
    let movesOut = window.evictionOffset > lastEvictionOffset
    ZStack(alignment: .leading) {
      line(window)
        .id(window.evictionOffset)
        .transition(.asymmetric(
          insertion: .identity,
          removal: .offset(x: -8 * scale).combined(with: .opacity)
        ))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .clipped()
    .animation(movesOut ? .easeOut(duration: 0.13) : nil, value: window.evictionOffset)
    .onChange(of: window.evictionOffset) { _, new in
      lastEvictionOffset = new
    }
  }

  private func line(_ window: HUDRecentDraftWindow) -> some View {
    let size = 18 * scale
    var committed = AttributedString(window.committed)
    committed.font = .system(size: size, weight: .medium)
    committed.foregroundColor = .white
    var guess = AttributedString(window.volatile)
    guess.font = .system(size: size, weight: .regular)
    guess.foregroundColor = Color.white.opacity(0.55)
    return Text(committed + guess)
      .lineLimit(1)
      .truncationMode(.head)
  }
}
