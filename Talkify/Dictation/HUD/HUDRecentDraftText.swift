import NaturalLanguage
import SwiftUI

/// The visible suffix of a live draft: the last `wordLimit` word tokens of
/// the joined committed and volatile strings. Display only — insertion still
/// uses the full transcript.
struct HUDRecentDraftWindow: Equatable {
  static let wordLimit = 8

  struct VisibleToken: Equatable, Identifiable {
    /// Index in the full joined draft, not in the window, so a word that
    /// stays on screen keeps its identity across evictions and rewrites.
    let id: Int
    let text: String
  }

  let committed: String
  let volatile: String
  /// Character offset of the visible suffix in the joined draft.
  /// Advances when an old word is evicted; a volatile rewrite can move it back.
  let evictionOffset: Int
  /// Word tokens in the joined draft, not the clipped window. A new word
  /// raises this; an in-token volatile rewrite does not.
  let tokenCount: Int
  /// Visible slices, each carrying trailing whitespace through the next
  /// token so a ForEach can keep surviving words in place.
  let visibleTokens: [VisibleToken]

  /// The visible string, committed and volatile together. Waveform + Draft
  /// paints them the same: the line is a glance, not a proofread.
  var displayString: String { committed + volatile }

  var tokenIDs: [Int] { visibleTokens.map(\.id) }

  /// A new word or an eviction, not a volatile rewrite inside the current
  /// token. Backward corrections snap; they must not linger behind a fade.
  func advances(from previous: Self) -> Bool {
    tokenCount > previous.tokenCount || evictionOffset > previous.evictionOffset
  }

  init(committed: String, volatile: String, limit: Int = Self.wordLimit) {
    let joined = committed + volatile
    guard !joined.isEmpty else {
      self.committed = ""
      self.volatile = ""
      self.evictionOffset = 0
      self.tokenCount = 0
      self.visibleTokens = []
      return
    }

    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = joined
    var tokens: [Range<String.Index>] = []
    tokenizer.enumerateTokens(in: joined.startIndex..<joined.endIndex) { range, _ in
      tokens.append(range)
      return true
    }
    tokenCount = tokens.count

    let start: String.Index
    let firstVisible: Int
    if tokens.isEmpty || tokens.count <= limit {
      start = joined.startIndex
      firstVisible = 0
    } else {
      firstVisible = tokens.count - limit
      start = tokens[firstVisible].lowerBound
    }

    if tokens.isEmpty {
      visibleTokens = [VisibleToken(id: 0, text: joined)]
    } else {
      var slices: [VisibleToken] = []
      for index in firstVisible..<tokens.count {
        let sliceStart = index == firstVisible ? start : tokens[index].lowerBound
        let sliceEnd = index + 1 < tokens.count
          ? tokens[index + 1].lowerBound : joined.endIndex
        slices.append(VisibleToken(
          id: index,
          text: String(joined[sliceStart..<sliceEnd])
        ))
      }
      visibleTokens = slices
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

/// Origin of a recent-draft line inside the island. A line that fits is
/// centered; one that does not keeps the newest words and lets the oldest
/// overflow the leading edge. Independent per-word ellipses are rejected:
/// they turn an ordinary eight-word glance into fragments.
enum HUDRecentDraftLine {
  static func originX(contentWidth: CGFloat, in bounds: CGRect) -> CGFloat {
    if bounds.width > 0, contentWidth > bounds.width {
      return bounds.maxX - contentWidth
    }
    return bounds.midX - contentWidth / 2
  }
}

/// Places each token at its ideal width so SwiftUI cannot compress them
/// separately. Overflow is then one clip of the oldest words, not eight
/// ellipses.
private struct HUDRecentDraftLineLayout: Layout {
  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) -> CGSize {
    let content = contentSize(subviews)
    return CGSize(
      width: proposal.width ?? content.width,
      height: proposal.height ?? content.height
    )
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) {
    let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    let contentWidth = sizes.reduce(CGFloat.zero) { $0 + $1.width }
    var x = HUDRecentDraftLine.originX(contentWidth: contentWidth, in: bounds)
    for (subview, size) in zip(subviews, sizes) {
      subview.place(
        at: CGPoint(x: x, y: bounds.midY - size.height / 2),
        anchor: .topLeading,
        proposal: ProposedViewSize(size)
      )
      x += size.width
    }
  }

  private func contentSize(_ subviews: Subviews) -> CGSize {
    subviews.reduce(into: CGSize.zero) { acc, subview in
      let size = subview.sizeThatFits(.unspecified)
      acc.width += size.width
      acc.height = max(acc.height, size.height)
    }
  }
}

/// Waveform + Draft's live draft: one 24-point line of recent words,
/// centered in the island when it fits. Each word keeps a stable id, so
/// only a new or departing token slides; a finalization rewrites in place.
struct HUDRecentDraftText: View {
  static let pointSize: CGFloat = 24

  let committed: String
  let volatile: String
  var scale: CGFloat = 1

  @State private var lastWindow: HUDRecentDraftWindow?

  private var window: HUDRecentDraftWindow {
    HUDRecentDraftWindow(committed: committed, volatile: volatile)
  }

  var body: some View {
    let window = self.window
    let animate = lastWindow.map(window.advances(from:)) ?? false
    HUDRecentDraftLineLayout {
      ForEach(window.visibleTokens) { token in
        Text(token.text)
          .font(.system(size: Self.pointSize * scale, weight: .medium))
          .foregroundStyle(.white)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
          ))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
    .animation(animate ? .easeOut(duration: 0.14) : nil, value: window.tokenIDs)
    .onChange(of: window) { _, new in
      lastWindow = new
    }
  }
}
