// Generates Assets.xcassets/AppIcon.appiconset (PNGs + Contents.json).
// Run: swift Scripts/generate_app_icon.swift
// Pure CoreGraphics/ImageIO — geometric shapes only, no external assets.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDir = URL(fileURLWithPath: "Sources/Presentation/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func roundedRect(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, fill: CGColor) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
}

// Minimal, dark: near-black squircle, one thin light ring, one indigo dot.
// The dot is the engram (the memory trace); the ring is the app's progress ring.
func drawIcon(px: Int) -> CGImage {
    let s = CGFloat(px)
    let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // macOS-style squircle with the standard transparent margin.
    let inset = s * 0.098
    let plate = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let plateRadius = plate.width * 0.2237

    ctx.saveGState()
    ctx.addPath(CGPath(
        roundedRect: plate, cornerWidth: plateRadius, cornerHeight: plateRadius, transform: nil
    ))
    ctx.clip()
    // Barely-there vertical gradient so the black reads as a surface, not a hole.
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [color(0x1A1A1F), color(0x0C0C0F)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.midX, y: plate.maxY),
        end: CGPoint(x: plate.midX, y: plate.minY),
        options: []
    )
    ctx.restoreGState()

    // Open book, thin white line art, with an indigo bookmark ribbon.
    let pw = plate.width
    let cx = plate.midX
    let cy = plate.midY - pw * 0.01
    let w = pw * 0.60          // full open width
    let h = pw * 0.34          // page height at the outer edges
    let sag = pw * 0.055       // how far the spine dips below the outer edges
    let y0 = cy - h / 2        // outer bottom
    let y1 = cy + h / 2        // outer top
    let stroke = max(1, pw * 0.032)

    let book = CGMutablePath()
    for side: CGFloat in [-1, 1] {
        let outerX = cx + side * w / 2
        let controlX = cx + side * w * 0.24
        // Top edge: spine (lower) sweeping up and out to the page corner.
        book.move(to: CGPoint(x: cx, y: y1 - sag))
        book.addQuadCurve(
            to: CGPoint(x: outerX, y: y1),
            control: CGPoint(x: controlX, y: y1)
        )
        // Outer page edge.
        book.addLine(to: CGPoint(x: outerX, y: y0))
        // Bottom edge back into the spine.
        book.addQuadCurve(
            to: CGPoint(x: cx, y: y0 - sag),
            control: CGPoint(x: controlX, y: y0)
        )
    }
    // Spine.
    book.move(to: CGPoint(x: cx, y: y1 - sag))
    book.addLine(to: CGPoint(x: cx, y: y0 - sag))

    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(color(0xECECF1, alpha: 0.94))
    ctx.addPath(book)
    ctx.strokePath()

    // Indigo bookmark ribbon over the right page, hanging past the top edge.
    let ribbonW = pw * 0.075
    let ribbonX = cx + w * 0.21 - ribbonW / 2
    let ribbonTop = y1 + pw * 0.065
    let ribbonBottom = y1 - pw * 0.10
    let ribbon = CGMutablePath()
    ribbon.move(to: CGPoint(x: ribbonX, y: ribbonTop))
    ribbon.addLine(to: CGPoint(x: ribbonX + ribbonW, y: ribbonTop))
    ribbon.addLine(to: CGPoint(x: ribbonX + ribbonW, y: ribbonBottom))
    ribbon.addLine(to: CGPoint(x: ribbonX + ribbonW / 2, y: ribbonBottom + ribbonW * 0.55))
    ribbon.addLine(to: CGPoint(x: ribbonX, y: ribbonBottom))
    ribbon.closeSubpath()
    ctx.setFillColor(color(0x847DFF))
    ctx.addPath(ribbon)
    ctx.fillPath()

    return ctx.makeImage()!
}

let variants: [(base: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

var images: [[String: String]] = []
for (base, scale) in variants {
    let filename = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
    let url = outputDir.appendingPathComponent(filename)
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, drawIcon(px: base * scale), nil)
    CGImageDestinationFinalize(destination)
    images.append([
        "filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(base)x\(base)",
    ])
}

let contents: [String: Any] = [
    "images": images,
    "info": ["author": "xcode", "version": 1],
]
let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try data.write(to: outputDir.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icons to \(outputDir.path)")
