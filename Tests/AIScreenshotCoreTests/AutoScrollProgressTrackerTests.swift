import XCTest
@testable import AIScreenshotCore

final class AutoScrollProgressTrackerTests: XCTestCase {
    func testDuplicateCaptureTicksDoNotConsumeScrollAttemptBudget() {
        var tracker = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 6)
        tracker.begin()
        tracker.didSendScroll()

        for _ in 0..<20 {
            tracker.observe(.duplicate)
        }

        XCTAssertEqual(tracker.attemptsWithoutProgress, 0)
        XCTAssertFalse(tracker.shouldStop)
    }

    func testExplicitNoProgressResolutionCountsOneAttempt() {
        var tracker = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 6)
        tracker.begin()
        tracker.didSendScroll()
        tracker.observe(.duplicate)
        tracker.finishPendingWithoutProgress()

        XCTAssertEqual(tracker.attemptsWithoutProgress, 1)
        XCTAssertFalse(tracker.shouldStop)
    }

    func testAppendedFrameResetsNoProgressAttempts() {
        var tracker = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 6)
        tracker.begin()
        for _ in 0..<4 {
            tracker.didSendScroll()
            tracker.observe(.duplicate)
            tracker.finishPendingWithoutProgress()
        }
        XCTAssertEqual(tracker.attemptsWithoutProgress, 4)

        tracker.didSendScroll()

        tracker.observe(.appended(newPixelHeight: 120, confidence: 0.9))

        XCTAssertEqual(tracker.attemptsWithoutProgress, 0)
        XCTAssertFalse(tracker.shouldStop)
    }

    func testStopsAfterTwoActualScrollAttemptsWithoutProgress() {
        var tracker = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
        tracker.begin()

        for attempt in 0..<2 {
            tracker.didSendScroll()
            tracker.observe(.duplicate)
            tracker.finishPendingWithoutProgress()
            XCTAssertEqual(tracker.shouldStop, attempt == 1)
        }

        XCTAssertEqual(tracker.attemptsWithoutProgress, 2)
        XCTAssertTrue(tracker.shouldStop)
    }

    func testDefaultNoProgressLimitIsTwo() {
        XCTAssertEqual(AutoScrollProgressTracker().maximumAttemptsWithoutProgress, 2)
    }

    func testRejectedFrameRequestsSettlingTimeWithoutConsumingRetry() {
        var tracker = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
        tracker.begin()
        tracker.didSendScroll()

        tracker.observe(.rejected)

        XCTAssertTrue(tracker.needsMoreSettlingTime)
        XCTAssertEqual(tracker.attemptsWithoutProgress, 0)
    }

    func testAppendedFrameClearsSettlingWait() {
        var tracker = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
        tracker.begin()
        tracker.didSendScroll()
        tracker.observe(.rejected)

        tracker.observe(.appended(newPixelHeight: 90, confidence: 0.8))

        XCTAssertFalse(tracker.needsMoreSettlingTime)
        XCTAssertFalse(tracker.hasPendingScroll)
        XCTAssertEqual(tracker.attemptsWithoutProgress, 0)
    }

    func testSecondScrollCannotOpenWhilePreviousAttemptIsPending() {
        var tracker = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
        tracker.didSendScroll()
        tracker.didSendScroll()

        tracker.finishPendingWithoutProgress()

        XCTAssertEqual(tracker.attemptsWithoutProgress, 1)
    }

    func testRolledBackSeamDoesNotConsumeBottomBudget() {
        var tracker = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
        tracker.didSendScroll()
        tracker.observe(.rejected)

        tracker.cancelPendingAttempt()

        XCTAssertFalse(tracker.hasPendingScroll)
        XCTAssertFalse(tracker.needsMoreSettlingTime)
        XCTAssertEqual(tracker.attemptsWithoutProgress, 0)
        XCTAssertFalse(tracker.shouldStop)
    }

    func testConfirmedViewportMovementClosesPendingGestureWithoutCountingFailure() {
        var tracker = AutoScrollProgressTracker(maximumAttemptsWithoutProgress: 2)
        tracker.didSendScroll()
        tracker.observe(.rejected)

        tracker.finishPendingWithProgress()

        XCTAssertFalse(tracker.hasPendingScroll)
        XCTAssertFalse(tracker.needsMoreSettlingTime)
        XCTAssertEqual(tracker.attemptsWithoutProgress, 0)
        XCTAssertFalse(tracker.shouldStop)
    }
}
