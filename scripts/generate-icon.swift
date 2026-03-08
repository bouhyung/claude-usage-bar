#!/usr/bin/env swift

import AppKit
import CoreGraphics

func generateIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let s = CGFloat(size)

    // Background: rounded rect with dark gradient
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.04, dy: s * 0.04),
                            xRadius: s * 0.22, yRadius: s * 0.22)

    let gradient = NSGradient(colors: [
        NSColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0),
        NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1.0),
    ])!
    gradient.draw(in: path, angle: -90)

    // Circular gauge track (gray)
    let center = NSPoint(x: s * 0.5, y: s * 0.52)
    let radius = s * 0.30
    let trackWidth = s * 0.06
    let trackPath = NSBezierPath()
    trackPath.appendArc(withCenter: center, radius: radius,
                        startAngle: -225, endAngle: 45, clockwise: true)
    trackPath.lineWidth = trackWidth
    trackPath.lineCapStyle = .round
    NSColor(white: 0.3, alpha: 1.0).setStroke()
    trackPath.stroke()

    // Gauge fill (green to orange gradient effect - draw as green)
    let fillPath = NSBezierPath()
    fillPath.appendArc(withCenter: center, radius: radius,
                       startAngle: -225, endAngle: -225 + 270 * 0.65, clockwise: false)
    fillPath.lineWidth = trackWidth
    fillPath.lineCapStyle = .round
    NSColor(red: 0.2, green: 0.85, blue: 0.4, alpha: 1.0).setStroke()
    fillPath.stroke()

    // "C" letter in the center
    let fontSize = s * 0.30
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let str = NSAttributedString(string: "C", attributes: attrs)
    let strSize = str.size()
    let strPoint = NSPoint(x: center.x - strSize.width / 2,
                           y: center.y - strSize.height / 2)
    str.draw(at: strPoint)

    // Small percentage text below
    let smallFont = NSFont.monospacedSystemFont(ofSize: s * 0.10, weight: .medium)
    let smallAttrs: [NSAttributedString.Key: Any] = [
        .font: smallFont,
        .foregroundColor: NSColor(white: 0.6, alpha: 1.0),
    ]
    let pctStr = NSAttributedString(string: "usage", attributes: smallAttrs)
    let pctSize = pctStr.size()
    pctStr.draw(at: NSPoint(x: center.x - pctSize.width / 2, y: s * 0.1))

    img.unlockFocus()
    return img
}

// Generate iconset
let iconsetDir = "/Users/bou/dev/claude-usage-bar/Resources/AppIcon.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetDir)
try! fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for (name, size) in sizes {
    let img = generateIcon(size: size)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(name)")
        continue
    }
    let path = "\(iconsetDir)/\(name).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("Generated \(name) (\(size)x\(size))")
}

print("Done! Run: iconutil -c icns Resources/AppIcon.iconset")
