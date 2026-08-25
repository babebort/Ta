import CoreGraphics
import AIScreenshotCore
import XCTest
@testable import AIScreenshotApp

@MainActor
final class ScrollingCaptureSessionControllerTests: XCTestCase {
    func testRecommendedScrollDistanceScalesWithSelectionAndStaysBounded() {
        XCTAssertEqual(
            ScrollingCaptureSessionController.recommendedScrollDistance(for: selection(height: 200)),
            180
        )
        XCTAssertEqual(
            ScrollingCaptureSessionController.recommendedScrollDistance(for: selection(height: 800)),
            384
        )
        XCTAssertEqual(
            ScrollingCaptureSessionController.recommendedScrollDistance(for: selection(height: 1600)),
            520
        )
    }

    func testSyntheticPointerPositionRestoresOriginalPointer() {
        XCTAssertEqual(
            AccessibilityAutoScrollService.pointerRestorationPoint(
                original: CGPoint(x: 42, y: 84),
                current: CGPoint(x: 500, y: 400),
                synthetic: CGPoint(x: 500, y: 400)
            ),
            CGPoint(x: 42, y: 84)
        )
    }

    func testAutoScrollUsesBoundedMouseWheelLines() {
        XCTAssertEqual(AccessibilityAutoScrollService.recommendedWheelLines(for: 80), 3)
        XCTAssertEqual(AccessibilityAutoScrollService.recommendedWheelLines(for: 384), 8)
        XCTAssertEqual(AccessibilityAutoScrollService.recommendedWheelLines(for: 900), 10)
        XCTAssertEqual(AccessibilityAutoScrollService.standardWheelBurstCount, 2)
    }

    func testAutoScrollUsesStandardFastCaptureTiming() {
        XCTAssertEqual(ScrollingCaptureSessionController.standardAutoScrollDelayMilliseconds, 300)
        XCTAssertEqual(ScrollingCaptureSessionController.standardAutoScrollDelay, 0.30)
        XCTAssertEqual(ScrollingCaptureSessionController.maximumAutoScrollSettleTime, 0.90)
    }

    func testConcurrentUserMovementIsNeverOverwritten() {
        XCTAssertNil(
            AccessibilityAutoScrollService.pointerRestorationPoint(
                original: CGPoint(x: 42, y: 84),
                current: CGPoint(x: 620, y: 460),
                synthetic: CGPoint(x: 500, y: 400)
            )
        )
    }

    func testRejectedFrameDefersRetryOnlyWithinBoundedSettleWindow() {
        var progress = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
        progress.begin()
        progress.didSendScroll()
        progress.observe(.rejected)
        let now = Date()

        XCTAssertTrue(
            ScrollingCaptureSessionController.shouldDeferAutoScrollRetry(
                progress: progress,
                now: now,
                settleDeadline: now.addingTimeInterval(1)
            )
        )
        XCTAssertFalse(
            ScrollingCaptureSessionController.shouldDeferAutoScrollRetry(
                progress: progress,
                now: now,
                settleDeadline: now.addingTimeInterval(-0.01)
            )
        )
    }

    func testStationaryViewportCountsAsNoProgressEvenWhenSeamIsRejected() {
        let observation = ScrollingCaptureSessionController.autoScrollObservation(
            stitchDisposition: .rejected,
            motion: ViewportMotionMeasurement(
                hasReference: true,
                meanAbsoluteDifference: 0.8,
                changedPixelFraction: 0.01,
                isStationary: true
            )
        )

        XCTAssertEqual(observation, .duplicate)
    }

    func testMovedViewportNeverCountsAsBottomWhenSeamIsNotReady() {
        let observation = ScrollingCaptureSessionController.autoScrollObservation(
            stitchDisposition: .duplicate,
            motion: ViewportMotionMeasurement(
                hasReference: true,
                meanAbsoluteDifference: 34,
                changedPixelFraction: 0.7,
                isStationary: false
            )
        )

        XCTAssertEqual(observation, .rejected)
    }

    func testClosingSeamReviewWindowCancelsCaptureSession() throws {
        let stitcher = ScrollingImageStitcher()
        _ = try stitcher.append(makeImage(width: 120, height: 80))
        let controller = ScrollingSeamReviewWindowController()
        var cancellationCount = 0

        controller.present(
            stitcher: stitcher,
            onComplete: { _, _ in XCTFail("Closing the review window must not complete the capture") },
            onCancel: { cancellationCount += 1 }
        )
        let window = try XCTUnwrap(NSApp.windows.first(where: { $0.title == "检查长截图接缝" }))
        window.performClose(nil)

        XCTAssertEqual(cancellationCount, 1)
    }

    private func selection(height: CGFloat) -> CaptureSelection {
        CaptureSelection(
            globalRect: CGRect(x: 100, y: 100, width: 600, height: height),
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            displayID: 1,
            backingScaleFactor: 2
        )
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw NSError(domain: "ScrollingCaptureSessionControllerTests", code: 1)
        }
        return image
    }
}
