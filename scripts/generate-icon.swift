import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/generate-icon.swift <output.iconset>\n", stderr)
    exit(1)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let cyan = NSColor(calibratedRed: 0.12, green: 0.82, blue: 0.94, alpha: 1)

func drawIcon() {
    let panel = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880),
                             xRadius: 180, yRadius: 180)
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.23, alpha: 1),
               ending: NSColor(calibratedWhite: 0.04, alpha: 1))!
        .draw(in: panel, angle: -90)
    NSColor(calibratedWhite: 0.32, alpha: 1).setStroke()
    panel.lineWidth = 4
    panel.stroke()

    cyan.setFill()
    NSBezierPath(ovalIn: NSRect(x: 490, y: 870, width: 44, height: 44)).fill()

    for index in 0..<11 {
        let y = 210 + CGFloat(index) * 60
        let length: CGFloat = index.isMultiple(of: 5) ? 88 : 48
        NSColor(calibratedWhite: 0.52, alpha: 1).setStroke()
        let ticks = NSBezierPath()
        ticks.lineWidth = 8
        ticks.lineCapStyle = .round
        ticks.move(to: NSPoint(x: 410 - length, y: y))
        ticks.line(to: NSPoint(x: 410, y: y))
        ticks.move(to: NSPoint(x: 614, y: y))
        ticks.line(to: NSPoint(x: 614 + length, y: y))
        ticks.stroke()
    }

    NSColor(calibratedWhite: 0.025, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 484, y: 180, width: 56, height: 664),
                 xRadius: 28, yRadius: 28).fill()
    cyan.setFill()
    NSBezierPath(roundedRect: NSRect(x: 502, y: 198, width: 20, height: 374),
                 xRadius: 10, yRadius: 10).fill()

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    let cap = NSBezierPath(roundedRect: NSRect(x: 322, y: 478, width: 380, height: 188),
                           xRadius: 28, yRadius: 28)
    NSGradient(starting: NSColor(calibratedWhite: 0.94, alpha: 1),
               ending: NSColor(calibratedWhite: 0.48, alpha: 1))!
        .draw(in: cap, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSColor(calibratedWhite: 0.98, alpha: 1).setStroke()
    cap.lineWidth = 3
    cap.stroke()
    NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 342, y: 554, width: 340, height: 36),
                 xRadius: 8, yRadius: 8).fill()
    cyan.setFill()
    NSBezierPath(roundedRect: NSRect(x: 352, y: 564, width: 320, height: 16),
                 xRadius: 5, yRadius: 5).fill()
    NSColor(calibratedWhite: 0.28, alpha: 1).setFill()
    for y in [CGFloat(510), CGFloat(626)] {
        NSBezierPath(roundedRect: NSRect(x: 372, y: y, width: 280, height: 6),
                     xRadius: 3, yRadius: 3).fill()
    }
}

do {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw NSError(domain: "ES9MixerIcon", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Cannot create icon bitmap."])
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
            drawIcon()
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "ES9MixerIcon", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Cannot encode icon PNG."])
            }
            let suffix = scale == 2 ? "@2x" : ""
            try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        }
    }
} catch {
    fputs("Icon generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
