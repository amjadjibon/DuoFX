import AppKit

enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { rect in
            drawGlyph(in: rect.insetBy(dx: 2, dy: 1), color: .black)
            return true
        }
        // Let macOS choose the ink color for light/dark menu bars and selection.
        image.isTemplate = true
        image.accessibilityDescription = "DuoFX"
        return image
    }()

    /// The same folding laptop mark is used by the menu item and app icon.
    static func drawGlyph(in rect: NSRect, color: NSColor) {
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let screen = NSBezierPath()
        screen.move(to: point(0.15, 0.22))
        screen.line(to: point(0.15, 0.75))
        screen.line(to: point(0.65, 0.94))
        screen.line(to: point(0.85, 0.22))
        screen.close()
        screen.move(to: point(0.65, 0.94))
        screen.line(to: point(0.53, 0.22))
        screen.move(to: point(0.03, 0.06))
        screen.line(to: point(0.97, 0.06))
        screen.lineWidth = rect.width * 0.075
        screen.lineJoinStyle = .round
        screen.lineCapStyle = .round
        color.setStroke()
        screen.stroke()
    }
}
