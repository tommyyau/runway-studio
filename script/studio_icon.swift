import AppKit

// Original vector artwork, rendered at each icon size. No third-party brand assets.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (name, size) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
    ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)
] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: Double(size) / 1024, y: Double(size) / 1024)
    let shape = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.17, blue: 0.24, alpha: 1),
               ending: NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.075, alpha: 1))!.draw(in: shape, angle: -45)
    let ring = NSBezierPath(ovalIn: NSRect(x: 220, y: 220, width: 584, height: 584))
    NSColor(calibratedRed: 0.32, green: 0.91, blue: 0.74, alpha: 0.15).setStroke()
    ring.lineWidth = 54; ring.stroke()
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 292, startAngle: 90, endAngle: 340, clockwise: true)
    NSColor(calibratedRed: 0.40, green: 0.96, blue: 0.77, alpha: 1).setStroke()
    arc.lineWidth = 54; arc.lineCapStyle = .round; arc.stroke()
    let signal = NSBezierPath()
    signal.move(to: NSPoint(x: 307, y: 495))
    for point in [NSPoint(x: 410, y: 495), NSPoint(x: 460, y: 630), NSPoint(x: 540, y: 390), NSPoint(x: 594, y: 515), NSPoint(x: 711, y: 515)] {
        signal.line(to: point)
    }
    NSColor.white.setStroke()
    signal.lineWidth = 40; signal.lineCapStyle = .round; signal.lineJoinStyle = .round; signal.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name + ".png"))
}
