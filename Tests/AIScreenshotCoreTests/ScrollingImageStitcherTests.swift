import AppKit
import CoreGraphics
import XCTest
@testable import AIScreenshotCore

final class ScrollingImageStitcherTests: XCTestCase {
    func testSingleFrameOutputKeepsVisualTopAtTop() throws {
        let image = try makeDirectionalImage(width: 80, height: 120, splitY: 60)
        let stitcher = ScrollingImageStitcher(sampleWidth: 40)
        _ = try stitcher.append(image)

        let output = try stitcher.makeImage()

        assertRed(try pixel(in: output, x: 10, yFromTop: 10))
        assertBlue(try pixel(in: output, x: 10, yFromTop: 110))
    }

    func testDownwardStitchedOutputKeepsDocumentTopAtTop() throws {
        let first = try makeDirectionalImage(width: 120, height: 140, splitY: 110, offsetY: 0)
        let second = try makeDirectionalImage(width: 120, height: 140, splitY: 110, offsetY: 70)
        let stitcher = ScrollingImageStitcher(sampleWidth: 60)
        _ = try stitcher.append(first)
        let disposition = try stitcher.append(second)
        guard case .appended = disposition else {
            return XCTFail("Expected a stitched frame, got \(disposition)")
        }
        XCTAssertEqual(stitcher.segments.last?.direction, .down)

        let output = try stitcher.makeImage()

        assertRed(try pixel(in: output, x: 10, yFromTop: 10))
        assertBlue(try pixel(in: output, x: 10, yFromTop: output.height - 10))
    }

    func testSegmentedPreviewPartsKeepTopToBottomOrder() throws {
        let stitcher = ScrollingImageStitcher(sampleWidth: 60)
        for offset in [0, 70, 140] {
            _ = try stitcher.append(
                makeDirectionalImage(width: 120, height: 140, splitY: 110, offsetY: offset)
            )
        }

        let parts = try stitcher.makeImages(maximumPixelHeight: 100)

        XCTAssertGreaterThan(parts.count, 1)
        assertRed(try pixel(in: try XCTUnwrap(parts.first), x: 10, yFromTop: 10))
        let last = try XCTUnwrap(parts.last)
        assertBlue(try pixel(in: last, x: 10, yFromTop: last.height - 10))
    }

