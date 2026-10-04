// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    // macOS icon grid: 824pt rounded square centered in 1024.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(calibratedRed: 0.17, green: 0.08, blue: 0.30, alpha: 1),
                        NSColor(calibratedRed: 0.05, green: 0.04, blue: 0.08, alpha: 1)])!
        .draw(in: squircle, angle: -90)
    squircle.addClip()

    // The notch hanging from the top edge.
    let notchWidth = 420 * s, notchHeight = 150 * s, r = 60 * s
    let top = body.maxY
    let left = body.midX - notchWidth / 2
    let notch = NSBezierPath()
    notch.move(to: NSPoint(x: left - 30 * s, y: top))
    notch.curve(to: NSPoint(x: left, y: top - 30 * s), controlPoint1: NSPoint(x: left, y: top), controlPoint2: NSPoint(x: left, y: top))
    notch.line(to: NSPoint(x: left, y: top - notchHeight + r))
    notch.curve(to: NSPoint(x: left + r, y: top - notchHeight), controlPoint1: NSPoint(x: left, y: top - notchHeight), controlPoint2: NSPoint(x: left, y: top - notchHeight))
    notch.line(to: NSPoint(x: left + notchWidth - r, y: top - notchHeight))
    notch.curve(to: NSPoint(x: left + notchWidth, y: top - notchHeight + r), controlPoint1: NSPoint(x: left + notchWidth, y: top - notchHeight), controlPoint2: NSPoint(x: left + notchWidth, y: top - notchHeight))
    notch.line(to: NSPoint(x: left + notchWidth, y: top - 30 * s))
    notch.curve(to: NSPoint(x: left + notchWidth + 30 * s, y: top), controlPoint1: NSPoint(x: left + notchWidth, y: top), controlPoint2: NSPoint(x: left + notchWidth, y: top))
    notch.close()
    NSColor.black.setFill()
    notch.fill()

    // The eyebrow: a thick arc under the notch in the accent gradient.
    let brow = NSBezierPath()
    brow.move(to: NSPoint(x: body.midX - 230 * s, y: body.midY + 30 * s))
    brow.curve(to: NSPoint(x: body.midX + 250 * s, y: body.midY + 55 * s),
               controlPoint1: NSPoint(x: body.midX - 80 * s, y: body.midY + 120 * s),
               controlPoint2: NSPoint(x: body.midX + 140 * s, y: body.midY + 125 * s))
    brow.lineWidth = 74 * s
    brow.lineCapStyle = .round
    let strokePath = NSBezierPath()
    strokePath.append(brow)
    NSGraphicsContext.saveGraphicsState()
    let cg = NSGraphicsContext.current!.cgContext
    cg.setLineWidth(74 * s)
    cg.setLineCap(.round)
    cg.addPath(brow.cgPath)
    cg.replacePathWithStrokedPath()
    cg.clip()
    NSGradient(colors: [NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.56, alpha: 1),
                        NSColor(calibratedRed: 0.78, green: 0.42, blue: 0.98, alpha: 1)])!
        .draw(in: body, angle: 0)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
try render(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/images/icon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Resources/AppIcon.icns" : "iconutil failed")
