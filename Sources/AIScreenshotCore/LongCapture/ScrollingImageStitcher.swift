import CoreGraphics
import Foundation

public enum ScrollingImageStitcherError: LocalizedError {
    case noFrames
    case invalidImage
    case outputTooLarge
    case couldNotCreateCanvas

    public var errorDescription: String? {
        switch self {
        case .noFrames:
            "没有采集到可用画面。"
        case .invalidImage:
            "滚动截图画面无效。"
        case .outputTooLarge:
            "长截图尺寸过大，请提前结束并分段保存。"
        case .couldNotCreateCanvas:
            "无法创建长截图画布。"
        }
    }
}

public enum ScrollingFrameDisposition: Equatable, Sendable {
    case firstFrame
    case appended(newPixelHeight: Int, confidence: Double)
    case duplicate
    case rejected
}

public struct ScrollingStitchSegment: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let direction: VerticalScrollDirection
    public let newPixelHeight: Int
    public let confidence: Double
    public let stableTopHeight: Int
    public let stableBottomHeight: Int

    public init(
        id: UUID = UUID(),
        direction: VerticalScrollDirection,
        newPixelHeight: Int,
        confidence: Double,
        stableTopHeight: Int,
        stableBottomHeight: Int
    ) {
        self.id = id
        self.direction = direction
        self.newPixelHeight = newPixelHeight
        self.confidence = confidence
        self.stableTopHeight = stableTopHeight
        self.stableBottomHeight = stableBottomHeight
    }
}

public enum ScrollingCaptureQualityIssue: Equatable, Sendable {
    case lowConfidence(segmentID: UUID, confidence: Double)
    case ultraLongOutput(recommendedPartCount: Int)
}

public final class ScrollingImageStitcher {
    private struct CapturedSegment {
        let image: CGImage
        let details: ScrollingStitchSegment
    }

    private struct ImageStrip {
        let image: CGImage
        let sourceY: Int
        let height: Int
    }

    private let matcher: VerticalScrollMatcher
    private let sampleWidth: Int
    private let sampleHeight: Int
    private let maximumOutputPixels: Int
    private var firstImage: CGImage?
    private var previousSample: GrayscaleFrame?
    private var capturedSegments: [CapturedSegment] = []
    private var stitchSegments: [ScrollingStitchSegment] = []
    private var accumulatedHeight = 0
    private var viewportOffset = 0
    private var minimumViewportOffset = 0
    private var maximumViewportOffset = 0

    public init(
        matcher: VerticalScrollMatcher = VerticalScrollMatcher(),
        sampleWidth: Int = 96,
        sampleHeight: Int = 720,
        maximumOutputPixels: Int = 120_000_000
    ) {
        self.matcher = matcher
        self.sampleWidth = max(32, sampleWidth)
        self.sampleHeight = max(120, sampleHeight)
        self.maximumOutputPixels = maximumOutputPixels
    }

    public var frameCount: Int {
        firstImage == nil ? 0 : capturedSegments.count + 1
    }

    public var outputPixelHeight: Int { accumulatedHeight }

    public var segments: [ScrollingStitchSegment] { stitchSegments }

    public var qualityIssues: [ScrollingCaptureQualityIssue] {
        var issues = stitchSegments.compactMap { segment -> ScrollingCaptureQualityIssue? in
            guard segment.confidence < 0.58 else { return nil }
            return .lowConfidence(segmentID: segment.id, confidence: segment.confidence)
        }
        if let firstImage {
            let safeHeight = max(1, maximumOutputPixels / max(1, firstImage.width))
            if accumulatedHeight > safeHeight {
                issues.append(.ultraLongOutput(
                    recommendedPartCount: Int(ceil(Double(accumulatedHeight) / Double(safeHeight)))
                ))
            }
        }
        return issues
    }

    /// Lets the review UI nudge a detected seam without re-running capture.
    /// A negative delta removes duplicated rows; a positive delta restores rows.
    @discardableResult
    public func adjustSegment(id: UUID, pixelDelta: Int) -> Bool {
        guard let capturedIndex = capturedSegments.firstIndex(where: { $0.details.id == id }),
              let publicIndex = stitchSegments.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let captured = capturedSegments[capturedIndex]
        let old = captured.details
        let newHeight = min(captured.image.height, max(1, old.newPixelHeight + pixelDelta))
        guard newHeight != old.newPixelHeight else { return false }
        let updated = ScrollingStitchSegment(
            id: old.id,
            direction: old.direction,
            newPixelHeight: newHeight,
            confidence: old.confidence,
            stableTopHeight: old.stableTopHeight,
            stableBottomHeight: old.stableBottomHeight
        )
        capturedSegments[capturedIndex] = CapturedSegment(image: captured.image, details: updated)
        stitchSegments[publicIndex] = updated
        accumulatedHeight += newHeight - old.newPixelHeight
        return true
    }

