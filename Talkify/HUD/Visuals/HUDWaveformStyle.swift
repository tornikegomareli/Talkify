/// The waveform looks the user can choose, each mimicking a reference
/// implementation, all fed by the same live level history:
/// - Article: "Writing a High-Performance Audio Wave in SwiftUI" — the
///   original bar architecture.
/// - Silver: our styling of the same bars.
/// - Capsules / Chart Line / Chart Area: jonathanjr3/AudioWaveform's chart
///   types (Chart Line carries its own conveyor renderer and treatment).
/// - Dots / Curve: lkora/WaveformScrubber's DotDrawer and BezierCurveDrawer.
/// - Filled: AudioKit/Waveform's min/max region.
/// - Siri Wave: alfianlosari/SiriWaveView's classic Siri 9 multi-wave (MIT,
///   © 2019 Noah Chalifour; carries its own colors and treatment).
///
/// rawValue is the UserDefaults value existing picks are stored under —
/// renaming a case silently resets that preference.
enum HUDWaveformStyle: String, CaseIterable {
  case article = "Article"
  case silver = "Silver"
  case capsules = "Capsules"
  case chartLine = "Chart Line"
  case chartArea = "Chart Area"
  case dots = "Dots"
  case curve = "Curve"
  case filled = "Filled"
  case siriWave = "Siri Wave"
}
