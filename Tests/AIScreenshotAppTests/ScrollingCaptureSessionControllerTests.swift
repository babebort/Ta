import AIScreenshotCore
import CoreGraphics
import XCTest

@testable import AIScreenshotApp

@MainActor
final class ScrollingCaptureSessionControllerTests: XCTestCase {
  func testRecommendedScrollDistanceScalesWithSelectionAndStaysBounded() {
    XCTAssertEqual(
      ScrollingCaptureSessionController.recommendedScrollDistance(for: selection(height: 200)),
      120
    )
    XCTAssertEqual(
      ScrollingCaptureSessionController.recommendedScrollDistance(for: selection(height: 800)),
      336
    )
    XCTAssertEqual(
      ScrollingCaptureSessionController.recommendedScrollDistance(for: selection(height: 1600)),
      460
    )
  }

  func testAutoScrollSplitsLargeGestureIntoPortablePixelSteps() {
    XCTAssertEqual(
      AccessibilityAutoScrollService.pixelDeltas(for: 130),
      [-32, -32, -32, -32, -2]
    )
    XCTAssertEqual(AccessibilityAutoScrollService.pixelDeltas(for: 1), [-1])
    XCTAssertEqual(AccessibilityAutoScrollService.pixelDeltas(for: 96).reduce(0, +), -96)
    XCTAssertTrue(
      AccessibilityAutoScrollService.pixelDeltas(for: 520)
        .allSatisfy { abs($0) <= 32 }
    )
    XCTAssertEqual(AccessibilityAutoScrollService.pixelDeltas(for: -65), [32, 32, 1])
  }

  func testAutoScrollUsesStandardFastCaptureTiming() {
    XCTAssertEqual(ScrollingCaptureSessionController.standardAutoScrollDelayMilliseconds, 300)
    XCTAssertEqual(ScrollingCaptureSessionController.standardAutoScrollDelay, 0.30)
    XCTAssertEqual(ScrollingCaptureSessionController.maximumAutoScrollSettleTime, 1.20)
    XCTAssertEqual(AccessibilityAutoScrollService.scrollEventIntervalMilliseconds, 14)
  }

  func testVisibleMovementContinuesEvenWhenSeamMatcherRejectsFrame() {
    var progress = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
    progress.begin()
    progress.didSendScroll()
    progress.observe(.rejected)
    let now = Date()

    XCTAssertEqual(
      ScrollingCaptureSessionController.resolveAutoScrollAttempt(
        progress: progress,
        observation: .rejected,
        motion: ViewportMotionMeasurement(
          hasReference: true,
          meanAbsoluteDifference: 24,
          changedPixelFraction: 0.6,
          isStationary: false
        ),
        now: now,
        settleDeadline: now.addingTimeInterval(1)
      ),
      .progress
    )
  }

  func testStationaryAttemptIsTheOnlyConditionThatCountsAsBottomProgress() {
    var progress = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
    progress.didSendScroll()
    let now = Date()

    XCTAssertEqual(
      ScrollingCaptureSessionController.resolveAutoScrollAttempt(
        progress: progress,
        observation: .duplicate,
        motion: ViewportMotionMeasurement(
          hasReference: true,
          meanAbsoluteDifference: 0.4,
          changedPixelFraction: 0.002,
          isStationary: true
        ),
        now: now,
        settleDeadline: now
      ),
      .noMovement
    )
  }

  func testAccessibilityProgressAtEndDoesNotStopBeforePixelConfirmation() {
    var progress = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
    progress.didSendScroll()
    let now = Date()

    XCTAssertEqual(
      ScrollingCaptureSessionController.resolveAutoScrollAttempt(
        progress: progress,
        observation: .appended(newPixelHeight: 120, confidence: 0.9),
        motion: ViewportMotionMeasurement(
          hasReference: true,
          meanAbsoluteDifference: 18,
          changedPixelFraction: 0.4,
          isStationary: false
        ),
        scrollProgressBefore: AccessibilityScrollProgress(value: 0.94, minimum: 0, maximum: 1),
        scrollProgressAfter: AccessibilityScrollProgress(value: 1, minimum: 0, maximum: 1),
        now: now,
        settleDeadline: now
      ),
      .progress
    )
  }

  func testBottomSignalRequiresConsecutiveStableFramesAfterScrollbarReachesMaximum() {
    let end = AccessibilityScrollProgress(value: 1, minimum: 0, maximum: 1)
    let moving = ViewportMotionMeasurement(
      hasReference: true,
      meanAbsoluteDifference: 18,
      changedPixelFraction: 0.4,
      isStationary: false
    )
    let stable = ViewportMotionMeasurement(
      hasReference: true,
      meanAbsoluteDifference: 0.2,
      changedPixelFraction: 0,
      isStationary: true
    )

    XCTAssertEqual(
      ScrollingCaptureSessionController.advanceBottomConfirmation(
        currentCount: 0,
        observation: .appended(newPixelHeight: 30, confidence: 0.9),
        motion: stable,
        scrollProgressAfter: end
      ),
      0
    )
    XCTAssertEqual(
      ScrollingCaptureSessionController.advanceBottomConfirmation(
        currentCount: 0,
        observation: .rejected,
        motion: moving,
        scrollProgressAfter: end
      ),
      0
    )
    XCTAssertEqual(
      ScrollingCaptureSessionController.advanceBottomConfirmation(
        currentCount: 0,
        observation: .duplicate,
        motion: stable,
        scrollProgressAfter: end
      ),
      1
    )
    XCTAssertEqual(
      ScrollingCaptureSessionController.advanceBottomConfirmation(
        currentCount: 2,
        observation: .duplicate,
        motion: stable,
        scrollProgressAfter: end
      ),
      ScrollingCaptureSessionController.requiredBottomConfirmationFrames
    )
  }

