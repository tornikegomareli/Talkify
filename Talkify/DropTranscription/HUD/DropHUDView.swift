import SwiftUI

/// The Drop Transcription face of the HUD: the shape, the size it takes for
/// each state, and which state view goes inside it.
///
/// It renders inside `HUDSurface`, so it inherits the black shape, the fillets
/// and the housing band the dictation shell uses. No voice visual — nothing is
/// listening.
struct DropHUDView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let screen: HUDScreenSnapshot
  let settings: DictationSessionSettings
  let drop: DropHUDContent
  /// The index is which half took the drop, which is the language choice when
  /// the target is split. No URL: the drop is answered without reading one.
  var onDrop: (Int) -> Void = { _ in }
  var onCardEvent: (HUDCardEvent) -> Void = { _ in }
  /// Drop handling is an interactive layer `ImageRenderer` cannot draw, so the
  /// render harness turns it off to photograph the surface itself.
  var acceptsDrops = true

  private var style: DropHUDStyle { DropHUDStyle(settings: settings) }
  private var metrics: HUDMetrics { style.metrics }

  private var housingHeight: CGFloat {
    HUDNotchGeometry.closedSize(for: screen).height
  }

  /// The strip below the housing. Explicit rather than expanding: the host
  /// window is sized for the tallest layout, so anything greedy about height
  /// fills the window instead of the shape.
  private var bodyHeight: CGFloat {
    max(size.height - housingHeight, 0)
  }

  /// The peek is a narrow tab barely clear of the housing; opening grows it to
  /// the full shape. Growing rather than appearing is what makes the gesture
  /// read as one movement.
  private var size: CGSize {
    let windowWidth = HUDNotchGeometry.windowFrame(for: screen).width
    let width = min(metrics.contentWidth, windowWidth)
    switch drop.mode {
    case .none:
      return CGSize(width: metrics.contentWidth, height: housingHeight)
    case .armed where !drop.isOpen:
      return CGSize(
        width: min(HUDNotchGeometry.closedSize(for: screen).width + 96 * metrics.scale, windowWidth),
        height: housingHeight + 16 * metrics.scale
      )
    case .armed:
      return CGSize(width: width, height: housingHeight + 78 * metrics.scale)
    case .held:
      return CGSize(width: width, height: housingHeight + 96 * metrics.scale)
    case .transcript:
      return CGSize(width: width, height: housingHeight + 84 * metrics.scale)
    case .notice:
      return CGSize(width: width, height: housingHeight + 44 * metrics.scale)
    }
  }

  var body: some View {
    HUDSurface(
      screen: screen,
      metrics: metrics,
      // Carried but unused: `growsFromHousing` replaces it entirely. Drop
      // Transcription is always the notch opening and closing, which is the
      // gesture the whole feature is built on; the user's pick applies to
      // dictation, where the shape is a status surface rather than a target.
      revealStyle: settings.revealStyle,
      isRevealed: drop.isRevealed,
      size: size,
      growsFromHousing: true,
      clipsContent: true
    ) {
      VStack(spacing: 0) {
        stateView
          .frame(height: bodyHeight)
        // The housing cap, level with the bottom edge: kept empty so the
        // state content never collides with it.
        Color.clear.frame(height: housingHeight)
      }
    }
    // On the surface, not inside it. `HUDSurface` applies `size` as a frame
    // around this content, so an animation attached within the content never
    // reaches the frame: the shape jumps to its new size while only the words
    // inside it move, which is the frame-switch this removes.
    .animation(openingAnimation, value: size)
  }

  /// NotchDrop's spring, on every size the shape takes — peek, open, holding a
  /// file, holding a card. `extraBounce` is where the overshoot comes from:
  /// the shape passes its new size and settles back into it, which is what
  /// makes the notch feel like it snapped open rather than resized. Using it
  /// only for the reveal, as this did at first, hides the effect exactly where
  /// it is most visible.
  private var openingAnimation: Animation? {
    guard !reduceMotion else { return nil }
    return .interactiveSpring(duration: 0.5, extraBounce: 0.25, blendDuration: 0.125)
  }

  @ViewBuilder
  private var stateView: some View {
    switch drop.mode {
    case .none:
      EmptyView()
    case .armed:
      if drop.isOpen {
        // Crossfade only. The shape's growth carries the movement; the hint
        // and the target simply trade places inside it.
        DropTargetView(
          style: style,
          fileName: drop.fileName,
          languageTags: drop.languageTags,
          acceptsDrops: acceptsDrops,
          onDrop: onDrop
        )
        .transition(.opacity)
      } else {
        DropPeekView(style: style)
          .transition(.opacity)
      }
    case .held:
      DropHeldFileView(style: style, fileName: drop.fileName, icon: drop.heldIcon)
        // NotchDrop's item transition: it grows into place rather than
        // appearing, so the file reads as having been put there.
        .transition(.opacity.combined(with: .scale))
    case .transcript:
      if let transcript = drop.transcript {
        TranscriptCardView(
          style: style,
          transcript: transcript,
          isHovered: drop.isCardHovered,
          remaining: drop.remainingFraction,
          isInteractive: acceptsDrops,
          onEvent: onCardEvent
        )
      }
    case .notice:
      DropNoticeView(style: style, symbol: drop.noticeSymbol, text: drop.noticeText)
    }
  }
}
