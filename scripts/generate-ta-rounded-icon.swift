#!/usr/bin/env swift

import AppKit
import Foundation

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = projectRoot.appendingPathComponent("Resources/Brand/Ta-AppIcon-selected-original.png")
let outputURL = projectRoot.appendingPathComponent("Resources/Brand/Ta-AppIcon.png")

guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("Unable to load \(sourceURL.path)\n", stderr)
    exit(1)
}

let canvasSize = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create icon bitmap\n", stderr)
    exit(1)
}

bitmap.size = canvasSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

NSColor.clear.setFill()
NSRect(origin: .zero, size: canvasSize).fill()

// Preserve the complete rice-paper artwork and remove only the outer white
// canvas corners with a macOS-style rounded silhouette.
let clipPath = NSBezierPath(
    roundedRect: NSRect(origin: .zero, size: canvasSize),
    xRadius: 228,
    yRadius: 228
)
clipPath.addClip()

NSGraphicsContext.current?.imageInterpolation = .high
source.draw(
    in: NSRect(origin: .zero, size: canvasSize),
    from: NSRect(origin: .zero, size: source.size),
    operation: .copy,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to render rounded icon\n", stderr)
    exit(1)
}

try png.write(to: outputURL, options: .atomic)
print(outputURL.path)
