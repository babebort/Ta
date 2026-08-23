import CoreGraphics
import Foundation

public struct ViewportMotionMeasurement: Equatable, Sendable {
    public let hasReference: Bool
    public let meanAbsoluteDifference: Double
    public let changedPixelFraction: Double
    public let isStationary: Bool

    public init(
        hasReference: Bool,
        meanAbsoluteDifference: Double,
        changedPixelFraction: Double,
        isStationary: Bool
    ) {
        self.hasReference = hasReference
        self.meanAbsoluteDifference = meanAbsoluteDifference
        self.changedPixelFraction = changedPixelFraction
        self.isStationary = isStationary
    }
}

/// Detects whether a scroll gesture actually moved the viewport. This is kept
/// separate from seam matching: a temporarily unmatchable frame is not proof
/// that the page reached the bottom.
public final class ViewportMotionDetector {
    private let sampleWidth: Int
    private let ignoredTopFraction: Double
    private let ignoredBottomFraction: Double
    private let ignoredSideFraction: Double
    private let stationaryMeanDifference: Double
    private let stationaryChangedFraction: Double
    private let changedPixelDifference: Int
    private var reference: GrayscaleFrame?

    public init(
        sampleWidth: Int = 72,
        ignoredTopFraction: Double = 0.12,
        ignoredBottomFraction: Double = 0.12,
        ignoredSideFraction: Double = 0.06,
        stationaryMeanDifference: Double = 2.8,
        stationaryChangedFraction: Double = 0.025,
        changedPixelDifference: Int = 12
    ) {
        self.sampleWidth = max(32, sampleWidth)
        self.ignoredTopFraction = min(0.3, max(0, ignoredTopFraction))
        self.ignoredBottomFraction = min(0.3, max(0, ignoredBottomFraction))
        self.ignoredSideFraction = min(0.2, max(0, ignoredSideFraction))
        self.stationaryMeanDifference = max(0, stationaryMeanDifference)
        self.stationaryChangedFraction = min(1, max(0, stationaryChangedFraction))
        self.changedPixelDifference = max(1, changedPixelDifference)
    }

    public func reset() {
        reference = nil
    }

    public func commit(_ image: CGImage) throws {
        reference = try makeSample(from: image)
    }

    public func compare(_ image: CGImage) throws -> ViewportMotionMeasurement {
        let current = try makeSample(from: image)
        guard let reference,
              reference.width == current.width,
              reference.height == current.height else {
            return ViewportMotionMeasurement(
                hasReference: false,
                meanAbsoluteDifference: 0,
                changedPixelFraction: 0,
                isStationary: false
            )
        }

        let top = min(reference.height - 1, Int(Double(reference.height) * ignoredTopFraction))
        let bottom = max(top + 1, reference.height - Int(Double(reference.height) * ignoredBottomFraction))
        let left = min(reference.width - 1, Int(Double(reference.width) * ignoredSideFraction))
        let right = max(left + 1, reference.width - Int(Double(reference.width) * ignoredSideFraction))

        var totalDifference = 0
        var changedPixels = 0
        var count = 0
        for y in top..<bottom {
            for x in left..<right {
                let difference = abs(Int(reference[x, y]) - Int(current[x, y]))
                totalDifference += difference
                if difference >= changedPixelDifference {
                    changedPixels += 1
                }
                count += 1
            }
        }

        guard count > 0 else {
            return ViewportMotionMeasurement(
                hasReference: true,
                meanAbsoluteDifference: 0,
                changedPixelFraction: 0,
                isStationary: true
            )
        }
        let meanDifference = Double(totalDifference) / Double(count)
        let changedFraction = Double(changedPixels) / Double(count)
        let stationary = meanDifference <= stationaryMeanDifference
            || changedFraction <= stationaryChangedFraction
        return ViewportMotionMeasurement(
            hasReference: true,
            meanAbsoluteDifference: meanDifference,
            changedPixelFraction: changedFraction,
            isStationary: stationary
        )
    }

    private func makeSample(from image: CGImage) throws -> GrayscaleFrame {
        let height = max(24, Int((Double(image.height) * Double(sampleWidth) / Double(image.width)).rounded()))
        var pixels = [UInt8](repeating: 0, count: sampleWidth * height)
        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw ScrollingImageStitcherError.invalidImage
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: height))
        return GrayscaleFrame(width: sampleWidth, height: height, pixels: pixels)
    }
}
