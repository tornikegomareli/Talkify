import AppKit
import SwiftUI

/// The Edge Glow color palettes, a permanent Settings pick: each palette
/// colors the beam's strokes and the particle cloud together so the whole
/// visual speaks one language.
enum HUDGlowPalette: String, CaseIterable {
  case spectrum = "Spectrum"
  case silver = "Silver"
  case aurora = "Aurora"
  case sunset = "Sunset"
  case ocean = "Ocean"
  case mono = "Mono"

  /// The beam's stroke fill.
  var stroke: AnyShapeStyle {
    AnyShapeStyle(
      .angularGradient(
        stops: stops,
        center: .center,
        startAngle: Angle(radians: .zero),
        endAngle: Angle(radians: .pi * 2)
      )
    )
  }

  private var stops: [Gradient.Stop] {
    switch self {
    case .spectrum:
      // The gist's palette.
      [
        .init(color: .blue, location: 0.0),
        .init(color: .purple, location: 0.2),
        .init(color: .red, location: 0.4),
        .init(color: .mint, location: 0.5),
        .init(color: .indigo, location: 0.7),
        .init(color: .pink, location: 0.9),
        .init(color: .blue, location: 1.0),
      ]
    case .silver:
      [
        .init(color: .white, location: 0.0),
        .init(color: Color(red: 0.62, green: 0.72, blue: 1.0), location: 0.3),
        .init(color: .white, location: 0.5),
        .init(color: Color(red: 0.75, green: 0.78, blue: 0.95), location: 0.75),
        .init(color: .white, location: 1.0),
      ]
    case .aurora:
      [
        .init(color: .mint, location: 0.0),
        .init(color: .teal, location: 0.3),
        .init(color: .green, location: 0.5),
        .init(color: .cyan, location: 0.75),
        .init(color: .mint, location: 1.0),
      ]
    case .sunset:
      [
        .init(color: .orange, location: 0.0),
        .init(color: .red, location: 0.35),
        .init(color: .pink, location: 0.6),
        .init(color: .purple, location: 0.85),
        .init(color: .orange, location: 1.0),
      ]
    case .ocean:
      [
        .init(color: .blue, location: 0.0),
        .init(color: .cyan, location: 0.35),
        .init(color: .indigo, location: 0.65),
        .init(color: Color(red: 0.0, green: 0.1, blue: 0.45), location: 0.85),
        .init(color: .blue, location: 1.0),
      ]
    case .mono:
      [
        .init(color: .white, location: 0.0),
        .init(color: .white, location: 1.0),
      ]
    }
  }

  /// One representative accent for AppKit chrome (the status ghost's
  /// session tint) — the hue a user would name when asked what color
  /// this palette is.
  var statusAccent: NSColor {
    switch self {
    case .spectrum: NSColor(red: 0.55, green: 0.5, blue: 1.0, alpha: 1)
    case .silver: NSColor(red: 0.75, green: 0.8, blue: 1.0, alpha: 1)
    case .aurora: NSColor(red: 0.2, green: 0.85, blue: 0.6, alpha: 1)
    case .sunset: NSColor(red: 1.0, green: 0.45, blue: 0.3, alpha: 1)
    case .ocean: NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
    case .mono: .white
    }
  }

  /// The particle cloud's colors, cycled across the motes.
  var particleColors: [SIMD4<Float>] {
    switch self {
    case .spectrum:
      [
        SIMD4(0.35, 0.45, 1.0, 1.0),
        SIMD4(0.75, 0.4, 1.0, 1.0),
        SIMD4(1.0, 0.5, 0.75, 1.0),
      ]
    case .silver:
      [
        SIMD4(0.62, 0.72, 1.0, 1.0),
        SIMD4(0.85, 0.90, 1.0, 1.0),
        SIMD4(1.0, 1.0, 1.0, 1.0),
      ]
    case .aurora:
      [
        SIMD4(0.4, 1.0, 0.8, 1.0),
        SIMD4(0.3, 0.85, 0.85, 1.0),
        SIMD4(0.9, 1.0, 0.95, 1.0),
      ]
    case .sunset:
      [
        SIMD4(1.0, 0.6, 0.25, 1.0),
        SIMD4(1.0, 0.45, 0.6, 1.0),
        SIMD4(1.0, 0.9, 0.8, 1.0),
      ]
    case .ocean:
      [
        SIMD4(0.25, 0.75, 1.0, 1.0),
        SIMD4(0.3, 0.45, 1.0, 1.0),
        SIMD4(0.85, 0.95, 1.0, 1.0),
      ]
    case .mono:
      [
        SIMD4(1.0, 1.0, 1.0, 1.0),
        SIMD4(0.9, 0.9, 0.9, 1.0),
        SIMD4(0.75, 0.75, 0.75, 1.0),
      ]
    }
  }
}
