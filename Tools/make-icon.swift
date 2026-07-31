#!/usr/bin/env swift
// Renders the NotchPrompter app icon set into Assets.xcassets/AppIcon.appiconset.
// Run: swift Tools/make-icon.swift

import AppKit
import CoreGraphics
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("NotchPrompter/Assets.xcassets/AppIcon.appiconset")

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(size: Int) -> Data? {
    let dimension = CGFloat(size)
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    // macOS icons leave a margin around the tile.
    let inset = dimension * 0.085
    let tile = CGRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
    let corner = tile.width * 0.225

    // Body: near-black with a soft top-down sheen.
    context.saveGState()
    context.addPath(roundedPath(tile, radius: corner))
    context.clip()

    let colors = [
        CGColor(srgbRed: 0.22, green: 0.22, blue: 0.24, alpha: 1),
        CGColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1)
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: tile.midX, y: tile.maxY),
            end: CGPoint(x: tile.midX, y: tile.minY),
            options: []
        )
    }

    // The notch: a pill hanging off the top edge.
    let notchWidth = tile.width * 0.40
    let notchHeight = tile.height * 0.115
    let notch = CGRect(
        x: tile.midX - notchWidth / 2,
        y: tile.maxY - notchHeight,
        width: notchWidth,
        height: notchHeight * 2
    )
    context.setFillColor(CGColor(srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1))
    context.addPath(roundedPath(notch, radius: notchHeight * 0.65))
    context.fillPath()

    // Script lines, mimicking a page of text mid-scroll.
    let leftEdge = tile.minX + tile.width * 0.135
    let usableWidth = tile.width * 0.73
    let barHeight = tile.height * 0.082
    let gap = tile.height * 0.048
    let widths: [CGFloat] = [1.0, 0.72, 0.88, 0.55, 0.95, 0.40]
    var y = tile.maxY - notchHeight - tile.height * 0.135 - barHeight

    for (index, factor) in widths.enumerated() {
        guard y > tile.minY + tile.height * 0.06 else { break }
        let bar = CGRect(x: leftEdge, y: y, width: usableWidth * factor, height: barHeight)
        let brightness = 1.0 - Double(index) * 0.11
        context.setFillColor(CGColor(srgbRed: brightness, green: brightness, blue: brightness, alpha: 1))
        context.addPath(roundedPath(bar, radius: barHeight / 2))
        context.fillPath()

        // Second short bar on the last row, like a wrapped final line.
        if index == widths.count - 1 {
            let trailing = CGRect(
                x: leftEdge + usableWidth * factor + gap,
                y: y,
                width: usableWidth * 0.30,
                height: barHeight
            )
            context.addPath(roundedPath(trailing, radius: barHeight / 2))
            context.fillPath()
        }

        y -= barHeight + gap
    }

    context.restoreGState()

    // Recording dot tucked beside the notch.
    let dotSize = tile.width * 0.055
    let dot = CGRect(
        x: tile.midX + notchWidth / 2 + tile.width * 0.035,
        y: tile.maxY - notchHeight * 0.62 - dotSize / 2,
        width: dotSize,
        height: dotSize
    )
    if size >= 64 {
        context.setFillColor(CGColor(srgbRed: 0.26, green: 0.84, blue: 0.40, alpha: 1))
        context.fillEllipse(in: dot)
    }

    // Hairline highlight around the tile edge.
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
    context.setLineWidth(max(1, dimension * 0.004))
    context.addPath(roundedPath(tile.insetBy(dx: 0.5, dy: 0.5), radius: corner))
    context.strokePath()

    guard let image = context.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: dimension, height: dimension)
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
