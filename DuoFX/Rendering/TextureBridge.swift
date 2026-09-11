import CoreVideo
import Metal

struct CapturedTexture {
    let texture: MTLTexture
    // Retain both owners until the GPU command buffer has completed.
    let reference: CVMetalTexture?
    let pixelBuffer: CVPixelBuffer?
}

final class TextureBridge {
    private let cache: CVMetalTextureCache
    init(device: MTLDevice) throws {
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let cache else { throw RendererError.textureCache }
        self.cache = cache
    }

    func texture(from pixelBuffer: CVPixelBuffer) -> CapturedTexture? {
        var reference: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &reference
        )
        guard result == kCVReturnSuccess, let reference,
              let texture = CVMetalTextureGetTexture(reference) else { return nil }
        return CapturedTexture(texture: texture, reference: reference, pixelBuffer: pixelBuffer)
    }
}
