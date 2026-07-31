#!/usr/bin/env swift
// Renders the NotchPrompter app icon set into Assets.xcassets/AppIcon.appiconset.
// Run: swift Tools/make-icon.swift
//
// The tile is the display. The notch bites into its top edge and a script sits
// underneath, mid-scroll. One line is amber — the same colour the app paints the
// line you are currently speaking.

import AppKit
import CoreGraphics
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("NotchPrompter/Assets.xcassets/AppIcon.appiconset")

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Apple's continuous corner. A plain rounded rect meets its edges at a tangent
/// and reads visibly sharper; a superellipse bows the straight edges outward.
/// This is the real decomposition — straight edges, curvature easing into them.
func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2 / 1.52866483)
    let path = CGMutablePath()

    // Three curves per corner: ease out of the straight edge, sweep the corner,
    // ease into the next edge. The shape is symmetric top-to-bottom, so it draws
    // the same whether the context's y axis points up or down.
    let A: CGFloat = 1.52866483, B: CGFloat = 1.08849323, C: CGFloat = 0.86840689
    let D: CGFloat = 0.63149379, E: CGFloat = 0.37282992, F: CGFloat = 0.16905955
    let G: CGFloat = 0.07491139

    let l = rect.minX, t = rect.minY, rt = rect.maxX, b = rect.maxY
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    path.move(to: p(l + A * r, t))
    path.addLine(to: p(rt - A * r, t))
    path.addCurve(to: p(rt - D * r, t + G * r), control1: p(rt - B * r, t), control2: p(rt - C * r, t))
    path.addCurve(to: p(rt - G * r, t + D * r), control1: p(rt - E * r, t + F * r), control2: p(rt - F * r, t + E * r))
    path.addCurve(to: p(rt, t + A * r), control1: p(rt, t + C * r), control2: p(rt, t + B * r))

    path.addLine(to: p(rt, b - A * r))
    path.addCurve(to: p(rt - G * r, b - D * r), control1: p(rt, b - B * r), control2: p(rt, b - C * r))
    path.addCurve(to: p(rt - D * r, b - G * r), control1: p(rt - F * r, b - E * r), control2: p(rt - E * r, b - F * r))
    path.addCurve(to: p(rt - A * r, b), control1: p(rt - C * r, b), control2: p(rt - B * r, b))

    path.addLine(to: p(l + A * r, b))
    path.addCurve(to: p(l + D * r, b - G * r), control1: p(l + B * r, b), control2: p(l + C * r, b))
    path.addCurve(to: p(l + G * r, b - D * r), control1: p(l + E * r, b - F * r), control2: p(l + F * r, b - E * r))
    path.addCurve(to: p(l, b - A * r), control1: p(l, b - C * r), control2: p(l, b - B * r))

    path.addLine(to: p(l, t + A * r))
    path.addCurve(to: p(l + G * r, t + D * r), control1: p(l, t + B * r), control2: p(l, t + C * r))
    path.addCurve(to: p(l + D * r, t + G * r), control1: p(l + F * r, t + E * r), control2: p(l + E * r, t + F * r))
    path.addCurve(to: p(l + A * r, t), control1: p(l + C * r, t), control2: p(l + B * r, t))

    path.closeSubpath()
    return path
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func linearGradient(_ context: CGContext, _ stops: [(UInt32, CGFloat)], from: CGPoint, to: CGPoint) {
    let colors = stops.map { color($0.0, $0.1) } as CFArray
    guard let gradient = CGGradient(colorsSpace: srgb, colors: colors, locations: nil) else { return }
    context.drawLinearGradient(gradient, start: from, end: to, options: [])
}