  func testBottomSignalDoesNotCompleteBeforeTheTerminalViewportSettles() {
    let end = AccessibilityScrollProgress(value: 1, minimum: 0, maximum: 1)
    let firstBottomFrame = ViewportMotionMeasurement(
      hasReference: false,
      meanAbsoluteDifference: 0,
      changedPixelFraction: 0,
      isStationary: false
    )
    let stillAnimating = ViewportMotionMeasurement(
      hasReference: true,
      meanAbsoluteDifference: 12,
      changedPixelFraction: 0.18,
      isStationary: false
    )
    let settled = ViewportMotionMeasurement(
      hasReference: true,
      meanAbsoluteDifference: 0.3,
      changedPixelFraction: 0.001,
      isStationary: true
    )

    XCTAssertEqual(
      ScrollingCaptureSessionController.advanceBottomConfirmation(
        currentCount: 0,
        observation: .rejected,
        motion: firstBottomFrame,
        scrollProgressAfter: end
      ),
      0
    )
    XCTAssertEqual(
      ScrollingCaptureSessionController.advanceBottomConfirmation(
        currentCount: 0,
        observation: .rejected,
        motion: stillAnimating,
        scrollProgressAfter: end
      ),
      0
    )
    XCTAssertEqual(
      ScrollingCaptureSessionController.advanceBottomConfirmation(
        currentCount: 0,
        observation: .duplicate,
        motion: settled,
        scrollProgressAfter: end
      ),
      1
    )
  }

  func testTrackedMovementCannotBeMistakenForNoMovement() {
    var progress = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
    progress.didSendScroll()
    let now = Date()

    XCTAssertEqual(
      ScrollingCaptureSessionController.resolveAutoScrollAttempt(
        progress: progress,
        observation: .duplicate,
        motion: ViewportMotionMeasurement(
          hasReference: true,
          meanAbsoluteDifference: 1,
          changedPixelFraction: 0.01,
          isStationary: true
        ),
        scrollProgressBefore: AccessibilityScrollProgress(value: 0.20, minimum: 0, maximum: 1),
        scrollProgressAfter: AccessibilityScrollProgress(value: 0.24, minimum: 0, maximum: 1),
        now: now,
        settleDeadline: now
      ),
      .progress
    )
  }

  func testTrackedLazyLoadingStillClosesGestureAndContinuesScrolling() {
    var progress = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
    progress.didSendScroll()
    let now = Date()

    XCTAssertEqual(
      ScrollingCaptureSessionController.resolveAutoScrollAttempt(
        progress: progress,
        observation: .rejected,
        motion: ViewportMotionMeasurement(
          hasReference: true,
          meanAbsoluteDifference: 9,
          changedPixelFraction: 0.08,
          isStationary: false
        ),
        scrollProgressBefore: AccessibilityScrollProgress(value: 0.42, minimum: 0, maximum: 1),
        scrollProgressAfter: AccessibilityScrollProgress(value: 0.42, minimum: 0, maximum: 1),
        now: now,
        settleDeadline: now
      ),
      .progress
    )
  }

  func testScrollProgressNormalizesNonUnitRanges() {
    let progress = AccessibilityScrollProgress(value: 35, minimum: 10, maximum: 60)
    XCTAssertEqual(progress.normalizedValue, 0.5, accuracy: 0.0001)
    XCTAssertFalse(progress.isAtEnd)
    XCTAssertTrue(AccessibilityScrollProgress(value: 60, minimum: 10, maximum: 60).isAtEnd)
  }

  func testTrackedScrollbarCannotStopEarlyWhileItsProgressIsBelowTheBottom() {
    var progress = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
    progress.didSendScroll()
    progress.finishPendingWithoutProgress()
    progress.didSendScroll()
    progress.finishPendingWithoutProgress()
    XCTAssertTrue(progress.shouldStop)

    XCTAssertFalse(
      ScrollingCaptureSessionController.shouldCompleteAfterNoProgress(
        progress: progress,
        targetMode: .accessibilityTracked,
        currentScrollProgress: AccessibilityScrollProgress(value: 0.42, minimum: 0, maximum: 1)
      )
    )
    XCTAssertTrue(
      ScrollingCaptureSessionController.shouldCompleteAfterNoProgress(
        progress: progress,
        targetMode: .accessibilityTracked,
        currentScrollProgress: AccessibilityScrollProgress(value: 1, minimum: 0, maximum: 1)
      )
    )
  }

  func testFallbackModeCanFinishAfterItsFullNoMovementBudget() {
    var progress = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
    progress.didSendScroll()
    progress.finishPendingWithoutProgress()
    progress.didSendScroll()
    progress.finishPendingWithoutProgress()

    XCTAssertTrue(
      ScrollingCaptureSessionController.shouldCompleteAfterNoProgress(
        progress: progress,
        targetMode: .eventFallback,
        currentScrollProgress: nil
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
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ), let image = context.makeImage()
    else {
      throw NSError(domain: "ScrollingCaptureSessionControllerTests", code: 1)
    }
    return image
  }
}
