import MetalKit
import SwiftUI
#if SWIFT_PACKAGE
import DuoFXCore
#endif

struct MetalPreview: NSViewRepresentable {
    var configuration: EffectConfiguration
    var progress: Float
    var easesChanges: Bool
    @Binding var error: String?
    final class Coordinator {
        var renderer: MetalRenderer?
        var target: Float = 0
        var easing = AngleSmoother()
        var easesChanges = true
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.isPaused = true; view.enableSetNeedsDisplay = false
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = min(NSScreen.main?.maximumFramesPerSecond ?? 60, 120)
        do {
            let renderer = try MetalRenderer()
            renderer.isOverlay = false
            renderer.onFailure = { failure in
                DispatchQueue.main.async { self.error = failure.localizedDescription }
            }
            try renderer.loadPreview()
            view.device = renderer.device; view.delegate = renderer
            let coordinator = context.coordinator
            coordinator.renderer = renderer
            renderer.onWillDraw = { [weak coordinator, weak view] in
                guard let coordinator, let renderer = coordinator.renderer else { return }
                let value = coordinator.easesChanges
                    ? Float(coordinator.easing.update(Double(coordinator.target), at: ProcessInfo.processInfo.systemUptime,
                                                      response: renderer.configuration.motionResponse)) : coordinator.target
                renderer.progress = min(max(value, 0), 1)
                // Let the preview rest once settled; changing a control wakes it.
                if !coordinator.easesChanges || (abs(renderer.progress - coordinator.target) < 0.0001 && abs(coordinator.easing.velocity) < 0.001) {
                    renderer.progress = coordinator.target; view?.isPaused = true
                }
            }
        } catch {
            DispatchQueue.main.async { self.error = error.localizedDescription }
        }
        return view
    }
    func updateNSView(_ view: MTKView, context: Context) {
        let coordinator = context.coordinator
        if view.isPaused || coordinator.easesChanges != easesChanges {
            // Resume from the visible position after resting, rather than
            // treating time spent idle as a wake gap that snaps to the target.
            coordinator.easing = AngleSmoother()
            _ = coordinator.easing.update(Double(coordinator.renderer?.progress ?? progress),
                                          at: ProcessInfo.processInfo.systemUptime)
        }
        coordinator.renderer?.configuration = configuration
        coordinator.target = progress; coordinator.easesChanges = easesChanges
        view.isPaused = false
    }
    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true; view.delegate = nil
        coordinator.renderer?.onWillDraw = nil
        coordinator.renderer?.clear(); coordinator.renderer = nil
    }
}
