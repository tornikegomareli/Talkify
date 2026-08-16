import SwiftUI
import UniformTypeIdentifiers

/// The two Drop Transcription faces of the HUD: the target a media file is
/// dragged into, and the card the finished transcript is dragged out of.
///
/// Both render inside `HUDSurface`, so they inherit the shape, the fillets and
/// the reveal that the dictation shell uses. Neither shows a voice visual —
/// nothing is listening.
struct DropHUDView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let screen: HUDScreenSnapshot
  let settings: DictationSessionSettings
  let drop: HUDDropContent
  /// Returns true when the drop was taken. Index is which half received it,
  /// which is the language choice when the target is split.
  var onDrop: (URL, Int) -> Bool = { _, _ in false }
  var onHoverCard: (Bool) -> Void = { _ in }
  /// Drop handling is an interactive layer `ImageRenderer` cannot draw, so the
  /// render harness turns it off to photograph the surface itself.
  var acceptsDrops = true

  private var metrics: HUDMetrics { settings.hudMetrics }

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
    switch drop.mode {
    case .none:
      return CGSize(width: metrics.contentWidth, height: housingHeight)
    case .armed where !drop.isOpen:
      return CGSize(
        width: min(HUDNotchGeometry.closedSize(for: screen).width + 96 * metrics.scale, windowWidth),
        height: housingHeight + 16 * metrics.scale
      )
    case .armed:
      return CGSize(
        width: min(metrics.contentWidth, windowWidth),
        height: housingHeight + 78 * metrics.scale
      )
    case .transcript:
      return CGSize(
        width: min(metrics.contentWidth, windowWidth),
        height: housingHeight + 84 * metrics.scale
      )
    }
  }

  var body: some View {
    HUDSurface(
      screen: screen,
      metrics: metrics,
      revealStyle: settings.revealStyle,
      isRevealed: drop.isRevealed,
      size: size
    ) {
      VStack(spacing: 0) {
        // Level with the housing, always empty: the camera lives here.
        Color.clear.frame(height: housingHeight)
        body(for: drop.mode)
          .frame(height: bodyHeight)
      }
      .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0), value: drop.isOpen)
      .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0), value: drop.mode)
    }
  }

  @ViewBuilder
  private func body(for mode: HUDDropContent.Mode) -> some View {
    switch mode {
    case .none:
      EmptyView()
    case .armed:
      if drop.isOpen {
        openTarget
      } else {
        peekHint
      }
    case .transcript:
      transcriptCard
    }
  }

  /// The hint. No file name and no instruction: at this distance the shape is
  /// saying "I am here", and anything more is unreadable in passing.
  private var peekHint: some View {
    Capsule(style: .continuous)
      .fill(SettingsTheme.accent.opacity(0.9))
      .frame(width: 34 * metrics.scale, height: 3 * metrics.scale)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var openTarget: some View {
    Group {
      if drop.languageTags.count > 1 {
        splitTarget
      } else {
        singleTarget
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 18 * metrics.scale)
    .padding(.bottom, 14 * metrics.scale)
  }

  private var singleTarget: some View {
    HStack(spacing: 12 * metrics.scale) {
      mediaGlyph
      VStack(alignment: .leading, spacing: 2 * metrics.scale) {
        Text("Drop to transcribe")
          .font(.system(size: 13 * metrics.scale, weight: .semibold))
          .foregroundStyle(.white)
        Text(drop.fileName)
          .font(.system(size: 11 * metrics.scale))
          .foregroundStyle(.white.opacity(0.55))
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14 * metrics.scale)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(receptiveWell)
    .modifier(DropAccepting(isEnabled: acceptsDrops) { onDrop($0, 0) })
  }

  /// With two languages configured the drop itself picks one, so the choice
  /// costs no decision before the gesture. Talkify never guesses a spoken
  /// language, and on a long file a wrong guess wastes minutes.
  private var splitTarget: some View {
    HStack(spacing: 10 * metrics.scale) {
      ForEach(Array(drop.languageTags.enumerated()), id: \.offset) { index, tag in
        VStack(spacing: 4 * metrics.scale) {
          Text(tag)
            .font(.system(size: 15 * metrics.scale, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
          Text("Drop here")
            .font(.system(size: 10 * metrics.scale))
            .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(receptiveWell)
        .modifier(DropAccepting(isEnabled: acceptsDrops) { onDrop($0, index) })
      }
    }
  }

  /// The receptive edge: an accent stroke over a barely-lifted well. Not the
  /// Edge Glow beam, which means a microphone is listening.
  private var receptiveWell: some View {
    let shape = RoundedRectangle(cornerRadius: 12 * metrics.scale, style: .continuous)
    return shape
      .fill(.white.opacity(0.05))
      .overlay {
        shape.strokeBorder(
          SettingsTheme.accent.opacity(0.85),
          style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
        )
      }
  }

  private var mediaGlyph: some View {
    Image(systemName: "waveform")
      .font(.system(size: 20 * metrics.scale, weight: .medium))
      .foregroundStyle(SettingsTheme.accent)
      .frame(width: 30 * metrics.scale)
  }

  @ViewBuilder
  private var transcriptCard: some View {
    if let transcript = drop.transcript {
      VStack(spacing: 0) {
        HStack(spacing: 12 * metrics.scale) {
          Image(systemName: "doc.text")
            .font(.system(size: 20 * metrics.scale, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 30 * metrics.scale)
          VStack(alignment: .leading, spacing: 2 * metrics.scale) {
            Text(transcript.name)
              .font(.system(size: 13 * metrics.scale, weight: .semibold))
              .foregroundStyle(.white)
              .lineLimit(1)
              .truncationMode(.middle)
            Text("\(transcript.wordCountText) · \(transcript.durationText)")
              .font(.system(size: 11 * metrics.scale, weight: .medium))
              .monospacedDigit()
              .foregroundStyle(.white.opacity(0.55))
          }
          Spacer(minLength: 0)
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11 * metrics.scale, weight: .semibold))
            .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 14 * metrics.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
          RoundedRectangle(cornerRadius: 12 * metrics.scale, style: .continuous)
            .fill(.white.opacity(0.07))
        }
        .modifier(
          CardDragging(isEnabled: acceptsDrops, url: transcript.url, onHover: onHoverCard) {
            dragPreview(transcript)
          }
        )

        dismissalHairline
      }
      .padding(.horizontal, 18 * metrics.scale)
      .padding(.bottom, 12 * metrics.scale)
    }
  }

  /// The drag image is the card itself rather than a generic file icon, so the
  /// thing that leaves the island is the thing that was in it.
  private func dragPreview(_ transcript: HUDDropContent.Transcript) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "doc.text")
      Text(transcript.name).lineLimit(1)
    }
    .font(.system(size: 12, weight: .semibold))
    .foregroundStyle(.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.black.opacity(0.85), in: Capsule())
  }

  /// Shows the five seconds draining away, and stops when the pointer arrives.
  /// A surface that asks for an action has to make its deadline visible.
  private var dismissalHairline: some View {
    GeometryReader { proxy in
      Capsule()
        .fill(.white.opacity(0.28))
        .frame(width: proxy.size.width * drop.remainingFraction)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: 2 * metrics.scale)
    .padding(.top, 8 * metrics.scale)
    .opacity(drop.remainingFraction > 0 ? 1 : 0)
  }
}

/// Accepting a dropped file. Split out so the surface can be rendered without
/// it: `ImageRenderer` draws an interactive drop destination as a placeholder
/// rather than as the view underneath.
private struct DropAccepting: ViewModifier {
  let isEnabled: Bool
  let onDrop: (URL) -> Bool

  func body(content: Content) -> some View {
    if isEnabled {
      content.dropDestination(for: URL.self) { urls, _ in
        guard let url = urls.first else { return false }
        return onDrop(url)
      }
    } else {
      content
    }
  }
}

/// Dragging the finished transcript out, with the open-hand cursor that is the
/// whole grab affordance. Split out for the same rendering reason.
private struct CardDragging<Preview: View>: ViewModifier {
  let isEnabled: Bool
  let url: URL
  let onHover: (Bool) -> Void
  @ViewBuilder let preview: Preview

  func body(content: Content) -> some View {
    if isEnabled {
      // A real file already on disk, so this is an ordinary file drag: a
      // same-volume Finder drop moves it, anywhere else copies it.
      content
        .draggable(url) { preview }
        .onHover { isInside in
          onHover(isInside)
          if isInside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
    } else {
      content
    }
  }
}
