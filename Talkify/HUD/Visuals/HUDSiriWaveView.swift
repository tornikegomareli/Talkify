import SwiftUI

/// The classic Siri 9-style wave, ported from alfianlosari/SiriWaveView
/// (MIT License, © 2019 Noah Chalifour): a support line and three overlapping
/// colored waves; every power change animates each wave toward a fresh random
/// four-curve composition over 0.3s, which is what makes the motion roll.
///
/// Talkify adaptations: the microphone level drives the power, value-based
/// animation replaces the source's deprecated implicit `.animation`, and a
/// dead microphone flattens it to a static amber line (CONTEXT.md).
struct HUDSiriWaveView: View {
  /// The source's three wave colors.
  private static let colors: [Color] = [
    Color(red: 173 / 255, green: 57 / 255, blue: 76 / 255),
    Color(red: 48 / 255, green: 220 / 255, blue: 155 / 255),
    Color(red: 25 / 255, green: 122 / 255, blue: 255 / 255),
  ]
  private static let amber = Color.orange.opacity(0.55)

  let content: DictationHUDContent

  var body: some View {
    let alive = content.isAudioAlive
    ZStack {
      supportLine(alive: alive)
      ForEach(0..<Self.colors.count, id: \.self) { index in
        SiriSingleWave(
          power: alive ? content.audioLevel : 0,
          color: alive ? Self.colors[index] : Self.amber
        )
      }
    }
    .blendMode(.lighten)
    .drawingGroup()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func supportLine(alive: Bool) -> some View {
    GeometryReader { proxy in
      Path { path in
        let centerY = proxy.size.height / 2
        path.move(to: CGPoint(x: 0, y: centerY))
        path.addLine(to: CGPoint(x: proxy.size.width, y: centerY))
      }
      .stroke(alive ? Color.white : Self.amber, lineWidth: 2)
      .opacity(0.5)
    }
  }
}

/// One colored wave: holds the current composition and animates to a new
/// random one whenever the power changes (the source regenerated per body
/// evaluation under an implicit animation; this is the value-based twin).
private struct SiriSingleWave: View {
  let power: Double
  let color: Color

  @State private var wave = SiriWave.random(power: 0)

  var body: some View {
    SiriWaveShape(wave: wave)
      .fill(color)
      .onChange(of: power) { _, newPower in
        withAnimation(.linear(duration: 0.3)) {
          wave = .random(power: newPower)
        }
      }
  }
}

/// One sine component of a wave.
struct SiriWaveCurve: Equatable {
  var power: Double
  var A: Double
  var k: Double
  var t: Double

  static func random(power: Double) -> SiriWaveCurve {
    SiriWaveCurve(
      power: power,
      A: .random(in: 0.1...1.0),
      k: .random(in: 0.6...0.9),
      t: .random(in: -1.0...4.0)
    )
  }
}

/// A composition of four curves, of which `useCurves` render.
struct SiriWave: Equatable {
  var power: Double
  var curves: [SiriWaveCurve]
  var useCurves: Int

  static func random(power: Double) -> SiriWave {
    SiriWave(
      power: power,
      curves: (0..<4).map { _ in .random(power: power) },
      useCurves: Int.random(in: 2...4)
    )
  }
}

// The source's workaround, kept as-is: arrays cannot be animatable data, so
// the four curves' parameters flatten into nested AnimatablePairs.
extension SiriWave: Animatable {
  typealias AnimatableData = AnimatablePair<
    AnimatablePair<
      AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>,
      AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>
    >,
    AnimatablePair<
      AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>,
      AnimatablePair<
        AnimatablePair<Double, Double>,
        AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>
      >
    >
  >

  var animatableData: AnimatableData {
    get {
      .init(
        .init(
          .init(.init(curves[0].A, curves[0].power), .init(curves[0].k, curves[0].t)),
          .init(.init(curves[1].A, curves[1].power), .init(curves[1].k, curves[1].t))
        ),
        .init(
          .init(.init(curves[2].A, curves[2].power), .init(curves[2].k, curves[2].t)),
          .init(
            .init(curves[3].A, curves[3].power),
            .init(.init(curves[3].k, curves[3].t), .init(power, .zero))
          )
        )
      )
    }
    set {
      curves[0].A = newValue.first.first.first.first
      curves[0].power = newValue.first.first.first.second
      curves[0].k = newValue.first.first.second.first
      curves[0].t = newValue.first.first.second.second

      curves[1].A = newValue.first.second.first.first
      curves[1].power = newValue.first.second.first.second
      curves[1].k = newValue.first.second.second.first
      curves[1].t = newValue.first.second.second.second

      curves[2].A = newValue.second.first.first.first
      curves[2].power = newValue.second.first.first.second
      curves[2].k = newValue.second.first.second.first
      curves[2].t = newValue.second.first.second.second

      curves[3].A = newValue.second.second.first.first
      curves[3].power = newValue.second.second.first.second
      curves[3].k = newValue.second.second.second.first.first
      curves[3].t = newValue.second.second.second.first.second

      power = newValue.second.second.second.second.first
    }
  }
}

/// The source's wave geometry: each active curve is an attenuated sine
/// (|A·sin(kx−t)| under a bell), the curves' upper envelope is taken per
/// column, then mirrored about the midline into the filled blob.
struct SiriWaveShape: Shape {
  var wave: SiriWave

  var animatableData: SiriWave.AnimatableData {
    get { wave.animatableData }
    set { wave.animatableData = newValue }
  }

  nonisolated func path(in rect: CGRect) -> Path {
    let columns = Array(stride(from: -rect.midX, to: rect.midX, by: 1.0))
    var upper = [CGPoint](
      repeating: CGPoint(x: 0, y: rect.midY),
      count: columns.count
    )

    for index in 0..<wave.useCurves {
      let curve = wave.curves[index]
      let A = curve.A * Double(rect.midY) * wave.power

      for (j, graphX) in columns.enumerated() {
        let scaledX = graphX / (rect.midX / 9.0)
        let x = rect.midX + graphX
        let y = attenuatedSine(
          x: Double(scaledX), A: A, k: curve.k, t: curve.t
        ) + Double(rect.midY)
        upper[j] = CGPoint(x: x, y: max(upper[j].y, y))
      }
    }

    let mirrored = upper.map { CGPoint(x: $0.x, y: 2 * rect.midY - $0.y) }

    var path = Path()
    path.move(to: CGPoint(x: 0, y: rect.midY))
    path.addLines(upper + mirrored)
    return path
  }

  private nonisolated func attenuatedSine(
    x: Double, A: Double, k: Double, t: Double
  ) -> Double {
    let sine = A * sin((k * x) - t)
    let K = 4.0
    let shiftedT = t - (Double.pi / 2)
    let bell = pow(K / (K + pow((k * x) - shiftedT, 2)), K)
    return abs(sine * bell)
  }
}

#Preview("Siri Wave") {
  HUDShellPreviewHarness(visual: .waveform, waveformStyle: .siriWave)
}

#Preview("Siri Wave · dead mic") {
  HUDShellPreviewHarness(visual: .waveform, waveformStyle: .siriWave, micAlive: false)
}