    public func reset() {
        firstImage = nil
        previousSample = nil
        capturedSegments.removeAll(keepingCapacity: true)
        stitchSegments.removeAll(keepingCapacity: true)
        accumulatedHeight = 0
        viewportOffset = 0
        minimumViewportOffset = 0
        maximumViewportOffset = 0
    }

    @discardableResult
    public func append(
        _ image: CGImage,
        constraint: VerticalScrollConstraint = .any,
        preferredPixelShift: Int? = nil
    ) throws -> ScrollingFrameDisposition {
        guard image.width > 0, image.height > 0 else {
            throw ScrollingImageStitcherError.invalidImage
        }
        let sample = try makeSample(from: image)

        guard let firstImage, let previousSample else {
            self.firstImage = image
            self.previousSample = sample
            accumulatedHeight = image.height
            return .firstFrame
        }
        guard image.width == firstImage.width, image.height == firstImage.height else {
            return .rejected
        }
        let scale = Double(image.height) / Double(sample.height)
        let preferredSampleShift = preferredPixelShift.map {
            Int((Double($0) / scale).rounded())
        }
        guard let match = matcher.match(
            previous: previousSample,
            current: sample,
            constraint: constraint,
            preferredSignedShift: preferredSampleShift
        ) else {
            return .rejected
        }
        return appendMatched(
            image: image,
            sample: sample,
            previousSample: previousSample,
            match: match,
            scale: scale
        )
    }

    /// Commits the final, settled viewport after the tracked scrollbar reaches
    /// its maximum. The last scroll is commonly shorter than the regular step,
    /// and repeated chat rows can make that small seam look ambiguous. At the
    /// confirmed bottom it is safer to accept the best downward overlap at low
    /// confidence so the document tail is retained for seam review.
    @discardableResult
    public func appendTerminalFrame(
        _ image: CGImage,
        preferredPixelShift: Int? = nil
    ) throws -> ScrollingFrameDisposition {
        guard image.width > 0, image.height > 0 else {
            throw ScrollingImageStitcherError.invalidImage
        }
        let sample = try makeSample(from: image)
        guard let firstImage, let previousSample else {
            self.firstImage = image
            self.previousSample = sample
            accumulatedHeight = image.height
            return .firstFrame
        }
        guard image.width == firstImage.width, image.height == firstImage.height else {
            return .rejected
        }

        let scale = Double(image.height) / Double(sample.height)
        let preferredSampleShift = preferredPixelShift.map {
            Int((Double($0) / scale).rounded())
        }
        guard let match = matcher.match(
            previous: previousSample,
            current: sample,
            constraint: .downwardOnly,
            preferredSignedShift: preferredSampleShift,
            allowsAmbiguousMatch: true,
            minimumAcceptedConfidence: 0.05
        ) else {
            return .rejected
        }
        let terminalMatch = VerticalScrollMatch(
            signedShift: match.signedShift,
            meanAbsoluteDifference: match.meanAbsoluteDifference,
            confidence: min(match.confidence, 0.35)
        )
        return appendMatched(
            image: image,
            sample: sample,
            previousSample: previousSample,
            match: terminalMatch,
            scale: scale
        )
    }

