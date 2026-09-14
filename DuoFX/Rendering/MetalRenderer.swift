import AppKit
import MetalKit
import MetalPerformanceShaders
#if SWIFT_PACKAGE
import DuoFXCore
#endif

enum RendererError: LocalizedError {
    case unavailable, textureCache, missingResource, allocation, gpu(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "Metal is unavailable on this Mac."
        case .textureCache: "The desktop texture cache could not be created."
        case .missingResource: "A bundled shader or preview image is missing. Rebuild DuoFX."
        case .allocation: "Metal could not allocate rendering resources."
        case .gpu(let detail): "Rendering stopped: \(detail)"
        }
    }
}

enum AppResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }
}

struct RenderUniforms {
    var progress: Float
    var opacity: Float
    var shadow: Float
    var edgeSoftness: Float
    var isOverlay: UInt32
    var direction: UInt32
    var isFold: UInt32
    var foldShadow: Float
    var foldWidth: Float
    var foldBlurRadius: Float
    var isPerspective: UInt32
    var perspectiveStrength: Float
    var perspectiveFeather: Float
}

/// Submission is thread-safe. Rendering and configuration run on the main thread.
final class MetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let mesh: MTLBuffer
    private let vertexCount: Int
    private let bridge: TextureBridge
    private let frameLock = NSLock()
    private var latestFrame: CapturedTexture?
    private let inFlight = DispatchSemaphore(value: 3)
    private var blurTexture: MTLTexture?
    private var foldTexture: MTLTexture?
    private var blur: MPSImageGaussianBlur?
    private var blurSigma: Float = -1
    var configuration = EffectConfiguration()
    var progress: Float = 0
    var isOverlay = true
    var onFailure: (@Sendable (Error) -> Void)?
    var onWillDraw: (() -> Void)?

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else { throw RendererError.unavailable }
        self.device = device; commandQueue = queue
        bridge = try TextureBridge(device: device)
        guard let url = AppResources.bundle.url(forResource: "Shaders", withExtension: "metal") else {
            throw RendererError.missingResource
        }
        let library = try device.makeLibrary(source: String(contentsOf: url), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "blurVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "blurFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear; samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge; samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { throw RendererError.allocation }
        self.sampler = sampler
        let vertices = MeshFactory.fullScreenQuad()
        vertexCount = vertices.count
        guard let mesh = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<MeshVertex>.stride,
                                          options: .storageModeShared) else { throw RendererError.allocation }
        self.mesh = mesh
        super.init()
    }

    @discardableResult
    func submit(_ buffer: CVPixelBuffer) -> Bool {
        // Cache conversion and frame replacement are serialized; no CPU frame copies.
        frameLock.lock(); defer { frameLock.unlock() }
        guard let frame = bridge.texture(from: buffer) else { return false }
        latestFrame = frame
        return true
    }

    func loadPreview() throws {
        guard let url = AppResources.bundle.url(forResource: "Preview", withExtension: "png") else {
            throw RendererError.missingResource
        }
        let texture = try MTKTextureLoader(device: device).newTexture(URL: url, options: [.SRGB: false])
        frameLock.lock(); latestFrame = CapturedTexture(texture: texture, reference: nil, pixelBuffer: nil); frameLock.unlock()
    }

    func clear() {
        frameLock.lock(); latestFrame = nil; frameLock.unlock()
        blurTexture = nil; foldTexture = nil; blur = nil; blurSigma = -1
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor else { inFlight.signal(); return }
        // Start presentation timing only when a drawable is available. Waiting
        // for the initial surface must not consume the clear-to-tilted reveal.
        onWillDraw?()
        frameLock.lock(); let frame = latestFrame; frameLock.unlock()
        guard let frame else { inFlight.signal(); return }
        guard let command = commandQueue.makeCommandBuffer() else {
            inFlight.signal(); onFailure?(RendererError.allocation); return
        }
        do {
            try encode(frame: frame, pass: pass, command: command)
        } catch {
            inFlight.signal(); onFailure?(error); return
        }
        let semaphore = inFlight
        let failure = onFailure
        command.addCompletedHandler { [frame] buffer in
            withExtendedLifetime(frame) {}
            semaphore.signal()
            if buffer.status == .error { failure?(RendererError.gpu(buffer.error?.localizedDescription ?? "GPU command failed")) }
        }
        command.present(drawable)
        command.commit()
    }

    // Shared with offscreen rendering tests so geometry and shader compilation are exercised.
    func encode(frame: CapturedTexture, pass: MTLRenderPassDescriptor, command: MTLCommandBuffer) throws {
        let c = configuration.validated()
        let p = min(max(progress, 0), 1)
        let opacity: Float = isOverlay ? smoothstep(0, 0.035, p) : 1
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        var texture = frame.texture
        // Soft fold samples continuously varying radii from a GPU mip pyramid.
        // Sweep retains its constant Gaussian radius. Perspective projects UVs
        // in the fragment shader and shares Soft fold's variable-radius blur.
        let sigma = (Float(c.blurStrength) * 2).rounded() / 2
        if c.animationMode != .sweep && p > 0 && c.blurStrength > 0 {
            if foldTexture?.width != texture.width || foldTexture?.height != texture.height ||
                foldTexture?.pixelFormat != texture.pixelFormat {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat,
                    width: texture.width, height: texture.height, mipmapped: true)
                descriptor.usage = .shaderRead; descriptor.storageMode = .private
                foldTexture = device.makeTexture(descriptor: descriptor)
            }
            guard let pyramid = foldTexture, let blit = command.makeBlitCommandEncoder() else {
                throw RendererError.allocation
            }
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                      sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                      to: pyramid, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
            blit.generateMipmaps(for: pyramid)
            blit.endEncoding()
            texture = pyramid
        } else if c.animationMode == .sweep && p > 0 && sigma >= 0.5 {
            if blurTexture?.width != texture.width || blurTexture?.height != texture.height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                    width: texture.width, height: texture.height, mipmapped: false)
                descriptor.usage = [.shaderRead, .shaderWrite]; descriptor.storageMode = .private
                blurTexture = device.makeTexture(descriptor: descriptor)
            }
            guard let blurred = blurTexture else { throw RendererError.allocation }
            if blurSigma != sigma {
                blur = MPSImageGaussianBlur(device: device, sigma: sigma)
                blur?.edgeMode = .clamp; blurSigma = sigma
            }
            blur?.encode(commandBuffer: command, sourceTexture: texture, destinationTexture: blurred)
            texture = blurred
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw RendererError.allocation }
        var uniforms = RenderUniforms(progress: p, opacity: opacity,
            shadow: Float(c.shadowStrength), edgeSoftness: Float(c.edgeSoftness), isOverlay: isOverlay ? 1 : 0,
            direction: c.sweepDirection.shaderValue, isFold: c.animationMode != .sweep ? 1 : 0,
            foldShadow: Float(c.foldShadow), foldWidth: Float(c.foldWidth),
            foldBlurRadius: Float(c.blurStrength) * 2.4,
            isPerspective: c.animationMode == .perspective ? 1 : 0,
            perspectiveStrength: Float(c.perspectiveStrength), perspectiveFeather: Float(c.perspectiveFeather))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(mesh, offset: 0, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(frame.texture, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        encoder.endEncoding()
    }
}
