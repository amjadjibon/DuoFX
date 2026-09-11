import AppKit

@main
struct GenerateIcon {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "DuoFX", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pass an output .iconset directory"])
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                    let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                    throw NSError(domain: "DuoFX", code: 2)
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                let side = CGFloat(pixels)
                let rect = NSRect(x: side * 0.07, y: side * 0.07, width: side * 0.86, height: side * 0.86)
                let background = NSBezierPath(roundedRect: rect, xRadius: side * 0.19, yRadius: side * 0.19)
                let gradient = NSGradient(starting: NSColor(srgbRed: 0.04, green: 0.22, blue: 0.31, alpha: 1),
                                          ending: NSColor(srgbRed: 0.07, green: 0.65, blue: 0.61, alpha: 1))!
                gradient.draw(in: background, angle: 65)
                MenuBarIcon.drawGlyph(in: NSRect(x: side * 0.23, y: side * 0.25, width: side * 0.54, height: side * 0.52), color: .white)
                NSGraphicsContext.restoreGraphicsState()
                guard let data = bitmap.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "DuoFX", code: 3)
                }
                let suffix = scale == 2 ? "@2x" : ""
                try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
            }
        }
    }
}
