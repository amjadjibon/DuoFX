import AppKit
import CoreMedia
import ScreenCaptureKit

@MainActor
protocol ScreenCapturing: AnyObject {
    func invalidate()
    func start(displayID: CGDirectDisplayID,
               onFrame: @escaping @Sendable (CVPixelBuffer) -> Void,
               onFailure: @escaping @Sendable (Error) -> Void) async throws
    func stop() async
}

@MainActor
final class ScreenCaptureService: ScreenCapturing {
    private var stream: SCStream?
    private var output: CaptureOutput?
    private var generation = 0
    private let queue = DispatchQueue(label: "com.duofx.capture", qos: .userInteractive)

    func start(displayID: CGDirectDisplayID,
               onFrame: @escaping @Sendable (CVPixelBuffer) -> Void,
               onFailure: @escaping @Sendable (Error) -> Void) async throws {
        let token = generation
        // Permission is requested only after the user enables Live desktop.
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw CaptureError.permissionDenied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard token == generation else { throw CancellationError() }
        guard CGDisplayIsBuiltin(displayID) != 0,
              let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noBuiltInDisplay
        }
        guard let ownApp = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else {
            throw CaptureError.ownApplicationMissing
        }
        let filter = SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = CGDisplayPixelsWide(displayID)
        configuration.height = CGDisplayPixelsHigh(displayID)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        let output = CaptureOutput(onFrame: onFrame, onFailure: onFailure)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
        self.output = output; self.stream = stream
        do {
            try await stream.startCapture()
            guard token == generation else { throw CancellationError() }
        }
        catch {
            output.deactivate()
            try? await stream.stopCapture()
            self.stream = nil; self.output = nil
            throw error
        }
    }

    func invalidate() {
        generation += 1
        output?.deactivate()
    }

    func stop() async {
        output?.deactivate()
        if let stream {
            do { try await stream.stopCapture() }
            catch { /* A stream already stopped by the system needs no further teardown. */ }
        }
        stream = nil; output = nil
    }
}

private final class CaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private let onFrame: @Sendable (CVPixelBuffer) -> Void
    private let onFailure: @Sendable (Error) -> Void
    init(onFrame: @escaping @Sendable (CVPixelBuffer) -> Void,
         onFailure: @escaping @Sendable (Error) -> Void) {
        self.onFrame = onFrame; self.onFailure = onFailure
    }
    func deactivate() { lock.lock(); active = false; lock.unlock() }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: status) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        lock.lock(); defer { lock.unlock() }
        if active { onFrame(buffer) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); let shouldReport = active; active = false; lock.unlock()
        if shouldReport { onFailure(error) }
    }
}
