import MetalKit
import XCTest
@testable import DuoFX
@testable import DuoFXCore

final class RenderingTests: XCTestCase {
    func testMeshHasNoGapsAndCorrectTextureOrientation() {
        let mesh = MeshFactory.grid(segments: 64)
        XCTAssertEqual(mesh.count, 384)
        XCTAssertEqual(mesh.first?.position, [-1, -1])
        XCTAssertEqual(mesh.first?.uv, [0, 1])
        XCTAssertEqual(mesh.last?.position, [-1, 1])
        XCTAssertEqual(mesh.last?.uv, [0, 0])
        XCTAssertEqual(MemoryLayout<MeshVertex>.stride, 16)
        XCTAssertEqual(MemoryLayout<RenderUniforms>.stride, 32)
        for row in 0..<63 {
            XCTAssertEqual(mesh[row * 6 + 2].position, mesh[(row + 1) * 6].position)
        }
    }

    func testGPUProjectionOrientationFadeAndBlur() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal GPU unavailable") }
        let renderer = try MetalRenderer(device: device)
        renderer.isOverlay = false
        renderer.configuration.blurStrength = 0
        renderer.configuration.shadowStrength = 0
        renderer.configuration.verticalStretch = 0
        let size = 64
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: size, height: size, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.shaderRead, .renderTarget]
        let input = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let output = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                bytes[i] = y >= 32 ? 255 : 0 // Bottom blue.
                bytes[i + 1] = x >= 32 ? 255 : 0 // Right green.
                bytes[i + 2] = y < 32 ? 255 : 0 // Top red.
            }
        }
        input.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: bytes, bytesPerRow: size * 4)
        let queue = try XCTUnwrap(device.makeCommandQueue())
        func render(_ p: Float) throws -> [UInt8] {
            renderer.progress = p
            let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = output
            let command = try XCTUnwrap(queue.makeCommandBuffer())
            try renderer.encode(frame: CapturedTexture(texture: input, reference: nil, pixelBuffer: nil), pass: pass, command: command)
            command.commit(); command.waitUntilCompleted()
            XCTAssertEqual(command.status, .completed, command.error?.localizedDescription ?? "")
            var result = [UInt8](repeating: 0, count: bytes.count)
            output.getBytes(&result, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
            return result
        }
        let open = try render(0)
        func pixel(_ image: [UInt8], _ x: Int, _ y: Int) -> [UInt8] { Array(image[((y * size + x) * 4)..<((y * size + x) * 4 + 4)]) }
        XCTAssertEqual(pixel(open, 8, 8), [0, 0, 255, 255])
        XCTAssertEqual(pixel(open, 56, 8), [0, 255, 255, 255])
        XCTAssertEqual(pixel(open, 8, 56), [255, 0, 0, 255])
        let folded = try render(0.5)
        XCTAssertEqual(pixel(folded, 32, 5), [0, 0, 0, 255])
        XCTAssertGreaterThan(pixel(folded, 20, 58)[0], 240)
        for angle in [95.0, 75, 55, 35, 25] {
            let image = try render(closingProgress(angle: angle, workingAngle: 95, minimumAngle: 25))
            XCTAssertEqual(image.count, size * size * 4)
        }
        let closed = try render(1)
        XCTAssertTrue(stride(from: 0, to: closed.count, by: 4).allSatisfy { closed[$0] == 0 && closed[$0 + 1] == 0 && closed[$0 + 2] == 0 })
        renderer.configuration.blurStrength = 12
        let blurred = try render(0.5)
        XCTAssertNotEqual(blurred, folded)
        renderer.isOverlay = true
        let hidden = try render(0)
        XCTAssertTrue(hidden.allSatisfy { $0 == 0 })
        try renderer.loadPreview()
        renderer.clear()
    }
}
