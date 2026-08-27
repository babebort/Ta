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

    func testScreenshotPinPreservesSelectionPointSizeOnRetina() {
        let size = PinnedImageLayout.initialSize(
            imagePixels: CGSize(width: 800, height: 500),
            preferredLogicalSize: CGSize(width: 400, height: 250),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950)
        )

        XCTAssertEqual(size, CGSize(width: 400, height: 250))
    }

    func testSmallScreenshotPinIsNotArtificiallyEnlarged() {
        let size = PinnedImageLayout.initialSize(
            imagePixels: CGSize(width: 160, height: 100),
            preferredLogicalSize: CGSize(width: 80, height: 50),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950)
        )

        XCTAssertEqual(size, CGSize(width: 80, height: 50))
    }

    func testOversizedPinScalesDownProportionallyToVisibleScreen() {
        let size = PinnedImageLayout.initialSize(
            imagePixels: CGSize(width: 2400, height: 1600),
            preferredLogicalSize: CGSize(width: 1200, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 900, height: 700)
        )

        XCTAssertEqual(size.width, 876, accuracy: 0.001)
        XCTAssertEqual(size.height, 584, accuracy: 0.001)
    }

    func testPinDecorationsDefaultToVisible() {
        let state = PinnedImageDecorationState()

        XCTAssertTrue(state.showsBorder)
        XCTAssertTrue(state.showsShadow)
    }

    func testPinBorderAndShadowCanBeToggledIndependently() {
        var state = PinnedImageDecorationState()

        state.toggleBorder()
        XCTAssertFalse(state.showsBorder)
        XCTAssertTrue(state.showsShadow)

        state.toggleShadow()
        XCTAssertFalse(state.showsBorder)
        XCTAssertFalse(state.showsShadow)
    }

    @MainActor
    func testPinnedPanelCanMoveAboveTheMenuBarWithoutSystemClamping() {
        let panel = PinnedImagePanel(
            contentRect: CGRect(x: 100, y: 100, width: 320, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let proposed = CGRect(x: 100, y: 920, width: 320, height: 180)

        XCTAssertEqual(panel.constrainFrameRect(proposed, to: nil), proposed)
    }
}
