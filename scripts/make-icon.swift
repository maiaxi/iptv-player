// Renders the app icon into an .iconset folder. Usage: swift make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824/1024 body with rounded corners.
    let inset = s * 0.098
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    path.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.45, green: 0.22, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.95, alpha: 1),
    ])!.draw(in: body, angle: -55)

    // Screen
    let screen = NSRect(x: body.minX + body.width * 0.17, y: body.minY + body.height * 0.3,
                        width: body.width * 0.66, height: body.height * 0.46)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: screen.width * 0.1, yRadius: screen.width * 0.1)
    NSColor.white.withAlphaComponent(0.95).setFill()
    screenPath.fill()

    // Stand
    let stand = NSRect(x: body.midX - body.width * 0.14, y: body.minY + body.height * 0.2,
                       width: body.width * 0.28, height: body.height * 0.045)
    NSBezierPath(roundedRect: stand, xRadius: stand.height / 2, yRadius: stand.height / 2).fill()

    // Play triangle
    let tri = NSBezierPath()
    let cx = screen.midX + screen.width * 0.02, cy = screen.midY, r = screen.height * 0.24
    tri.move(to: NSPoint(x: cx - r * 0.75, y: cy + r))
    tri.line(to: NSPoint(x: cx + r, y: cy))
    tri.line(to: NSPoint(x: cx - r * 0.75, y: cy - r))
    tri.close()
    NSColor(calibratedRed: 0.32, green: 0.3, blue: 0.96, alpha: 1).setFill()
    tri.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
