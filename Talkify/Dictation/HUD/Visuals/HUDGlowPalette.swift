import AppKit
import SwiftUI

/// The Edge Glow color palettes, a permanent Settings pick: each palette
/// colors the beam's strokes and the particle cloud together so the whole
/// visual speaks one language.
enum HUDGlowPalette: String, CaseIterable {
  case spectrum = "Spectrum"
  /// The NotchIsland prototype's Intelligence colors, exactly: violet, rose,
  /// coral, amber and periwinkle.
  case intelligence = "Intelligence"
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

  /// The Intelligence palette's five colors, in the order the prototype's
  /// rim walked them.
  private static let intelligenceHues: [Color] = [
    Color(red: 0.74, green: 0.51, blue: 0.95),
    Color(red: 0.96, green: 0.56, blue: 0.82),
    Color(red: 1.0, green: 0.55, blue: 0.42),
    Color(red: 1.0, green: 0.78, blue: 0.45),
    Color(red: 0.48, green: 0.62, blue: 1.0),
  ]

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
    case .intelligence:
      Self.intelligenceHues.enumerated().map { index, color in
        .init(color: color, location: Double(index) / Double(Self.intelligenceHues.count))
      } + [.init(color: Self.intelligenceHues[0], location: 1.0)]
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
    case .intelligence: NSColor(red: 0.74, green: 0.51, blue: 0.95, alpha: 1)
    case .silver: NSColor(red: 0.75, green: 0.8, blue: 1.0, alpha: 1)
    case .aurora: NSColor(red: 0.2, green: 0.85, blue: 0.6, alpha: 1)
    case .sunset: NSColor(red: 1.0, green: 0.45, blue: 0.3, alpha: 1)
    case .ocean: NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1)
    case .mono: .white
    }
  }

  /// Three stops for the shaping label's sheen, in the order the ramp walks
  /// them. Taken from the same palette as the beam so the label speaks the
  /// palette's language, and kept to three because the shader mixes exactly
  /// three and wraps.
  var sheenColors: (Color, Color, Color) {
    switch self {
    case .spectrum: (.blue, .purple, .pink)
    case .intelligence: (Self.intelligenceHues[0], Self.intelligenceHues[1], Self.intelligenceHues[3])
    case .silver: (.white, Color(red: 0.62, green: 0.72, blue: 1.0), .white)
    case .aurora: (.mint, .teal, .cyan)
    case .sunset: (.orange, .pink, .purple)
    case .ocean: (.cyan, .blue, .indigo)
    // Mono means one color, so the ramp has nothing to walk and the label is
    // left to the specular sweep alone.
    case .mono: (.white, .white, .white)
    }
  }

  /// Five colors for Flying Ghost: they turn around its rim and move through
  /// the ghost's mesh (which takes the first four), so both read as the
  /// beam's palette. Mono has one color,
  /// so its orb is a lit pearl and its rim a plain light.
  var ghostColors: [Color] {
    // Each set spans the same range as the Intelligence palette: two light
    // tones, two mid, one deep. Without that spread the mesh has nothing to
    // move between (Mono was four whites, so its ghost read as flat), and the
    // halo, which takes the second color, would be brighter in one palette
    // than another.
    switch self {
    case .spectrum:
      [
        Color(red: 0.42, green: 0.52, blue: 1.0),
        Color(red: 0.76, green: 0.5, blue: 1.0),
        Color(red: 1.0, green: 0.5, blue: 0.74),
        Color(red: 0.55, green: 0.92, blue: 0.85),
        Color(red: 0.36, green: 0.36, blue: 0.95),
      ]
    case .intelligence: Self.intelligenceHues
    case .silver:
      [
        Color(red: 0.9, green: 0.92, blue: 1.0),
        Color(red: 0.66, green: 0.74, blue: 1.0),
        Color(red: 0.8, green: 0.83, blue: 0.95),
        Color(red: 0.97, green: 0.97, blue: 1.0),
        Color(red: 0.5, green: 0.58, blue: 0.85),
      ]
    case .aurora:
      [
        Color(red: 0.45, green: 1.0, blue: 0.8),
        Color(red: 0.3, green: 0.82, blue: 0.85),
        Color(red: 0.5, green: 0.92, blue: 0.5),
        Color(red: 0.75, green: 1.0, blue: 0.9),
        Color(red: 0.15, green: 0.6, blue: 0.7),
      ]
    case .sunset:
      [
        Color(red: 1.0, green: 0.62, blue: 0.3),
        Color(red: 1.0, green: 0.45, blue: 0.55),
        Color(red: 0.78, green: 0.45, blue: 0.95),
        Color(red: 1.0, green: 0.82, blue: 0.5),
        Color(red: 0.85, green: 0.28, blue: 0.35),
      ]
    case .ocean:
      [
        Color(red: 0.35, green: 0.6, blue: 1.0),
        Color(red: 0.35, green: 0.85, blue: 1.0),
        Color(red: 0.5, green: 0.45, blue: 0.98),
        Color(red: 0.65, green: 0.9, blue: 1.0),
        Color(red: 0.12, green: 0.28, blue: 0.7),
      ]
    case .mono:
      [
        Color(white: 0.98),
        Color(white: 0.78),
        Color(white: 0.88),
        Color(white: 1.0),
        Color(white: 0.55),
      ]
    }
  }

  /// How much to scale Flying Ghost's glow so it reads the same in every
  /// palette: light colors glow brighter than deep ones at the same strength,
  /// so Silver and Mono flared where Spectrum and Ocean stayed soft. The
  /// Intelligence palette is the reference at 1. The ratio is raised to 1.5
  /// because near-white reads brighter than its measured lightness: a plain
  /// ratio left Silver and Mono still flaring.
  var ghostGlowBalance: Double {
    let ratio = Self.averageLightness(of: Self.intelligenceHues) / Self.averageLightness(of: ghostColors)
    return min(max(pow(ratio, 1.5), Self.ghostGlowBalanceRange.lowerBound), Self.ghostGlowBalanceRange.upperBound)
  }

  static let ghostGlowBalanceRange = 0.45...1.25

  /// Mean relative luminance, the eye's weighting of red, green and blue.
  static func averageLightness(of colors: [Color]) -> Double {
    let total = colors.reduce(0.0) { sum, color in
      let resolved = color.resolve(in: EnvironmentValues())
      return sum + 0.2126 * Double(resolved.red) + 0.7152 * Double(resolved.green)
        + 0.0722 * Double(resolved.blue)
    }
    return total / Double(max(colors.count, 1))
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
    case .intelligence:
      [
        SIMD4(0.74, 0.51, 0.95, 1.0),
        SIMD4(0.96, 0.56, 0.82, 1.0),
        SIMD4(1.0, 0.78, 0.45, 1.0),
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
