import SwiftUI

/// An open, smoothed line through the samples, shifted left by
/// `scrollProgress` of one slot so consecutive buffers connect seamlessly.
struct SmoothLineShape: Shape {
  let samples: [Float]
  let scrollProgress: Double

  nonisolated func path(in rect: CGRect) -> Path {
    guard samples.count > 2 else { return Path() }
    let step = rect.width / CGFloat(samples.count - 2)
    let offset = CGFloat(scrollProgress) * step

    let points = samples.enumerated().map { index, sample in
      CGPoint(
        x: rect.minX + CGFloat(index) * step - offset,
        y: rect.midY - max(0.75, CGFloat(sample) * rect.height / 2)
      )
    }

    var path = Path()
    path.move(to: points[0])
    for i in 1..<points.count {
      let previous = points[i - 1]
      let current = points[i]
      let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
      path.addQuadCurve(to: mid, control: previous)
    }
    path.addLine(to: points[points.count - 1])
    return path
  }
}

/// One vertical bar per sample, centered on the midline. `rounded` and
/// `perceptual` (square-root heights) split the Article and Silver looks.
struct AudioWaveShape: Shape {
  let samples: [Float]
  let spacing: CGFloat
  var rounded = true
  var perceptual = true

  nonisolated func path(in rect: CGRect) -> Path {
    guard !samples.isEmpty else { return Path() }
    let count = CGFloat(samples.count)
    let barWidth = max(1, (rect.width - spacing * (count - 1)) / count)

    var path = Path()
    var x = rect.minX
    for sample in samples {
      let scaled = perceptual ? CGFloat(sample).squareRoot() : CGFloat(sample)
      let height = max(2, scaled * rect.height)
      let bar = CGRect(x: x, y: rect.midY - height / 2, width: barWidth, height: height)
      if rounded {
        path.addRoundedRect(
          in: bar,
          cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2)
        )
      } else {
        path.addRect(bar)
      }
      x += barWidth + spacing
    }
    return path
  }
}

/// WaveformScrubber's DotDrawer: a mirrored pair of dots per sample.
struct DotWaveShape: Shape {
  let samples: [Float]
  let dotRadius: CGFloat

  nonisolated func path(in rect: CGRect) -> Path {
    guard !samples.isEmpty else { return Path() }
    let spacing = rect.width / CGFloat(samples.count)
    var path = Path()
    for (index, sample) in samples.enumerated() {
      let x = rect.minX + CGFloat(index) * spacing
      let halfHeight = CGFloat(sample) * rect.height / 2
      for y in [rect.midY - halfHeight, rect.midY + halfHeight] {
        path.addEllipse(in: CGRect(
          x: x - dotRadius,
          y: y - dotRadius,
          width: dotRadius * 2,
          height: dotRadius * 2
        ))
      }
    }
    return path
  }
}

/// WaveformScrubber's BezierCurveDrawer, simplified: a smooth symmetric
/// filled shape through midpoint quadratic curves.
struct CurveWaveShape: Shape {
  let samples: [Float]

  nonisolated func path(in rect: CGRect) -> Path {
    guard samples.count > 1 else { return Path() }
    let stepX = rect.width / CGFloat(samples.count - 1)
    let top = samples.enumerated().map { index, sample in
      CGPoint(
        x: rect.minX + CGFloat(index) * stepX,
        y: rect.midY - max(1, CGFloat(sample) * rect.height / 2)
      )
    }

    var path = Path()
    path.move(to: top[0])
    addSmoothLine(through: top, to: &path)
    let bottom = top.reversed().map { CGPoint(x: $0.x, y: 2 * rect.midY - $0.y) }
    path.addLine(to: bottom[0])
    addSmoothLine(through: bottom, to: &path)
    path.closeSubpath()
    return path
  }

  private nonisolated func addSmoothLine(through points: [CGPoint], to path: inout Path) {
    for i in 1..<points.count {
      let previous = points[i - 1]
      let current = points[i]
      let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
      path.addQuadCurve(to: mid, control: previous)
    }
    path.addLine(to: points[points.count - 1])
  }
}

/// AudioKit Waveform's look: a continuous symmetric min/max region.
struct FilledWaveShape: Shape {
  let samples: [Float]

  nonisolated func path(in rect: CGRect) -> Path {
    guard samples.count > 1 else { return Path() }
    let stepX = rect.width / CGFloat(samples.count - 1)

    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.midY))
    for (index, sample) in samples.enumerated() {
      path.addLine(to: CGPoint(
        x: rect.minX + CGFloat(index) * stepX,
        y: rect.midY - max(0.75, CGFloat(sample) * rect.height / 2)
      ))
    }
    for (index, sample) in samples.enumerated().reversed() {
      path.addLine(to: CGPoint(
        x: rect.minX + CGFloat(index) * stepX,
        y: rect.midY + max(0.75, CGFloat(sample) * rect.height / 2)
      ))
    }
    path.closeSubpath()
    return path
  }
}