func drawIcon(size: Int) -> Data? {
    let canvas = CGFloat(size)
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    // Apple's macOS grid: an 824pt body inside a 1024pt canvas, corner radius 185.4.
    let margin = canvas * (100.0 / 1024.0)
    let tile = CGRect(
        x: margin,
        y: margin * 1.2,
        width: canvas - margin * 2,
        height: canvas - margin * 2
    )
    let cornerRadius = tile.width * (185.4 / 824.0)
    let body = squircle(tile, radius: cornerRadius)
    let detailed = size >= 64

    // Contact shadow.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -canvas * 0.014),
        blur: canvas * 0.032,
        color: color(0x000000, 0.45)
    )
    context.addPath(body)
    context.setFillColor(color(0x101013))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(body)
    context.clip()

    // Graphite body, dark enough that a pure-black notch still reads against it.
    linearGradient(
        context,
        [(0x46464E, 1), (0x2C2C33, 1), (0x151519, 1)],
        from: CGPoint(x: tile.midX, y: tile.maxY),
        to: CGPoint(x: tile.midX, y: tile.minY)
    )

    // Light pooling at the top edge.
    if let sheen = CGGradient(
        colorsSpace: srgb,
        colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    ) {
        context.drawRadialGradient(
            sheen,
            startCenter: CGPoint(x: tile.midX, y: tile.maxY + tile.height * 0.05),
            startRadius: 0,
            endCenter: CGPoint(x: tile.midX, y: tile.maxY + tile.height * 0.05),
            endRadius: tile.width * 0.78,
            options: []
        )
    }

    // The notch, hanging off the top edge.
    let notchWidth = tile.width * 0.44
    let notchHeight = tile.height * 0.125
    let notch = CGRect(
        x: tile.midX - notchWidth / 2,
        y: tile.maxY - notchHeight,
        width: notchWidth,
        height: notchHeight * 2
    )
    context.setFillColor(color(0x000000))
    context.addPath(rounded(notch, notchHeight * 0.68))
    context.fillPath()

    // Camera indicator, the way it sits on a real notch.
    if detailed {
        let dot = notchHeight * 0.26
        context.setFillColor(color(0x30D158))
        context.fillEllipse(in: CGRect(
            x: notch.midX + notchWidth * 0.26,
            y: tile.maxY - notchHeight * 0.55 - dot / 2,
            width: dot,
            height: dot
        ))
    }

    // Script lines. Widths are uneven so it reads as prose, not a list.
    let widths: [CGFloat] = detailed ? [0.97, 0.61, 1.0, 0.74, 0.43] : [0.97, 0.61, 0.85]
    let alphas: [CGFloat] = detailed ? [1.0, 1.0, 0.80, 0.55, 0.32] : [1.0, 1.0, 0.6]
    let accentIndex = 1

    let leftEdge = tile.minX + tile.width * 0.145
    let usable = tile.width * 0.715
    let barHeight = detailed ? tile.height * 0.083 : tile.height * 0.105
    let gap = detailed ? tile.height * 0.055 : tile.height * 0.075
    var y = tile.maxY - notchHeight - tile.height * 0.10 - barHeight

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -canvas * 0.0025),
        blur: canvas * 0.010,
        color: color(0x000000, 0.55)
    )
    for (index, factor) in widths.enumerated() {
        guard y > tile.minY + tile.height * 0.07 else { break }
        let bar = CGRect(x: leftEdge, y: y, width: usable * factor, height: barHeight)
        context.setFillColor(index == accentIndex ? color(0xFFD60A) : color(0xF4F4F7, alphas[index]))
        context.addPath(rounded(bar, barHeight / 2))
        context.fillPath()
        y -= barHeight + gap
    }
    context.restoreGState()

    // Vignette so the lower half settles back.
    if let vignette = CGGradient(
        colorsSpace: srgb,
        colors: [color(0x000000, 0), color(0x000000, 0.28)] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            vignette,
            start: CGPoint(x: tile.midX, y: tile.midY),
            end: CGPoint(x: tile.midX, y: tile.minY),
            options: []
        )
    }
    context.restoreGState()

    // Rim: catches light along the top, falls into shadow at the bottom.
    context.saveGState()
    context.addPath(body)
    context.clip()
    context.setLineWidth(max(1, canvas * 0.006))
    context.addPath(squircle(tile.insetBy(dx: canvas * 0.0025, dy: canvas * 0.0025), radius: cornerRadius))
    context.replacePathWithStrokedPath()
    context.clip()
    linearGradient(
        context,
        [(0xFFFFFF, 0.40), (0xFFFFFF, 0.05), (0x000000, 0.22)],
        from: CGPoint(x: tile.midX, y: tile.maxY),
        to: CGPoint(x: tile.midX, y: tile.minY)
    )
    context.restoreGState()

    guard let image = context.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: canvas, height: canvas)
    return rep.representation(using: .png, properties: [:])
}

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for size in sizes {
    guard let data = drawIcon(size: size) else {
        print("failed to render \(size)")
        exit(1)
    }
    let url = outputDirectory.appendingPathComponent("icon_\(size).png")
    try data.write(to: url)
    print("wrote \(url.lastPathComponent)")
}
