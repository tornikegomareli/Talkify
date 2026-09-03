/// The session's shaping pick and the two picks the arrows would land on.
///
/// The HUD draws all three, the neighbours faintly to either side, so the
/// arrows need no glyphs of their own: what Left would land on is literally
/// drawn on the left. That means the band needs the cycling order, not just
/// the current name, which is why this carries the whole list.
struct ShapingChoice: Equatable {
  /// Every pick in cycling order, None last. Never empty.
  let options: [String]
  /// Which pick the session holds now.
  let index: Int
  /// Which way the last arrow moved it: 1 for Right, -1 for Left, 0 before
  /// any press. The band slides the names the way the press moved them, so a
  /// press reads as motion in the direction pressed rather than as a swap.
  let direction: Int

  /// The label for the pick that shapes nothing.
  static let none = "None"

  /// Built from a session's library and its current pick, or nil when the
  /// session cannot cycle at all.
  ///
  /// The None option is appended here rather than stored in the library: it
  /// is a position in the cycle, not a prompt anybody can edit.
  init?(library: [ShapingPrompt], selected: ShapingPrompt?, direction: Int = 0) {
    guard !library.isEmpty else { return nil }
    options = library.map(\.name) + [Self.none]
    // A selected prompt the library no longer carries lands on None, which is
    // what an unresolved pick already inserts.
    index = selected.flatMap { pick in library.firstIndex { $0.id == pick.id } } ?? library.count
    self.direction = direction
  }

  var current: String { option(at: 0) }
  var previous: String { option(at: -1) }
  var next: String { option(at: 1) }

  /// Wraps both ways, because the cycle wraps: from None, Right returns to
  /// the first prompt. With a single prompt the two neighbours are the same
  /// option, which is true — both arrows land there.
  private func option(at offset: Int) -> String {
    guard !options.isEmpty else { return "" }
    let count = options.count
    return options[((index + offset) % count + count) % count]
  }
}
