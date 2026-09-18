import AppKit
import MetalKit

@MainActor
protocol OverlayPresenting: AnyObject {
    func show(renderer: MetalRenderer, on screen: NSScreen)
    func hide()
}

@MainActor
final class OverlayWindowController: OverlayPresenting {
    private var panel: NSPanel?
    private var metalView: MTKView?

    static func builtInScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = displayID(for: screen) else { return false }
            return CGDisplayIsBuiltin(id) != 0 && CGDisplayIsActive(id) != 0
        }
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    func show(renderer: MetalRenderer, on screen: NSScreen) {
        guard panel == nil else { return }
        let panel = PassthroughPanel(contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Below menus so Pause remains readable while the desktop is blurred.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: renderer.device)
        view.wantsLayer = true; view.layer?.isOpaque = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.preferredFramesPerSecond = min(max(screen.maximumFramesPerSecond, 60), 120)
        PerformanceRun.shared?.record("requested-hz", value: Double(view.preferredFramesPerSecond))
        view.framebufferOnly = true
        view.isPaused = false; view.enableSetNeedsDisplay = false
        view.autoresizingMask = [.width, .height]; view.delegate = renderer
        panel.contentView = view
        panel.setFrame(screen.frame, display: false)
        panel.orderFrontRegardless()
        self.panel = panel; metalView = view
    }

    func hide() {
        metalView?.isPaused = true; metalView?.delegate = nil
        panel?.orderOut(nil); panel?.close()
        metalView = nil; panel = nil
    }
}

private final class PassthroughPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
