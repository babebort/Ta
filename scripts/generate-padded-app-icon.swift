import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift generate-padded-app-icon.swift INPUT.png OUTPUT.icns\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("Unable to read input image.\n", stderr)
    exit(3)
}

let iconSizes = [16, 32, 64, 128, 256, 512, 1024]
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.icns.identifier as CFString,
    iconSizes.count,
    nil
) else {
    fputs("Unable to create ICNS destination.\n", stderr)
    exit(4)
}

for size in iconSizes {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fputs("Unable to create icon canvas.\n", stderr)
        exit(5)
    }

    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.interpolationQuality = .high

    // Keep the selected seal artwork pixel-for-pixel, but give the macOS icon
    // enough transparent breathing room to match neighboring Dock icons.
    let contentScale = 0.82
    let contentSize = CGFloat(size) * contentScale
    let inset = (CGFloat(size) - contentSize) / 2
    context.draw(
        sourceImage,
        in: CGRect(x: inset, y: inset, width: contentSize, height: contentSize)
    )

    guard let iconImage = context.makeImage() else {
        fputs("Unable to render icon size \(size).\n", stderr)
        exit(6)
    }
    CGImageDestinationAddImage(destination, iconImage, nil)
}

guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to finalize ICNS file.\n", stderr)
    exit(7)
}
