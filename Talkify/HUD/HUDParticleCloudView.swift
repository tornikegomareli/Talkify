import MetalKit
import SwiftUI

/// The Edge Glow particle cloud: silver motes drifting toward the glow origin
/// while listening, rendered by a Metal compute pipeline (ParticleCloud.metal)
/// into a transparent MTKView. The session ramp mirrors the border glow's —
/// same trigger, same duration — so the cloud blooms and drains with it. A
/// dead microphone zeroes the ramp instantly: only the static amber outline
/// may remain (CONTEXT.md: dead microphone ≠ silence).
struct HUDParticleCloudView: View {
    let content: DictationHUDContent
    /// The glow origin in this view's normalized coordinates.
    let center: CGPoint

    var body: some View {
        // Plain values for the @Sendable keyframeAnimator content closure;
        // the body re-evaluates on every content change, so they stay fresh.
        let listening = content.showsVoiceVisual
        let alive = content.isAudioAlive
        let center = center
        Color.clear
            .keyframeAnimator(
                initialValue: 0.0,
                trigger: listening
            ) { view, progress in
                view.overlay {
                    ParticleCloudSurface(
                        progress: Float(progress) * (alive ? 1 : 0),
                        center: center
                    )
                }
            } keyframes: { _ in
                if listening {
                    LinearKeyframe(1.0, duration: HUDEdgeGlowView.rampDuration)
                } else {
                    LinearKeyframe(0.0, duration: HUDEdgeGlowView.rampDuration)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Hosts the MTKView. Constructed inside a @Sendable animator closure, so its
/// init is explicitly nonisolated; the representable callbacks stay on the
/// main actor per the protocol.
private struct ParticleCloudSurface: NSViewRepresentable {
    let progress: Float
    let center: CGPoint

    nonisolated init(progress: Float, center: CGPoint) {
        self.progress = progress
        self.center = center
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

    /// The silver language the glow speaks: fringe blue-violet to white.
    private static let colors: [SIMD4<Float>] = [
        SIMD4(0.62, 0.72, 1.0, 1.0),
        SIMD4(0.85, 0.90, 1.0, 1.0),
        SIMD4(1.0, 1.0, 1.0, 1.0),
    ]

    var progress: Float = 0
    var center = CGPoint(x: 0.5, y: 0.5)

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
