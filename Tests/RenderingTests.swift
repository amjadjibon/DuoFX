import AppKit
import MetalKit
import XCTest
@testable import DuoFX
@testable import DuoFXCore

final class RenderingTests: XCTestCase {
    func testQuadCoversScreenWithCorrectTextureOrientation() {
        let mesh = MeshFactory.fullScreenQuad()
        XCTAssertEqual(mesh.count, 6)
        XCTAssertEqual(mesh.first?.position, [-1, -1])
        XCTAssertEqual(mesh.first?.uv, [0, 1])
        XCTAssertEqual(mesh.last?.position, [-1, 1])
        XCTAssertEqual(mesh.last?.uv, [0, 0])
        XCTAssertEqual(MemoryLayout<MeshVertex>.stride, 16)
        XCTAssertEqual(MemoryLayout<RenderUniforms>.stride, 20)
    }

    func testDesktopPixelsNeverMoveAtAnyLidAngle() throws {
        let fixture = try RenderFixture()
        fixture.renderer.configuration.blurStrength = 0
        for angle in [95.0, 75, 55, 35, 25] {
            let rendered = try fixture.render(closingProgress(angle: angle, workingAngle: 95, minimumAngle: 25))
            // Exact identity at every pixel rules out translation, compression,
            // perspective distortion, flipped UVs, black borders, and a closing fade.
            XCTAssertEqual(rendered, fixture.original, "Desktop moved at \(angle)°")
        }
    }

    func testOverlayCoverageTravelsDownAndUncoveredDesktopIsTransparent() throws {
        let fixture = try RenderFixture()
        fixture.renderer.isOverlay = true
        fixture.renderer.configuration.blurStrength = 0
        XCTAssertTrue(try fixture.render(0).allSatisfy { $0 == 0 })
        let quarter = try fixture.render(0.25)
        XCTAssertEqual(fixture.pixel(quarter, 8, 4), [0, 0, 255, 255])
        XCTAssertEqual(fixture.pixel(quarter, 8, 32), [0, 0, 0, 0])
        let halfway = try fixture.render(0.5)
        XCTAssertEqual(fixture.pixel(halfway, 8, 8), [0, 0, 255, 255])
        XCTAssertEqual(fixture.pixel(halfway, 8, 56), [0, 0, 0, 0])
        for y in [26, 30, 34, 38] {
            let expected = blurCoverage(y: (Float(y) + 0.5) / 64, progress: 0.5, edgeSoftness: 0.12) * 255
            XCTAssertEqual(Float(fixture.pixel(halfway, 8, y)[3]), expected, accuracy: 1)
        }
        let lower = try fixture.render(0.75)
        XCTAssertEqual(fixture.pixel(lower, 8, 32)[3], 255)
        XCTAssertEqual(fixture.pixel(lower, 8, 60)[3], 0)
        XCTAssertEqual(try fixture.render(1), fixture.original)
        XCTAssertEqual(try fixture.render(0.25), quarter)
    }

    func testBlurChangesOnlyTheCoveredRegion() throws {
        let fixture = try RenderFixture()
        fixture.renderer.configuration.blurStrength = 8
        let halfway = try fixture.render(0.5)
        // A vertical color boundary softens at the top while the bottom stays sharp.
        XCTAssertGreaterThan(fixture.pixel(halfway, 30, 8)[1], 20)
        XCTAssertEqual(fixture.pixel(halfway, 30, 56), fixture.pixel(fixture.original, 30, 56))
        let closed = try fixture.render(1)
        XCTAssertGreaterThan(fixture.pixel(closed, 30, 56)[1], 20)
        XCTAssertGreaterThan(fixture.pixel(closed, 8, 8)[2], 200)
        XCTAssertEqual(try fixture.render(0), fixture.original)
    }

    func testBundledPreviewRendersAtSweepStages() throws {
        let fixture = try RenderFixture(useBundledImage: true)
        fixture.renderer.configuration.blurStrength = 12
        for (name, p): (String, Float) in [("open", 0), ("half", 0.5), ("closed", 1)] {
            let pixels = try fixture.render(p)
            XCTAssertEqual(pixels.count, fixture.width * fixture.height * 4)
            // Optional test artifacts contain only our bundled fixture, never a capture.
            if let directory = ProcessInfo.processInfo.environment["DUOFX_PREVIEW_SNAPSHOTS"] {
                try fixture.save(pixels, to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
        }
    }
}

private final class RenderFixture {
    let renderer: MetalRenderer
    let input: MTLTexture
    let output: MTLTexture
    let queue: MTLCommandQueue
    let width: Int
    let height: Int
    var original: [UInt8] = []

    init(useBundledImage: Bool = false) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal GPU unavailable") }
        renderer = try MetalRenderer(device: device)
        renderer.isOverlay = false
        renderer.configuration.shadowStrength = 0
        queue = try XCTUnwrap(device.makeCommandQueue())
        if useBundledImage {
            let url = try XCTUnwrap(AppResources.bundle.url(forResource: "Preview", withExtension: "png"))
            input = try MTKTextureLoader(device: device).newTexture(URL: url, options: [.SRGB: false])
        } else {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 64, height: 64, mipmapped: false)
            descriptor.storageMode = .shared; descriptor.usage = .shaderRead
            input = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            original = [UInt8](repeating: 255, count: 64 * 64 * 4)
            for y in 0..<64 {
                for x in 0..<64 {
                    let i = (y * 64 + x) * 4
                    original[i] = y >= 32 ? 255 : 0
                    original[i + 1] = x >= 32 ? 255 : 0
                    original[i + 2] = y < 32 ? 255 : 0
                }
            }
            input.replace(region: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0, withBytes: original, bytesPerRow: 64 * 4)
        }
        width = input.width; height = input.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = .renderTarget
        output = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    func render(_ progress: Float) throws -> [UInt8] {
        renderer.progress = progress
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = output
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        try renderer.encode(frame: CapturedTexture(texture: input, reference: nil, pixelBuffer: nil), pass: pass, command: command)
        command.commit(); command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed, command.error?.localizedDescription ?? "")
        var result = [UInt8](repeating: 0, count: width * height * 4)
        output.getBytes(&result, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return result
    }

    func pixel(_ image: [UInt8], _ x: Int, _ y: Int) -> [UInt8] {
        Array(image[((y * width + x) * 4)..<((y * width + x) * 4 + 4)])
    }

    func save(_ pixels: [UInt8], to url: URL) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
        let bytes = try XCTUnwrap(bitmap.bitmapData)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            bytes[offset] = pixels[offset + 2]; bytes[offset + 1] = pixels[offset + 1]
            bytes[offset + 2] = pixels[offset]; bytes[offset + 3] = pixels[offset + 3]
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
