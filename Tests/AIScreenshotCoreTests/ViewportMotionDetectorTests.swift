import CoreGraphics
import XCTest
@testable import AIScreenshotCore

final class ViewportMotionDetectorTests: XCTestCase {
    func testIdenticalViewportIsStationary() throws {
        let image = try makeImage(width: 180, height: 240, contentOffset: 0)
        let detector = ViewportMotionDetector()
        try detector.commit(image)

        let measurement = try detector.compare(image)

        XCTAssertTrue(measurement.hasReference)
        XCTAssertTrue(measurement.isStationary)
    }

    func testScrolledCentralContentIsMovement() throws {
        let detector = ViewportMotionDetector()
        try detector.commit(makeImage(width: 180, height: 240, contentOffset: 0))

        let measurement = try detector.compare(
            makeImage(width: 180, height: 240, contentOffset: 52)
        )

        XCTAssertFalse(measurement.isStationary)
        XCTAssertGreaterThan(measurement.changedPixelFraction, 0.1)
    }

    func testChangingFixedHeaderAndComposerDoesNotCountAsScroll() throws {
        let detector = ViewportMotionDetector()
        try detector.commit(makeImage(width: 180, height: 240, contentOffset: 0, edgeVariant: 0))

        let measurement = try detector.compare(
            makeImage(width: 180, height: 240, contentOffset: 0, edgeVariant: 80)
        )

        XCTAssertTrue(measurement.isStationary)
    }

    private func makeImage(
        width: Int,
        height: Int,
        contentOffset: Int,
        edgeVariant: Int = 0
    ) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let isFixedEdge = y < 28 || y >= height - 28
                let sourceY = isFixedEdge ? y + edgeVariant : y + contentOffset
                pixels[offset] = UInt8((sourceY * 17 + x * 11) % 256)
                pixels[offset + 1] = UInt8((sourceY * 7 + x * 19) % 256)
                pixels[offset + 2] = UInt8((sourceY * 23 + x * 3) % 256)
                pixels[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
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
            throw MotionDetectorTestError.couldNotCreateImage
        }
        return image
    }
}

private enum MotionDetectorTestError: Error {
    case couldNotCreateImage
}
