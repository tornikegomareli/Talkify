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

  /// The visible string, committed and volatile together. Edge Glow + Draft
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
  static func originX(contentWidth: CGFloat, in bounds: CGRect, anchorsTrailing: Bool = false) -> CGFloat {
    if anchorsTrailing || (bounds.width > 0 && contentWidth > bounds.width) {
      return bounds.maxX - contentWidth
    }
    return bounds.midX - contentWidth / 2
  }

  /// How far a word is into being swallowed, 0 to 1, from where its front is:
  /// none until it reaches the mouth, all of it by the feed point.
  nonisolated static func swallowProgress(wordLeadingX x: CGFloat, mouth: CGFloat, feedX: CGFloat) -> Double {
    guard mouth > feedX else { return 0 }
    return Double(min(max((mouth - x) / (mouth - feedX), 0), 1))
  }

  /// How many tokens have reached the mouth on a line held to its trailing
  /// edge: those whose front lies left of `mouth`, measured in line
  /// coordinates where the line's room ends at `room`.
  static func reachedCount(tokenWidths: [CGFloat], room: CGFloat, mouth: CGFloat) -> Int {
    var front = room - tokenWidths.reduce(0, +)
    var reached = 0
    for width in tokenWidths {
      guard front < mouth else { break }
      reached += 1
      front += width
    }
    return reached
  }

  /// A token's width at the line's type size, for `reachedCount`.
  @MainActor
  static func width(of token: String, scale: CGFloat) -> CGFloat {
    (token as NSString).size(withAttributes: [
      .font: NSFont.systemFont(ofSize: HUDRecentDraftText.pointSize * scale, weight: .medium),
    ]).width
  }
}

/// Places each token at its ideal width so SwiftUI cannot compress them
/// separately. Overflow is then one clip of the oldest words, not eight
/// ellipses.
private struct HUDRecentDraftLineLayout: Layout {
  /// Keeps the newest word at the trailing edge even when the line fits, so a
  /// fed line moves steadily toward its feed point instead of re-centering
  /// each time it loses a word.
  var anchorsTrailing = false

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
    var x = HUDRecentDraftLine.originX(
      contentWidth: contentWidth,
      in: bounds,
      anchorsTrailing: anchorsTrailing
    )
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

/// Edge Glow + Draft's live draft: one 24-point line of recent words,
/// centered in the island when it fits. Each word keeps a stable id, so
/// only a new or departing token slides; a finalization rewrites in place.
struct HUDRecentDraftText: View {
  static let pointSize: CGFloat = 24
  /// A fed line keeps more words than the glance does. A word leaves a fed
  /// line by being eaten, so the window must not drop one that is still on
  /// its way to the feed point.
  static let fedWordLimit = 24
  /// Where swallowing begins, measured in from the line's leading edge: a word
  /// whose front reaches here has reached the mouth.
  static let mouthInset: CGFloat = 8

  let committed: String
  let volatile: String
  var scale: CGFloat = 1
  /// Colors laid across the whole line, leading to trailing, or nil for
  /// white. One gradient for the line rather than one per word, so the
  /// colors hold still while words slide through them.
  var tint: [Color]?
  /// Where something at the line's leading side takes the words in, as an
  /// offset from the line's leading center, or nil to clip them at the edge.
  /// Set, the line holds its trailing edge, and each word is swallowed as it
  /// arrives: from the moment its front reaches the mouth it shrinks toward
  /// the feed point, dips to it, and fades.
  var feed: CGSize?

  /// How far the line may draw past its leading edge.
  private var bleed: CGFloat { max(0, -(feed?.width ?? 0)) }

  @State private var lastWindow: HUDRecentDraftWindow?

  private var window: HUDRecentDraftWindow {
    HUDRecentDraftWindow(
      committed: committed,
      volatile: volatile,
      limit: feed == nil ? HUDRecentDraftWindow.wordLimit : Self.fedWordLimit
    )
  }

  var body: some View {
    let window = self.window
    let advances = lastWindow.map(window.advances(from:)) ?? false
    tinted(line(window))
      .animation(advances ? motion : nil, value: window.tokenIDs)
      .onChange(of: window) { _, new in
        lastWindow = new
      }
  }

  /// A fed line glides each push on a soft spring, so the words move toward
  /// the mouth as a stream rather than in steps.
  private var motion: Animation {
    feed == nil ? .easeOut(duration: 0.14) : .spring(response: 0.45, dampingFraction: 1)
  }

  @ViewBuilder
  private func tinted(_ line: some View) -> some View {
    if let tint {
      // Reaches past the leading edge as far as the line may draw.
      LinearGradient(colors: tint, startPoint: .leading, endPoint: .trailing)
        .padding(.leading, -bleed)
        .mask { line }
    } else {
      line
    }
  }

  private func line(_ window: HUDRecentDraftWindow) -> some View {
    HUDRecentDraftLineLayout(anchorsTrailing: feed != nil) {
      ForEach(window.visibleTokens) { token in
        swallowed(
          Text(token.text)
            .font(.system(size: Self.pointSize * scale, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        )
        .transition(.asymmetric(
          insertion: .move(edge: .trailing).combined(with: .opacity),
          // A fed line's departing word has already been eaten.
          removal: feed == nil ? .move(edge: .leading).combined(with: .opacity) : .opacity
        ))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .coordinateSpace(.named(Self.lineSpace))
    // A fed line draws past its edge, where its words are swallowed.
    .modifier(ClippedUnlessFed(isFed: feed != nil))
  }

  /// Swallowing follows the word's place in the line, so it happens as the
  /// word arrives at the mouth, however fast or slow the line is moving.
  @ViewBuilder
  private func swallowed(_ word: some View) -> some View {
    if let feed {
      let mouth = Self.mouthInset * scale
      word.visualEffect { content, proxy in
        let progress = HUDRecentDraftLine.swallowProgress(
          wordLeadingX: proxy.frame(in: .named(Self.lineSpace)).minX,
          mouth: mouth,
          feedX: feed.width
        )
        return content
          .scaleEffect(1 - 0.75 * progress, anchor: .leading)
          .offset(y: feed.height * progress)
          .opacity(1 - progress)
      }
    } else {
      word
    }
  }

  private static let lineSpace = "HUDRecentDraftLine"
}

private struct ClippedUnlessFed: ViewModifier {
  let isFed: Bool

  func body(content: Content) -> some View {
    if isFed {
      content
    } else {
      content.clipped()
    }
  }
}