    func testStitcherAddsOnlyNewScrolledPixels() throws {
        let source = try makeStripedImage(width: 240, height: 600)
        let first = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 240, height: 300)))
        let second = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 80, width: 240, height: 300)))
        let stitcher = ScrollingImageStitcher(sampleWidth: 80)

        XCTAssertEqual(try stitcher.append(first), .firstFrame)
        let outcome = try stitcher.append(second)
        guard case .appended(let newPixelHeight, _) = outcome else {
            return XCTFail("Expected appended frame, got \(outcome)")
        }
        XCTAssertEqual(newPixelHeight, 80, accuracy: 5)

        let output = try stitcher.makeImage()
        XCTAssertEqual(output.width, 240)
        XCTAssertEqual(output.height, 380, accuracy: 5)
    }

    func testStitcherIgnoresDuplicateImage() throws {
        let image = try makeStripedImage(width: 200, height: 260)
        let stitcher = ScrollingImageStitcher(sampleWidth: 72)
        _ = try stitcher.append(image)

        XCTAssertEqual(try stitcher.append(image), .duplicate)
        XCTAssertEqual(try stitcher.makeImage().height, 260)
    }

    func testStitcherPrependsUpwardScrollPixels() throws {
        let source = try makeStripedImage(width: 220, height: 520)
        let first = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 120, width: 220, height: 260)))
        let upward = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 75, width: 220, height: 260)))
        let stitcher = ScrollingImageStitcher(sampleWidth: 80)
        _ = try stitcher.append(first)

        let outcome = try stitcher.append(upward)
        guard case .appended(let newPixelHeight, _) = outcome else {
            return XCTFail("Expected appended frame, got \(outcome)")
        }
        XCTAssertEqual(newPixelHeight, 45, accuracy: 5)
        XCTAssertEqual(stitcher.segments.last?.direction, .up)
        XCTAssertEqual(try stitcher.makeImage().height, 305, accuracy: 5)
    }

    func testStitcherSplitsUltraLongOutputIntoBoundedParts() throws {
        let source = try makeStripedImage(width: 200, height: 760)
        let stitcher = ScrollingImageStitcher(sampleWidth: 80)
        for y in stride(from: 0, through: 360, by: 90) {
            let frame = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: y, width: 200, height: 280)))
            _ = try stitcher.append(frame)
        }

        let parts = try stitcher.makeImages(maximumPixelHeight: 240)

        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertTrue(parts.allSatisfy { $0.height <= 240 })
        XCTAssertEqual(parts.reduce(0) { $0 + $1.height }, stitcher.outputPixelHeight)
    }

    func testManualSeamAdjustmentChangesOutputHeight() throws {
        let source = try makeStripedImage(width: 200, height: 520)
        let first = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 200, height: 260)))
        let second = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 70, width: 200, height: 260)))
        let stitcher = ScrollingImageStitcher(sampleWidth: 80)
        _ = try stitcher.append(first)
        _ = try stitcher.append(second)
        let segment = try XCTUnwrap(stitcher.segments.first)
        let originalHeight = stitcher.outputPixelHeight

        XCTAssertTrue(stitcher.adjustSegment(id: segment.id, pixelDelta: -5))
        XCTAssertEqual(stitcher.outputPixelHeight, originalHeight - 5)
        XCTAssertEqual(try stitcher.makeImage().height, originalHeight - 5)
    }

    private func makeStripedImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8((y + (x / 16) * 13 + (y / 17) * 31) % 256)
                pixels[offset + 1] = UInt8((y * 2 + (x / 24) * 29 + (y / 23) * 17) % 256)
                pixels[offset + 2] = UInt8((y * 3 + (x / 12) * 7 + (y / 31) * 43) % 256)
                pixels[offset + 3] = 255
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                    .union(.byteOrder32Big),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw StitcherTestError.couldNotCreateImage
        }
        return image
    }

    private func makeDirectionalImage(
        width: Int,
        height: Int,
        splitY: Int,
        offsetY: Int = 0
    ) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let globalY = y + offsetY
                let isTop = globalY < splitY
                let texture = UInt8((globalY * 17 + x * 13 + (globalY / 5) * 29) % 36)
                pixels[offset] = isTop ? 210 + texture : 20 + texture
                pixels[offset + 1] = 35 + texture
                pixels[offset + 2] = isTop ? 20 + texture : 210 + texture
                pixels[offset + 3] = 255
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                    .union(.byteOrder32Big),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw StitcherTestError.couldNotCreateImage
        }
        return image
    }

    private func pixel(in image: CGImage, x: Int, yFromTop: Int) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        // Encode and decode through the same AppKit path used by preview/save so
        // the assertion validates visual orientation instead of CGContext space.
        let encoded = try XCTUnwrap(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        )
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: encoded))
        let color = try XCTUnwrap(
            decoded.colorAt(x: x, y: yFromTop)?.usingColorSpace(.deviceRGB)
        )
        return (
            UInt8((color.redComponent * 255).rounded()),
            UInt8((color.greenComponent * 255).rounded()),
            UInt8((color.blueComponent * 255).rounded())
        )
    }

    private func assertRed(
        _ pixel: (red: UInt8, green: UInt8, blue: UInt8),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(pixel.red, pixel.blue, file: file, line: line)
    }

    private func assertBlue(
        _ pixel: (red: UInt8, green: UInt8, blue: UInt8),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(pixel.blue, pixel.red, file: file, line: line)
    }
}

private enum StitcherTestError: Error {
    case couldNotCreateImage
}