    private func appendMatched(
        image: CGImage,
        sample: GrayscaleFrame,
        previousSample: GrayscaleFrame,
        match: VerticalScrollMatch,
        scale: Double
    ) -> ScrollingFrameDisposition {
        guard let firstImage else { return .rejected }
        if match.isDuplicate {
            return .duplicate
        }

        let signedPixelShift = Int((Double(match.signedShift) * scale).rounded())
        viewportOffset += signedPixelShift

        let newPixelHeight: Int
        if viewportOffset < minimumViewportOffset {
            newPixelHeight = minimumViewportOffset - viewportOffset
            minimumViewportOffset = viewportOffset
        } else if viewportOffset > maximumViewportOffset {
            newPixelHeight = viewportOffset - maximumViewportOffset
            maximumViewportOffset = viewportOffset
        } else {
            // The user reversed into an area that is already represented. Keep
            // this frame as the next matching reference, but do not duplicate it.
            self.previousSample = sample
            return .duplicate
        }

        let appendedHeight = min(image.height, max(1, newPixelHeight))
        guard appendedHeight >= 2 else {
            self.previousSample = sample
            return .duplicate
        }

        let stable = matcher.stableEdges(previous: previousSample, current: sample)
        let details = ScrollingStitchSegment(
            direction: signedPixelShift < 0 ? .up : .down,
            newPixelHeight: appendedHeight,
            confidence: match.confidence,
            stableTopHeight: min(image.height / 3, Int((Double(stable.topRows) * scale).rounded())),
            stableBottomHeight: min(image.height / 3, Int((Double(stable.bottomRows) * scale).rounded()))
        )
        capturedSegments.append(CapturedSegment(image: image, details: details))
        stitchSegments.append(details)
        accumulatedHeight = firstImage.height + maximumViewportOffset - minimumViewportOffset
        self.previousSample = sample
        return .appended(newPixelHeight: appendedHeight, confidence: match.confidence)
    }

    /// Advances the stitching anchor after the viewport demonstrably moved but
    /// the visual matcher could not find a unique seam. Chat timelines often
    /// contain repeated cards, blank areas, animated cursors, and sticky
    /// composers; those conditions may make a correct seam ambiguous even
    /// though the scroll itself succeeded. Keeping this low-confidence frame
    /// is safer than blocking all subsequent capture or silently dropping an
    /// entire viewport.
    @discardableResult
    public func appendFallback(
        _ image: CGImage,
        signedPixelShift requestedSignedPixelShift: Int
    ) throws -> ScrollingFrameDisposition {
        guard image.width > 0, image.height > 0 else {
            throw ScrollingImageStitcherError.invalidImage
        }
        let sample = try makeSample(from: image)
        guard let firstImage, let previousSample else {
            self.firstImage = image
            self.previousSample = sample
            accumulatedHeight = image.height
            return .firstFrame
        }
        guard image.width == firstImage.width, image.height == firstImage.height else {
            return .rejected
        }

        let maximumSafeShift = max(2, Int((Double(image.height) * 0.55).rounded(.down)))
        let magnitude = min(maximumSafeShift, max(2, abs(requestedSignedPixelShift)))
        let signedPixelShift = requestedSignedPixelShift < 0 ? -magnitude : magnitude
        viewportOffset += signedPixelShift

        let newPixelHeight: Int
        if viewportOffset < minimumViewportOffset {
            newPixelHeight = minimumViewportOffset - viewportOffset
            minimumViewportOffset = viewportOffset
        } else if viewportOffset > maximumViewportOffset {
            newPixelHeight = viewportOffset - maximumViewportOffset
            maximumViewportOffset = viewportOffset
        } else {
            self.previousSample = sample
            return .duplicate
        }

        let appendedHeight = min(image.height, max(2, newPixelHeight))
        let scale = Double(image.height) / Double(sample.height)
        let stable = matcher.stableEdges(previous: previousSample, current: sample)
        let details = ScrollingStitchSegment(
            direction: signedPixelShift < 0 ? .up : .down,
            newPixelHeight: appendedHeight,
            confidence: 0,
            stableTopHeight: min(image.height / 3, Int((Double(stable.topRows) * scale).rounded())),
            stableBottomHeight: min(image.height / 3, Int((Double(stable.bottomRows) * scale).rounded()))
        )
        capturedSegments.append(CapturedSegment(image: image, details: details))
        stitchSegments.append(details)
        accumulatedHeight = firstImage.height + maximumViewportOffset - minimumViewportOffset
        self.previousSample = sample
        return .appended(newPixelHeight: appendedHeight, confidence: 0)
    }

    public func makeImage() throws -> CGImage {
        guard let firstImage else { throw ScrollingImageStitcherError.noFrames }
        guard firstImage.width * accumulatedHeight <= maximumOutputPixels else {
            throw ScrollingImageStitcherError.outputTooLarge
        }
        return try render(strips: makeStrips(), startY: 0, height: accumulatedHeight)
    }

