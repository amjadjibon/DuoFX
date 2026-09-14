import MetalKit
import XCTest
@testable import DuoFX
@testable import DuoFXCore

final class RenderingPerformanceTests: XCTestCase {
    func testFullSizeBlurFrameBudget() throws {
        guard ProcessInfo.processInfo.environment["DUOFX_RENDER_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt in with DUOFX_RENDER_BENCHMARK=1 for GPU timings")
        }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal unavailable") }
        let renderer = try MetalRenderer(device: device)
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 3024, height: 1964, mipmapped: false)
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .renderTarget]
        let input = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let output = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        // Initialize a synthetic image; never capture the desktop for benchmarks.
        let setup = try XCTUnwrap(queue.makeCommandBuffer())
        let clear = MTLRenderPassDescriptor(); clear.colorAttachments[0].texture = input
        clear.colorAttachments[0].loadAction = .clear; clear.colorAttachments[0].storeAction = .store
        clear.colorAttachments[0].clearColor = MTLClearColorMake(0.3, 0.5, 0.7, 1)
        try XCTUnwrap(setup.makeRenderCommandEncoder(descriptor: clear)).endEncoding()
        setup.commit(); setup.waitUntilCompleted()
        for (mode, radius): (AnimationMode, Double) in [(.sweep, 0), (.sweep, 12), (.sweep, 18), (.fold, 30)] {
            renderer.clear(); renderer.configuration.animationMode = mode
            renderer.configuration.blurStrength = radius
            var times: [Double] = []
            for index in 0..<140 {
                renderer.progress = Float(index % 100 + 1) / 100
                let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = output
                let command = try XCTUnwrap(queue.makeCommandBuffer())
                try renderer.encode(frame: CapturedTexture(texture: input, reference: nil, pixelBuffer: nil),
                                    pass: pass, command: command)
                command.commit(); command.waitUntilCompleted()
                XCTAssertEqual(command.status, .completed)
                if index >= 20 { times.append((command.gpuEndTime - command.gpuStartTime) * 1000) }
            }
            times.sort()
            print(String(format: "DuoFX GPU 3024x1964 %@ blur=%.0f: p50=%.3f p95=%.3f p99=%.3f ms", mode.rawValue, radius,
                         times[60], times[114], times[118]))
        }
    }
}
