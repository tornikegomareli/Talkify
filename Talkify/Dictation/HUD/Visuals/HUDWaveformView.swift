import Charts
import SwiftUI

/// The live waveform strip: levels reduced on the audio side (vDSP in
/// MicrophoneInput) drive whichever style is selected. Newest level on the
/// right. Replaces the draft text while listening.
struct HUDWaveformView: View {
  static let barCount = 56

  let settings: DictationSessionSettings
  let content: DictationHUDContent

  @State private var start = Date()

  /// Chart Line and Siri Wave carry their own treatment (layered glow and
  /// gradient; the source's three-color blend) — the sheen shader and the
  /// bar styles' side margins would only muddy them.
  private var carriesOwnTreatment: Bool {
    settings.waveformStyle == .chartLine || settings.waveformStyle == .siriWave
  }

  var body: some View {
    Group {
      if carriesOwnTreatment {
        styledWave
      } else {
        TimelineView(.animation) { context in
          styledWave
            // WWDC26-style finish over the drawn pixels:
            // chromatic edge fringing, a metallic specular sweep,
            // and soft bloom (WaveformSheen.metal).
            .layerEffect(
              ShaderLibrary.waveformSheen(
                .float2(waveSize),
                .float(Float(context.date.timeIntervalSince(start))),
                .float(Float(content.audioLevel))
              ),
              maxSampleOffset: CGSize(width: 8, height: 8)
            )
        }
      }
    }
    .onGeometryChange(for: CGSize.self, of: \.size) { waveSize = $0 }
    .animation(.linear(duration: 0.05), value: content.levelHistory)
    // Full-width styles run edge to edge; the bar styles keep margins.
    .padding(.horizontal, carriesOwnTreatment ? 0 : 28)
    .padding(.vertical, 6)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  @State private var waveSize = CGSize(width: 1, height: 1)

  @ViewBuilder
  private var styledWave: some View {
    Group {
      switch settings.waveformStyle {
      case .article:
        AudioWaveShape(samples: content.levelHistory, spacing: 2, rounded: false, perceptual: false)
          .fill(silver)
      case .silver:
        AudioWaveShape(samples: content.levelHistory, spacing: 3, rounded: true, perceptual: true)
          .fill(silver)
      case .capsules:
        capsules
      case .chartLine:
        ChartLineWaveView(content: content)
      case .chartArea:
        areaChart
      case .dots:
        DotWaveShape(samples: content.levelHistory, dotRadius: 1.6)
          .fill(silver)
      case .curve:
        CurveWaveShape(samples: content.levelHistory)
          .fill(silver)
      case .filled:
        FilledWaveShape(samples: content.levelHistory)
          .fill(silver)
      case .siriWave:
        HUDSiriWaveView(content: content)
      }
    }
  }

  /// One color language for every style: the edge glow's white/silver —
  /// a hot white body cooling at the extremes, faint blue-violet fringe.
  /// Amber when the microphone dies (CONTEXT.md).
  private var silver: AnyShapeStyle {
    content.isAudioAlive
      ? AnyShapeStyle(LinearGradient(
        colors: [
          Color(red: 0.62, green: 0.72, blue: 1.0).opacity(0.75),
          .white,
          Color(red: 0.62, green: 0.72, blue: 1.0).opacity(0.75),
        ],
        startPoint: .top,
        endPoint: .bottom
      ))
      : AnyShapeStyle(Color.orange.opacity(0.55))
  }

  /// AudioWaveform's capsule mode: dampened heights, width-derived bars.
  private var capsules: some View {
    GeometryReader { proxy in
      let values = content.levelHistory
      let step = proxy.size.width / CGFloat(values.count)
      let barWidth = max(step * 0.55, 1)
      HStack(alignment: .center, spacing: step - barWidth) {
        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
          Capsule()
            .fill(silver)
            .frame(
              width: barWidth,
              height: max(barWidth, CGFloat(value) * 0.75 * proxy.size.height)
            )
            .frame(maxHeight: .infinity, alignment: .center)
        }
      }
    }
  }

  /// AudioWaveform's area mode, straight from Swift Charts.
  private var areaChart: some View {
    Chart(Array(content.levelHistory.enumerated()), id: \.offset) { index, value in
      AreaMark(x: .value("t", index), y: .value("level", value))
        .interpolationMethod(.catmullRom)
        .foregroundStyle(silver)
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartYScale(domain: 0...1)
  }
}

#Preview("Article") {
  HUDShellPreviewHarness(visual: .waveform, waveformStyle: .article)
}

#Preview("Silver") {
  HUDShellPreviewHarness(visual: .waveform, waveformStyle: .silver)
}

#Preview("Chart Area") {
  HUDShellPreviewHarness(visual: .waveform, waveformStyle: .chartArea)
}

#Preview("Dots") {
  HUDShellPreviewHarness(visual: .waveform, waveformStyle: .dots)
}

#Preview("Curve") {
  HUDShellPreviewHarness(visual: .waveform, waveformStyle: .curve)
}

#Preview("Filled") {
  HUDShellPreviewHarness(visual: .waveform, waveformStyle: .filled)
}