    /// Renders an ultra-long capture into ordered, clipboard/save-friendly parts.
    public func makeImages(maximumPixelHeight: Int = 30_000) throws -> [CGImage] {
        guard let firstImage else { throw ScrollingImageStitcherError.noFrames }
        let pixelSafeHeight = max(1, maximumOutputPixels / max(1, firstImage.width))
        let partHeight = max(1, min(maximumPixelHeight, pixelSafeHeight))
        let strips = makeStrips()
        var images: [CGImage] = []
        var startY = 0
        while startY < accumulatedHeight {
            let height = min(partHeight, accumulatedHeight - startY)
            images.append(try render(strips: strips, startY: startY, height: height))
            startY += height
        }
        return images
    }

    private func makeStrips() -> [ImageStrip] {
        guard let firstImage else { return [] }
        let upward = capturedSegments.filter { $0.details.direction == .up }
        let downward = capturedSegments.filter { $0.details.direction == .down }

        // Sticky regions must be present consistently. Taking the maximum lets
        // one blank/repetitive frame crop that many rows from every seam, which
        // is especially destructive in chat apps with a large composer.
        let stableTop = conservativeStableHeight(upward.map(\.details.stableTopHeight))
        let stableBottom = conservativeStableHeight(downward.map(\.details.stableBottomHeight))
        let safeTop = min(stableTop, firstImage.height / 3)
        let safeBottom = min(stableBottom, firstImage.height / 3)
        var strips: [ImageStrip] = []

        if let earliest = upward.last, safeTop > 0 {
            strips.append(ImageStrip(image: earliest.image, sourceY: 0, height: safeTop))
        }
        for segment in upward.reversed() {
            let sourceY = min(safeTop, max(0, segment.image.height - segment.details.newPixelHeight))
            let height = min(segment.details.newPixelHeight, segment.image.height - sourceY)
            if height > 0 {
                strips.append(ImageStrip(image: segment.image, sourceY: sourceY, height: height))
            }
        }

        let baseTop = upward.isEmpty ? 0 : safeTop
        let baseBottom = downward.isEmpty ? 0 : safeBottom
        let baseHeight = max(0, firstImage.height - baseTop - baseBottom)
        if baseHeight > 0 {
            strips.append(ImageStrip(image: firstImage, sourceY: baseTop, height: baseHeight))
        }

        for segment in downward {
            let height = min(segment.details.newPixelHeight, segment.image.height - safeBottom)
            let sourceY = max(0, segment.image.height - safeBottom - height)
            if height > 0 {
                strips.append(ImageStrip(image: segment.image, sourceY: sourceY, height: height))
            }
        }
        if let latest = downward.last, safeBottom > 0 {
            strips.append(ImageStrip(
                image: latest.image,
                sourceY: latest.image.height - safeBottom,
                height: safeBottom
            ))
        }
        return strips
    }

    private func conservativeStableHeight(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        // Lower median: one unusually large detection can never dominate a
        // two-frame capture, while a stable region seen across frames survives.
        return sorted[(sorted.count - 1) / 2]
    }

    private func render(strips: [ImageStrip], startY: Int, height: Int) throws -> CGImage {
        guard let firstImage else { throw ScrollingImageStitcherError.noFrames }
        let width = firstImage.width
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScrollingImageStitcherError.couldNotCreateCanvas
        }

        context.interpolationQuality = .high

        let requested = startY..<(startY + height)
        var globalY = 0
        for strip in strips {
            let stripRange = globalY..<(globalY + strip.height)
            let lower = max(requested.lowerBound, stripRange.lowerBound)
            let upper = min(requested.upperBound, stripRange.upperBound)
            if lower < upper {
                let offset = lower - stripRange.lowerBound
                let cropRect = CGRect(
                    x: 0,
                    y: strip.sourceY + offset,
                    width: strip.image.width,
                    height: upper - lower
                )
                if let cropped = strip.image.cropping(to: cropRect) {
                    let destinationY = height - (upper - startY)
                    context.draw(cropped, in: CGRect(
                        x: 0,
                        y: destinationY,
                        width: width,
                        height: upper - lower
                    ))
                }
            }
            globalY += strip.height
        }

        guard let image = context.makeImage() else {
            throw ScrollingImageStitcherError.couldNotCreateCanvas
        }
        return image
    }

    func makeSample(from image: CGImage) throws -> GrayscaleFrame {
        // Horizontal and vertical matching have different needs. Deriving the
        // sample height from the (small) sample width made a wide Retina frame
        // only a few dozen rows tall, so one matcher row could represent
        // 10–20 real pixels and cut straight through a line of text. Keep a
        // high, independent vertical resolution while still compressing x.
        let height = min(image.height, sampleHeight)
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
