import SwiftUI

/// The finished transcript, offered back: a card to drag out or click to copy,
/// with the deadline that will file it away draining underneath.
struct TranscriptCardView: View {
  let style: DropHUDStyle
  let transcript: DropHUDContent.Transcript
  let isHovered: Bool
  /// 1 down to 0 as the offer expires; frozen while the pointer is on the card.
  let remaining: Double
  var isInteractive = true
  var onEvent: (HUDCardEvent) -> Void = { _ in }

  var body: some View {
    VStack(spacing: 0) {
      card
      dismissalHairline
    }
    .padding(.horizontal, 18 * style.scale)
    .padding(.bottom, 12 * style.scale)
  }

  private var card: some View {
    HStack(spacing: 12 * style.scale) {
      Image(systemName: DropHUDStyle.transcriptSymbol)
        .font(.system(size: 20 * style.scale, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .frame(width: 30 * style.scale)

      VStack(alignment: .leading, spacing: 2 * style.scale) {
        Text(transcript.name)
          .font(.system(size: 13 * style.scale, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .truncationMode(.middle)
        // The card offers two gestures and neither is visible. The hint
        // replaces the numbers only while the pointer is here, which is the
        // moment it can still be acted on.
        Text(isHovered
          ? "Click to copy · Drag to save"
          : "\(transcript.wordCountText) · \(transcript.durationText)")
          .font(.system(size: 11 * style.scale, weight: .medium))
          .monospacedDigit()
          .foregroundStyle(.white.opacity(isHovered ? 0.75 : 0.55))
      }

      Spacer(minLength: 0)

      Image(systemName: isHovered ? "hand.point.up.left.fill" : "arrow.up.forward")
        .font(.system(size: 11 * style.scale, weight: .semibold))
        .foregroundStyle(.white.opacity(isHovered ? 0.55 : 0.3))
    }
    .padding(.horizontal, 14 * style.scale)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      RoundedRectangle(cornerRadius: style.innerRadius, style: .continuous)
        .fill(.white.opacity(isHovered ? 0.11 : 0.07))
    }
    .overlay { dragLayer }
  }

  /// Split out so the surface can be rendered without it: `ImageRenderer`
  /// cannot draw an `NSViewRepresentable`, and the render harness photographs
  /// the card rather than driving it.
  @ViewBuilder
  private var dragLayer: some View {
    if isInteractive {
      TranscriptDragView(
        url: transcript.url,
        text: transcript.text,
        makeDragImage: { dragImage },
        onEvent: onEvent
      )
    }
  }

  private var dragImage: NSImage? {
    let renderer = ImageRenderer(content: dragPreview)
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    return renderer.nsImage
  }

  /// The drag image is the card itself rather than a generic file icon, so the
  /// thing that leaves the island is the thing that was in it.
  private var dragPreview: some View {
    HStack(spacing: 8) {
      Image(systemName: DropHUDStyle.transcriptSymbol)
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
        .frame(width: proxy.size.width * remaining)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: 2 * style.scale)
    .padding(.top, 8 * style.scale)
    .opacity(remaining > 0 ? 1 : 0)
  }
}

/// What the shape holds between the drop and the job starting: the file
/// itself, with its own icon, so the gesture ends with the thing you dragged
/// visibly inside the notch instead of gone.
struct DropHeldFileView: View {
  let style: DropHUDStyle
  let fileName: String
  let icon: NSImage?

  var body: some View {
    VStack(spacing: 6 * style.scale) {
      Group {
        if let icon {
          Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
        } else {
          Image(systemName: "waveform")
            .font(.system(size: 30 * style.scale, weight: .medium))
            .foregroundStyle(style.accent)
        }
      }
      .frame(width: 44 * style.scale, height: 44 * style.scale)

      Text(fileName)
        .font(.system(size: 11 * style.scale, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.8))
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 18 * style.scale)
    .padding(.bottom, 12 * style.scale)
  }
}

/// What became of the transcript. One line: the card is gone and the only
/// thing left to say is where the words went.
struct DropNoticeView: View {
  let style: DropHUDStyle
  let symbol: String
  let text: String

  var body: some View {
    HStack(spacing: 8 * style.scale) {
      Image(systemName: symbol)
        .font(.system(size: 13 * style.scale, weight: .semibold))
        .foregroundStyle(style.accent)
      Text(text)
        .font(.system(size: 13 * style.scale, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 18 * style.scale)
    .padding(.bottom, 10 * style.scale)
  }
}
