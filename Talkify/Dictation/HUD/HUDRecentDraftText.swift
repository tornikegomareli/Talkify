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

  /// How many of the oldest tokens have gone wholly past the line's leading
  /// edge, given each token's width and the room the line has. A line that
  /// fits is centered and has lost nothing.
  static func passedCount(tokenWidths: [CGFloat], room: CGFloat) -> Int {
    let overflow = tokenWidths.reduce(0, +) - room
    guard overflow > 0 else { return 0 }
    var passed = 0
    var width: CGFloat = 0
    for tokenWidth in tokenWidths {
      width += tokenWidth
      guard width <= overflow else { break }
      passed += 1
    }
    return passed
  }

  /// A token's width at the line's type size, for `passedCount`.
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

  let committed: String
  let volatile: String
  var scale: CGFloat = 1
  /// Colors laid across the whole line, leading to trailing, or nil for
  /// white. One gradient for the line rather than one per word, so the
  /// colors hold still while words slide through them.
  var tint: [Color]?
  /// Where something at the line's leading side takes the words in, as an
  /// offset from the line's leading center, or nil to clip them at the edge.
  /// Set, the line fades out toward that point instead of being cut, and a
  /// departing word shrinks into it.
  var feed: CGSize?

  /// How far the line may draw past its leading edge.
  private var bleed: CGFloat { max(0, -(feed?.width ?? 0)) }

  @State private var lastWindow: HUDRecentDraftWindow?

  private var window: HUDRecentDraftWindow {
    HUDRecentDraftWindow(committed: committed, volatile: volatile)
  }

  var body: some View {
    let window = self.window
    let animate = lastWindow.map(window.advances(from:)) ?? false
    fed(tinted(line(window)))
      .animation(animate ? .easeOut(duration: 0.14) : nil, value: window.tokenIDs)
      .onChange(of: window) { _, new in
        lastWindow = new
      }
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

  /// With a feed, the words fade from full strength just inside the leading
  /// edge to nothing at the feed point, so they vanish into it.
  @ViewBuilder
  private func fed(_ line: some View) -> some View {
    if feed != nil {
      line.mask {
        HStack(spacing: 0) {
          LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
            .frame(width: bleed + 10 * scale)
          Color.black
        }
        .padding(.leading, -bleed)
      }
    } else {
      line
    }
  }

  private var departure: AnyTransition {
    guard let feed else { return .move(edge: .leading).combined(with: .opacity) }
    return .modifier(
      active: Swallowed(target: feed, progress: 1),
      identity: Swallowed(target: feed, progress: 0)
    )
    .animation(.easeIn(duration: 0.35))
  }

  private func line(_ window: HUDRecentDraftWindow) -> some View {
    HUDRecentDraftLineLayout(anchorsTrailing: feed != nil) {
      ForEach(window.visibleTokens) { token in
        Text(token.text)
          .font(.system(size: Self.pointSize * scale, weight: .medium))
          .foregroundStyle(.white)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: departure
          ))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // A fed line draws past its edge and fades there instead of being cut.
    .modifier(ClippedUnlessFed(isFed: feed != nil))
  }
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

/// A departing word shrinking into the feed point as it fades.
private struct Swallowed: ViewModifier {
  let target: CGSize
  let progress: Double

  func body(content: Content) -> some View {
    content
      .scaleEffect(1 - 0.8 * progress, anchor: .leading)
      .offset(x: target.width * 0.8 * progress, y: target.height * progress)
      .opacity(1 - progress)
  }
}
