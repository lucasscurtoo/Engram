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
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [color(0x6D6AF0), color(0x3B3899)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: []
    )
    ctx.restoreGState()

    // Back card: tilted, dimmed.
    let cardW = plate.width * 0.58
    let cardH = plate.height * 0.42
    let cardRadius = cardW * 0.10
    ctx.saveGState()
    ctx.translateBy(x: plate.midX - cardW * 0.06, y: plate.midY + cardH * 0.16)
    ctx.rotate(by: 7 * .pi / 180)
    roundedRect(
        ctx, CGRect(x: -cardW / 2, y: -cardH / 2, width: cardW, height: cardH),
        radius: cardRadius, fill: color(0xFFFFFF, alpha: 0.45)
    )
    ctx.restoreGState()

    // Front card: white, with two "text" bars.
    let front = CGRect(
        x: plate.midX - cardW / 2 - cardW * 0.05,
        y: plate.midY - cardH * 0.62,
        width: cardW, height: cardH
    )
    roundedRect(ctx, front, radius: cardRadius, fill: color(0xFFFFFF))
    let barH = cardH * 0.11
    roundedRect(
        ctx,
        CGRect(x: front.minX + cardW * 0.12, y: front.midY + barH * 0.8, width: cardW * 0.56, height: barH),
        radius: barH / 2, fill: color(0x3B3899, alpha: 0.85)
    )
    roundedRect(
        ctx,
        CGRect(x: front.minX + cardW * 0.12, y: front.midY - barH * 1.6, width: cardW * 0.40, height: barH),
        radius: barH / 2, fill: color(0x6D6AF0, alpha: 0.55)
    )

    // Timer ring, bottom-right: a bright arc at 3/4 progress — the focus half of the app.
    let ringCenter = CGPoint(x: plate.maxX - plate.width * 0.235, y: plate.minY + plate.height * 0.245)
    let ringRadius = plate.width * 0.115
    let ringWidth = ringRadius * 0.42
    ctx.setLineWidth(ringWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(0xFFFFFF, alpha: 0.30))
    ctx.addArc(center: ringCenter, radius: ringRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()
    ctx.setStrokeColor(color(0xFFB340))
    ctx.addArc(
        center: ringCenter, radius: ringRadius,
        startAngle: .pi / 2, endAngle: .pi / 2 - 1.5 * .pi, clockwise: true
    )
    ctx.strokePath()

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
