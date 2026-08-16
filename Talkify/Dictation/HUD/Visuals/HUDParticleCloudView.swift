import MetalKit
import SwiftUI

/// The Edge Glow particle cloud: silver motes chasing the beam's sweeping
/// origin while listening, rendered by a Metal compute pipeline
/// (ParticleCloud.metal) into a transparent MTKView. The session ramp and the
/// sweep clock mirror the border glow's — same trigger, same duration, same
/// sessionEpoch reset — so the cloud blooms, drains, and travels with it. A
/// dead microphone zeroes the ramp instantly: only the static amber outline
/// may remain (CONTEXT.md: dead microphone ≠ silence).
struct HUDParticleCloudView: View {
  let content: DictationHUDContent
  let settings: DictationSessionSettings
  let cornerRadius: CGFloat
  let topFilletRadius: CGFloat

  /// Reset on every session start, in the same runloop turn as the glow
  /// view's, so both sweeps stay in phase.
  @State private var sweepStart = Date()

  /// Mirrors `content.showsVoiceVisual` for the ramp's keyframe trigger,
  /// exactly like HUDEdgeGlowView: a view mounted while listening is
  /// already true would never see its trigger change, stay at progress 0,
  /// and keep the MTKView paused.
  @State private var ramped = false

  var body: some View {
    GeometryReader { proxy in
      let listening = content.showsVoiceVisual
      TimelineView(.animation(paused: !listening)) { context in
        // Plain values for the @Sendable keyframeAnimator content
        // closure; the body re-evaluates every timeline frame, so
        // they stay fresh.
        let size = proxy.size
        let alive = content.isAudioAlive
        let palette = settings.glowPalette
        let target = HUDGlowSilhouetteShape.point(
          atArcFraction: HUDEdgeGlowView.sweepFraction(
            at: context.date.timeIntervalSince(sweepStart)
          ),
          cornerRadius: cornerRadius,
          topFilletRadius: topFilletRadius,
          inset: 0,
          in: size
        )
        let center = CGPoint(
          x: target.x / max(size.width, 1),
          y: target.y / max(size.height, 1)
        )
        Color.clear
          .keyframeAnimator(
            initialValue: 0.0,
            trigger: ramped
          ) { view, progress in
            view.overlay {
              ParticleCloudSurface(
                progress: Float(progress) * (alive ? 1 : 0),
                center: center,
                palette: palette
              )
            }
          } keyframes: { _ in
            if ramped {
              LinearKeyframe(1.0, duration: HUDEdgeGlowView.rampDuration)
            } else {
              LinearKeyframe(0.0, duration: HUDEdgeGlowView.rampDuration)
            }
          }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onChange(of: content.sessionEpoch) {
      sweepStart = .now
    }
    .onChange(of: content.showsVoiceVisual, initial: true) { _, listening in
      ramped = listening
    }
  }
}

/// Hosts the MTKView. Constructed inside a @Sendable animator closure, so its
/// init is explicitly nonisolated; the representable callbacks stay on the
/// main actor per the protocol.
private struct ParticleCloudSurface: NSViewRepresentable {
  let progress: Float
  let center: CGPoint
  let palette: HUDGlowPalette

  nonisolated init(progress: Float, center: CGPoint, palette: HUDGlowPalette) {
    self.progress = progress
    self.center = center
    self.palette = palette
  }

  func makeCoordinator() -> ParticleRenderer {
    ParticleRenderer()
  }

  func makeNSView(context: Context) -> MTKView {
    let view = MTKView(frame: .zero, device: context.coordinator.device)
    view.delegate = context.coordinator
    // The compute pipeline writes straight into the drawable.
    view.framebufferOnly = false
    view.colorPixelFormat = .bgra8Unorm
    view.clearColor = MTLClearColorMake(0, 0, 0, 0)
    // macOS: transparency lives on the backing CAMetalLayer (there is no
    // NSView.backgroundColor to clear).
    view.layer?.isOpaque = false
    view.preferredFramesPerSecond = 60
    view.enableSetNeedsDisplay = false
    push(to: view, coordinator: context.coordinator)
    return view
  }

  func updateNSView(_ view: MTKView, context: Context) {
    push(to: view, coordinator: context.coordinator)
  }

  /// At ramp zero the render loop stops entirely; one forced draw first so
  /// the last visible frame is a cleared one, not frozen motes.
  private func push(to view: MTKView, coordinator: ParticleRenderer) {
    coordinator.progress = progress
    coordinator.center = center
    coordinator.applyPalette(palette)
    if progress == 0 {
      if !view.isPaused {
        view.isPaused = true
        view.draw()
      }
    } else {
      view.isPaused = false
    }
  }
}

/// Owns the Metal state and drives one compute pass per frame: clear the
/// drawable, then move and draw every particle. MTKViewDelegate is
/// main-actor-isolated in the macOS 26 SDK, so the renderer lives there too.
@MainActor
final class ParticleRenderer: NSObject {
  /// Mirrors `Particle` in ParticleCloud.metal member-for-member;
  /// HUDParticleLayoutTests pins the layout.
  struct Particle {
    var color: SIMD4<Float>
    var radius: Float
    var lifespan: Float
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
  }

  /// Mirrors `ParticleCloudInfo` in ParticleCloud.metal.
  struct CloudInfo {
    var center: SIMD2<Float>
    var progress: Float
  }

  nonisolated static let particleCount = 32

  var progress: Float = 0
  var center = CGPoint(x: 0.5, y: 0.5)
  private var appliedPalette = HUDGlowPalette.spectrum

  let device: MTLDevice?
  private let pipeline: Pipeline?

  private struct Pipeline {
    let commandQueue: MTLCommandQueue
    let cleanState: MTLComputePipelineState
    let drawState: MTLComputePipelineState
    let particleBuffer: MTLBuffer
  }

  override init() {
    device = MTLCreateSystemDefaultDevice()
    pipeline = device.flatMap(Self.makePipeline)
    super.init()
  }

  /// Fail soft: a missing pipeline draws nothing instead of crashing a
  /// menu-bar app over a decorative effect.
  private static func makePipeline(device: MTLDevice) -> Pipeline? {
    guard
      let commandQueue = device.makeCommandQueue(),
      let library = try? device.makeDefaultLibrary(bundle: .main),
      let cleanFunction = library.makeFunction(name: "cleanScreen"),
      let drawFunction = library.makeFunction(name: "drawParticles"),
      let cleanState = try? device.makeComputePipelineState(function: cleanFunction),
      let drawState = try? device.makeComputePipelineState(function: drawFunction)
    else {
      return nil
    }

    // Zeroed positions make the kernel's respawn branch scatter the
    // cloud on its first frame.
    let colors = HUDGlowPalette.spectrum.particleColors
    let particles = (0..<particleCount).map { index in
      Particle(
        color: colors[index % colors.count],
        radius: Float.random(in: 3..<12),
        lifespan: 0,
        position: .zero,
        velocity: SIMD2(Float.random(in: 2..<4), Float.random(in: 2..<4))
      )
    }
    guard let particleBuffer = device.makeBuffer(
      bytes: particles,
      length: MemoryLayout<Particle>.stride * particleCount
    ) else {
      return nil
    }

    return Pipeline(
      commandQueue: commandQueue,
      cleanState: cleanState,
      drawState: drawState,
      particleBuffer: particleBuffer
    )
  }

  /// Recolors the live buffer when the palette pick changes.
  func applyPalette(_ palette: HUDGlowPalette) {
    guard palette != appliedPalette, let pipeline else { return }
    appliedPalette = palette

    let colors = palette.particleColors
    let particles = pipeline.particleBuffer.contents()
      .bindMemory(to: Particle.self, capacity: Self.particleCount)
    for index in 0..<Self.particleCount {
      particles[index].color = colors[index % colors.count]
    }
  }
}

extension ParticleRenderer: MTKViewDelegate {
  func draw(in view: MTKView) {
    guard
      let pipeline,
      let drawable = view.currentDrawable,
      let commandBuffer = pipeline.commandQueue.makeCommandBuffer(),
      let encoder = commandBuffer.makeComputeCommandEncoder()
    else {
      return
    }

    let texture = drawable.texture
    encoder.setTexture(texture, index: 0)

    encoder.setComputePipelineState(pipeline.cleanState)
    let width = pipeline.cleanState.threadExecutionWidth
    let height = pipeline.cleanState.maxTotalThreadsPerThreadgroup / width
    encoder.dispatchThreads(
      MTLSize(width: texture.width, height: texture.height, depth: 1),
      threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
    )

    encoder.setComputePipelineState(pipeline.drawState)
    encoder.setBuffer(pipeline.particleBuffer, offset: 0, index: 0)
    var info = CloudInfo(
      center: SIMD2(Float(center.x), Float(center.y)),
      progress: progress
    )
    encoder.setBytes(&info, length: MemoryLayout<CloudInfo>.stride, index: 1)
    encoder.dispatchThreads(
      MTLSize(width: Self.particleCount, height: 1, depth: 1),
      threadsPerThreadgroup: MTLSize(
        width: pipeline.drawState.threadExecutionWidth,
        height: 1,
        depth: 1
      )
    )

    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}

#Preview("Particle cloud · session cycle") {
  HUDShellPreviewHarness(visual: .glow, simulatesSessionCycle: true)
}
