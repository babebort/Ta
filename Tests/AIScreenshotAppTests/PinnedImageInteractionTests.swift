import XCTest
@testable import AIScreenshotApp

final class PinnedImageInteractionTests: XCTestCase {
    func testSingleClickKeepsPinnedImageVisible() {
        XCTAssertFalse(PinnedImageInteraction.shouldClose(clickCount: 1))
    }

    func testDoubleAndHigherClickCountsClosePinnedImage() {
        XCTAssertTrue(PinnedImageInteraction.shouldClose(clickCount: 2))
        XCTAssertTrue(PinnedImageInteraction.shouldClose(clickCount: 3))
    }
}
