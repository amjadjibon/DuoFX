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
        XCTAssertEqual(MemoryLayout<RenderUniforms>.stride, 52)
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

    func testFoldKeepsDesktopPixelsFixedInEveryDirection() throws {
        let fixture = try RenderFixture()
        fixture.renderer.configuration.animationMode = .fold
        fixture.renderer.configuration.blurStrength = 0
        fixture.renderer.configuration.foldShadow = 0
        for direction in SweepDirection.allCases {
            fixture.renderer.configuration.sweepDirection = direction
            for progress: Float in [0, 0.25, 0.5, 0.75, 1] {
                XCTAssertEqual(try fixture.render(progress), fixture.original,
                               "Desktop pixels moved in \(direction) at \(progress)")
            }
        }
    }

    func testDirectionControlsCoverageAndLeavesOtherSideTransparent() throws {
        let fixture = try RenderFixture()
        fixture.renderer.isOverlay = true
        fixture.renderer.configuration.blurStrength = 0
        fixture.renderer.configuration.foldShadow = 0
        let probes: [(SweepDirection, Int, Int, Int, Int)] = [
            (.down, 32, 8, 32, 56), (.up, 32, 56, 32, 8),
            (.right, 8, 32, 56, 32), (.left, 56, 32, 8, 32)
        ]
        for mode: AnimationMode in [.sweep, .fold] {
            fixture.renderer.configuration.animationMode = mode
            for (direction, x, y, clearX, clearY) in probes {
                fixture.renderer.configuration.sweepDirection = direction
                XCTAssertTrue(try fixture.render(0).allSatisfy { $0 == 0 })
                let halfway = try fixture.render(0.5)
                XCTAssertEqual(fixture.pixel(halfway, x, y)[3], 255)
                XCTAssertEqual(fixture.pixel(halfway, clearX, clearY), [0, 0, 0, 0])
                XCTAssertEqual(try fixture.render(1), fixture.original)
                _ = try fixture.render(0.75)
                XCTAssertEqual(try fixture.render(0.5), halfway, "Opening must reverse the same shading path")
            }
        }
    }

    func testFoldShadowAddsDepthOnlyOnTheCoveredSide() throws {
        let fixture = try RenderFixture()
        fixture.renderer.configuration.animationMode = .fold
        fixture.renderer.configuration.sweepDirection = .right
        fixture.renderer.configuration.blurStrength = 0
        fixture.renderer.configuration.foldShadow = 0
        let flat = try fixture.render(0.5)
        fixture.renderer.configuration.foldShadow = 1
        let shaded = try fixture.render(0.5)
        XCTAssertLessThan(fixture.pixel(shaded, 8, 8)[2], fixture.pixel(flat, 8, 8)[2] - 20)
        XCTAssertLessThan(fixture.pixel(shaded, 8, 8)[2], fixture.pixel(shaded, 24, 8)[2])
        XCTAssertEqual(fixture.pixel(shaded, 56, 8), fixture.pixel(flat, 56, 8))
        XCTAssertEqual(try fixture.render(0), fixture.original)
        let closed = try fixture.render(1)
        XCTAssertEqual(fixture.pixel(closed, 8, 8), [0, 0, 0, 255])
    }

    func testFoldBlurRadiusBuildsBehindTheFrontAndWithClosing() throws {
        let fixture = try RenderFixture()
        fixture.renderer.configuration.animationMode = .fold
        fixture.renderer.configuration.blurStrength = 8
        fixture.renderer.configuration.foldShadow = 0
        let early = try fixture.render(0.25)
        let halfway = try fixture.render(0.5)
        let later = try fixture.render(0.75)
        // Green leaking across a vertical red/green edge measures blur width.
        // It increases toward the top and as the lid closes, rather than merely
        // fading a single pre-blurred image over every covered pixel.
        XCTAssertGreaterThan(fixture.pixel(halfway, 22, 4)[1], fixture.pixel(halfway, 22, 28)[1] + 5)
        XCTAssertGreaterThan(fixture.pixel(halfway, 22, 4)[1], fixture.pixel(early, 22, 4)[1] + 5)
        XCTAssertGreaterThan(fixture.pixel(later, 22, 4)[1], fixture.pixel(halfway, 22, 4)[1] + 5)
        XCTAssertEqual(fixture.pixel(halfway, 22, 56), fixture.pixel(fixture.original, 22, 56))
        XCTAssertEqual(try fixture.render(0.5), halfway)
        XCTAssertEqual(try fixture.render(0), fixture.original)
        fixture.renderer.clear()
        XCTAssertEqual(try fixture.render(0.5), halfway, "Recreated GPU resources must render identically")
    }

    func testFoldTransitionWidthSpreadsShadingAndOverlayMatchesPreview() throws {
        let fixture = try RenderFixture()
        fixture.renderer.configuration.animationMode = .fold
        fixture.renderer.configuration.blurStrength = 8
        fixture.renderer.configuration.foldShadow = 0.7
        fixture.renderer.configuration.foldWidth = 0.04
        let narrow = try fixture.render(0.5)
        fixture.renderer.configuration.foldWidth = 0.35
        let wide = try fixture.render(0.5)
        XCTAssertLessThan(fixture.pixel(narrow, 8, 8)[2], fixture.pixel(wide, 8, 8)[2] - 20)
        fixture.renderer.isOverlay = true
        let overlay = try fixture.render(0.5)
        for y in [4, 24, 30, 34, 38, 56] {
            let actual = fixture.pixel(overlay, 8, y)
            let background = fixture.pixel(fixture.original, 8, y)
            let preview = fixture.pixel(wide, 8, y)
            for channel in 0..<3 {
                let composed = Float(actual[channel]) + Float(background[channel]) * (1 - Float(actual[3]) / 255)
                XCTAssertEqual(composed, Float(preview[channel]), accuracy: 1.5)
                XCTAssertLessThanOrEqual(actual[channel], actual[3], "Overlay must remain premultiplied")
            }
        }
    }

    func testFoldReferencePreviewRenders() throws {
        let fixture = try RenderFixture(useBundledImage: true)
        fixture.renderer.configuration.applyFoldReference()
        for (name, progress): (String, Float) in [("open", 0), ("quarter", 0.25), ("half", 0.5), ("three-quarter", 0.75), ("closed", 1)] {
            let image = try fixture.render(progress)
            XCTAssertEqual(image.count, fixture.width * fixture.height * 4)
            if let directory = ProcessInfo.processInfo.environment["DUOFX_PREVIEW_SNAPSHOTS"] {
                try fixture.save(image, to: URL(fileURLWithPath: directory).appendingPathComponent("fold-\(name).png"))
            }
        }
    }

    func testPerspectiveProjectsTowardHingeAndReverses() throws {
        let fixture = try RenderFixture()
        fixture.renderer.configuration.animationMode = .perspective
        fixture.renderer.configuration.perspectiveStrength = 1
        fixture.renderer.configuration.blurStrength = 0
        fixture.renderer.configuration.foldShadow = 0
        XCTAssertEqual(try fixture.render(0), fixture.original)
        let halfway = try fixture.render(0.5)
        XCTAssertEqual(fixture.pixel(halfway, 16, 4), [0, 0, 0, 255])
        XCTAssertEqual(fixture.pixel(halfway, 16, 38), [0, 0, 255, 255], "Projection moves the red upper half downward")
        XCTAssertEqual(fixture.pixel(halfway, 16, 60), fixture.pixel(fixture.original, 16, 60))
        let closed = try fixture.render(1)
        XCTAssertEqual(fixture.pixel(closed, 16, 38), [0, 0, 0, 255])
        XCTAssertEqual(try fixture.render(0.5), halfway)
        fixture.renderer.isOverlay = true
        XCTAssertTrue(try fixture.render(0).allSatisfy { $0 == 0 })
        XCTAssertEqual(try fixture.render(0.5), halfway, "Backdrop must conceal the untransformed desktop")
    }

    func testPerspectiveStrengthZeroMatchesSoftFoldInEveryDirection() throws {
        let fixture = try RenderFixture()
        fixture.renderer.configuration.blurStrength = 8
        fixture.renderer.configuration.perspectiveStrength = 0
        for overlay in [false, true] {
            fixture.renderer.isOverlay = overlay
            for direction in SweepDirection.allCases {
                fixture.renderer.configuration.sweepDirection = direction
                for progress: Float in [0, 0.25, 0.5, 1] {
                    fixture.renderer.configuration.animationMode = .fold
                    let fold = try fixture.render(progress)
                    fixture.renderer.configuration.animationMode = .perspective
                    XCTAssertEqual(try fixture.render(progress), fold)
                }
            }
        }
    }

    func testPerspectiveDirectionsKeepDestinationEdgeVisible() throws {
        let fixture = try RenderFixture()
        fixture.renderer.configuration.animationMode = .perspective
        fixture.renderer.configuration.perspectiveStrength = 1
        fixture.renderer.configuration.blurStrength = 0
        fixture.renderer.configuration.foldShadow = 0
        for (direction, x, y, blankX, blankY): (SweepDirection, Int, Int, Int, Int) in [
            (.down, 16, 60, 16, 4), (.up, 16, 4, 16, 60),
            (.right, 60, 16, 4, 16), (.left, 4, 16, 60, 16)
        ] {
            fixture.renderer.configuration.sweepDirection = direction
            let image = try fixture.render(0.5)
            XCTAssertEqual(fixture.pixel(image, x, y), fixture.pixel(fixture.original, x, y))
            XCTAssertEqual(fixture.pixel(image, blankX, blankY), [0, 0, 0, 255])
        }
    }

    func testPerspectiveBundledPreviewRenders() throws {
        let fixture = try RenderFixture(useBundledImage: true)
        fixture.renderer.configuration.applyFoldReference()
        fixture.renderer.configuration.animationMode = .perspective
        for (name, progress): (String, Float) in [("open", 0), ("half", 0.5), ("closed", 1)] {
            let image = try fixture.render(progress)
            XCTAssertEqual(image.count, fixture.width * fixture.height * 4)
            if let directory = ProcessInfo.processInfo.environment["DUOFX_PREVIEW_SNAPSHOTS"] {
                try fixture.save(image, to: URL(fileURLWithPath: directory).appendingPathComponent("perspective-\(name).png"))
            }
        }
    }

    func testPerspectiveOutlineFadesGraduallyAndWidthIsAdjustable() throws {
        let fixture = try RenderFixture()
        fixture.renderer.configuration.animationMode = .perspective
        fixture.renderer.configuration.perspectiveStrength = 1
        fixture.renderer.configuration.blurStrength = 0
        fixture.renderer.configuration.foldShadow = 0
        fixture.renderer.configuration.perspectiveFeather = 0
        let crisp = try fixture.render(0.5)
        fixture.renderer.configuration.perspectiveFeather = 0.12
        let faded = try fixture.render(0.5)
        let ramp = [28, 30, 32, 34].map { fixture.pixel(faded, 16, $0)[2] }
        XCTAssertEqual(ramp, ramp.sorted())
        XCTAssertGreaterThan(ramp.last!, ramp.first! + 100)
        XCTAssertGreaterThan(ramp.first!, 0)
        XCTAssertLessThan(fixture.pixel(faded, 16, 30)[2], fixture.pixel(crisp, 16, 30)[2] - 50)
        // Both slanted sides soften too, while the center near the hinge stays intact.
        XCTAssertLessThan(fixture.pixel(faded, 8, 40)[2], fixture.pixel(crisp, 8, 40)[2])
        XCTAssertLessThan(fixture.pixel(faded, 55, 40)[1], fixture.pixel(crisp, 55, 40)[1])
        XCTAssertEqual(fixture.pixel(faded, 16, 60), fixture.pixel(crisp, 16, 60))
        XCTAssertEqual(try fixture.render(0), fixture.original)
        _ = try fixture.render(1)
        XCTAssertEqual(try fixture.render(0.5), faded)
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
        renderer.configuration.edgeSoftness = 0.12
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
