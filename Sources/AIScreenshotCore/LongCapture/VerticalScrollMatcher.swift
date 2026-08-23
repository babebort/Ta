import Foundation

public struct GrayscaleFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0, "Frame dimensions must be positive")
        precondition(pixels.count == width * height, "Pixel count must match dimensions")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }
}

public enum VerticalScrollDirection: String, Equatable, Sendable {
    case stationary
    case down
    case up
}

public struct StableEdgeRegions: Equatable, Sendable {
    public let topRows: Int
    public let bottomRows: Int

    public init(topRows: Int, bottomRows: Int) {
        self.topRows = topRows
        self.bottomRows = bottomRows
    }
}

public struct VerticalScrollMatch: Equatable, Sendable {
    /// Positive means that the viewport moved down; negative means it moved up.
    public let signedShift: Int
    public let meanAbsoluteDifference: Double
    public let confidence: Double

    public init(signedShift: Int, meanAbsoluteDifference: Double, confidence: Double) {
        self.signedShift = signedShift
        self.meanAbsoluteDifference = meanAbsoluteDifference
        self.confidence = confidence
    }

    public init(shift: Int, meanAbsoluteDifference: Double, confidence: Double) {
        self.init(
            signedShift: shift,
            meanAbsoluteDifference: meanAbsoluteDifference,
            confidence: confidence
        )
    }

    public var shift: Int { abs(signedShift) }

    public var direction: VerticalScrollDirection {
        if signedShift > 0 { return .down }
        if signedShift < 0 { return .up }
        return .stationary
    }

    public var isDuplicate: Bool {
        shift <= 1 && meanAbsoluteDifference <= 2.5
    }
}

public struct VerticalScrollMatcher: Sendable {
    public var maximumShiftFraction: Double
    public var ignoredTopFraction: Double
    public var ignoredBottomFraction: Double
    public var maximumMeanAbsoluteDifference: Double
    public var sampleStride: Int

    public init(
        maximumShiftFraction: Double = 0.82,
        ignoredTopFraction: Double = 0.10,
        ignoredBottomFraction: Double = 0.04,
        maximumMeanAbsoluteDifference: Double = 18,
        sampleStride: Int = 2
    ) {
        self.maximumShiftFraction = maximumShiftFraction
        self.ignoredTopFraction = ignoredTopFraction
        self.ignoredBottomFraction = ignoredBottomFraction
        self.maximumMeanAbsoluteDifference = maximumMeanAbsoluteDifference
        self.sampleStride = max(1, sampleStride)
    }

    public func match(previous: GrayscaleFrame, current: GrayscaleFrame) -> VerticalScrollMatch? {
        guard previous.width == current.width,
              previous.height == current.height,
              previous.width >= 8,
              previous.height >= 24 else {
            return nil
        }

        let height = previous.height
        let topMargin = max(1, Int(Double(height) * ignoredTopFraction))
        let bottomMargin = max(1, Int(Double(height) * ignoredBottomFraction))
        let maximumShift = min(height - topMargin - bottomMargin - 12,
                               Int(Double(height) * maximumShiftFraction))
        guard maximumShift >= 0 else { return nil }

        var bestShift = 0
        var bestDifference = Double.greatestFiniteMagnitude
        var secondBestDifference = Double.greatestFiniteMagnitude

        for signedShift in (-maximumShift)...maximumShift {
            let shift = abs(signedShift)
            let startY = topMargin
            let endY = height - shift - bottomMargin
            guard endY - startY >= 12 else { continue }

            var totalDifference = 0
            var sampleCount = 0
            var y = startY
            while y < endY {
                var x = 1
                while x < previous.width - 1 {
                    let previousY = signedShift >= 0 ? y + shift : y
                    let currentY = signedShift >= 0 ? y : y + shift
                    totalDifference += abs(Int(previous[x, previousY]) - Int(current[x, currentY]))
                    sampleCount += 1
                    x += sampleStride
                }
                y += sampleStride
            }

            guard sampleCount > 0 else { continue }
            let difference = Double(totalDifference) / Double(sampleCount)
            if difference < bestDifference {
                secondBestDifference = bestDifference
                bestDifference = difference
                bestShift = signedShift
            } else if difference < secondBestDifference {
                secondBestDifference = difference
            }
        }

        guard bestDifference <= maximumMeanAbsoluteDifference else { return nil }

        let quality = max(0, 1 - bestDifference / maximumMeanAbsoluteDifference)
        let separation: Double
        if secondBestDifference.isFinite, secondBestDifference > 0 {
            separation = min(1, max(0, (secondBestDifference - bestDifference) / secondBestDifference * 6))
        } else {
            separation = 1
        }
        let confidence = min(1, quality * 0.8 + separation * 0.2)
        return VerticalScrollMatch(
            signedShift: bestShift,
            meanAbsoluteDifference: bestDifference,
            confidence: confidence
        )
    }

    /// Finds same-position rows that stayed fixed between frames, such as a
    /// chat title bar or composer. The result is deliberately conservative;
    /// callers should still surface low-confidence seams for review.
    public func stableEdges(
        previous: GrayscaleFrame,
        current: GrayscaleFrame,
        maximumFraction: Double = 0.25,
        maximumRowDifference: Double = 3.0
    ) -> StableEdgeRegions {
        guard previous.width == current.width,
              previous.height == current.height else {
            return StableEdgeRegions(topRows: 0, bottomRows: 0)
        }

        let limit = max(0, min(previous.height / 3, Int(Double(previous.height) * maximumFraction)))
        guard limit > 0 else { return StableEdgeRegions(topRows: 0, bottomRows: 0) }

        func rowDifference(_ row: Int) -> Double {
            var total = 0
            var count = 0
            var x = 0
            while x < previous.width {
                total += abs(Int(previous[x, row]) - Int(current[x, row]))
                count += 1
                x += sampleStride
            }
            return count == 0 ? .greatestFiniteMagnitude : Double(total) / Double(count)
        }

        var top = 0
        while top < limit, rowDifference(top) <= maximumRowDifference { top += 1 }

        var bottom = 0
        while bottom < limit,
              rowDifference(previous.height - 1 - bottom) <= maximumRowDifference {
            bottom += 1
        }

        // One or two coincidentally equal rows are not a stable application region.
        return StableEdgeRegions(
            topRows: top >= 3 ? top : 0,
            bottomRows: bottom >= 3 ? bottom : 0
        )
    }
}
