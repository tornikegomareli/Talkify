import SwiftUI
import UniformTypeIdentifiers

/// The shape while a media file is being dragged at it: a hint at distance,
/// a receptive well once the pointer is close enough to drop.
struct DropTargetView: View {
  let style: DropHUDStyle
  let fileName: String
  /// Present only when a second dictation language is configured, in which
  /// case the target splits and the drop chooses the language.
  let languageTags: [String]
  var acceptsDrops = true
  var onDrop: (Int) -> Void = { _ in }

  var body: some View {
    Group {
      if languageTags.count > 1 {
        splitTarget
      } else {
        singleTarget
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 18 * style.scale)
    .padding(.bottom, 14 * style.scale)
  }

  private var singleTarget: some View {
    HStack(spacing: 12 * style.scale) {
      DropMediaGlyph(style: style)
      VStack(alignment: .leading, spacing: 2 * style.scale) {
        Text("Drop to transcribe")
          .font(.system(size: 13 * style.scale, weight: .semibold))
          .foregroundStyle(.white)
        Text(fileName)
          .font(.system(size: 11 * style.scale))
          .foregroundStyle(.white.opacity(0.55))
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14 * style.scale)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(receptiveWell)
    .modifier(DropAccepting(isEnabled: acceptsDrops) { onDrop(0) })
  }

  /// With two languages configured the drop itself picks one, so the choice
  /// costs no decision before the gesture. Talkify never guesses a spoken
  /// language, and on a long file a wrong guess wastes minutes.
  private var splitTarget: some View {
    HStack(spacing: 10 * style.scale) {
      ForEach(Array(languageTags.enumerated()), id: \.offset) { index, tag in
        VStack(spacing: 4 * style.scale) {
          Text(tag)
            .font(.system(size: 15 * style.scale, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
          Text("Drop here")
            .font(.system(size: 10 * style.scale))
            .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(receptiveWell)
        .modifier(DropAccepting(isEnabled: acceptsDrops) { onDrop(index) })
      }
    }
  }

  /// The receptive edge: a dashed accent stroke over a barely-lifted well.
  private var receptiveWell: some View {
    let shape = RoundedRectangle(cornerRadius: style.innerRadius, style: .continuous)
    return shape
      .fill(.white.opacity(0.05))
      .overlay {
        shape.strokeBorder(
          style.accentStroke,
          style: StrokeStyle(
            lineWidth: 1.5 * style.scale,
            dash: [6 * style.scale, 5 * style.scale]
          )
        )
        .opacity(0.85)
      }
  }
}

/// The hint at distance. No file name and no instruction: at this range the
/// shape is saying "I am here", and anything more is unreadable in passing.
struct DropPeekView: View {
  let style: DropHUDStyle

  var body: some View {
    Capsule(style: .continuous)
      .fill(style.accent.opacity(0.9))
      .frame(width: 34 * style.scale, height: 3 * style.scale)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct DropMediaGlyph: View {
  let style: DropHUDStyle

  var body: some View {
    Image(systemName: "waveform")
      .font(.system(size: 20 * style.scale, weight: .medium))
      .foregroundStyle(style.accent)
      .frame(width: 30 * style.scale)
  }
}

/// Accepting a dropped file. Split out so the surface can be rendered without
/// it: `ImageRenderer` draws an interactive drop destination as a placeholder
/// rather than as the view underneath.
///
/// The handler does nothing and says yes. That is the whole design: the system
/// keeps the dragged item on the pointer until the destination answers, so
/// every instruction executed before returning is time the item spends stuck
/// to the cursor. It does not read the item, it does not touch the file, and
/// it does not start the job — Talkify already knows what is being dragged,
/// because `DragWatcher` read the drag pasteboard when it opened this target.
/// Everything real happens on the next turn of the run loop, by which point
/// the item has left the pointer.
private struct DropAccepting: ViewModifier {
  let isEnabled: Bool
  let onDrop: () -> Void

  func body(content: Content) -> some View {
    if isEnabled {
      // `[.data]` rather than `[.fileURL]`, after NotchDrop. SwiftUI only
      // offers the drop to a destination whose declared types the providers
      // conform to, and a destination that is not offered the drop refuses it
      // — which macOS answers by flying the item back. `public.data` is the
      // broadest thing a file drag can be, so the offer always arrives; what
      // was actually dragged was decided long before this, on the way in.
      content.onDrop(of: [.data], isTargeted: nil) { _ in
        Task { @MainActor in onDrop() }
        return true
      }
    } else {
      content
    }
  }
}
