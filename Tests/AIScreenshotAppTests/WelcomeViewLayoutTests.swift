import XCTest
@testable import AIScreenshotApp

final class WelcomeViewLayoutTests: XCTestCase {
    func testWelcomeWindowDefaultSizeExceedsMinimumSize() {
        XCTAssertGreaterThanOrEqual(
            WelcomeViewMetrics.defaultWindowSize.width,
            WelcomeViewMetrics.minimumWindowSize.width
        )
        XCTAssertGreaterThanOrEqual(
            WelcomeViewMetrics.defaultWindowSize.height,
            WelcomeViewMetrics.minimumWindowSize.height
        )
    }

    func testQuickActionsUseCompactThreeColumnDashboard() {
        XCTAssertEqual(WelcomeViewMetrics.quickActionColumnCount, 3)
        XCTAssertEqual(WelcomeViewMetrics.quickActionCount, 6)
        XCTAssertEqual(WelcomeViewMetrics.quickActionMinimumHeight, 74)
        XCTAssertLessThan(WelcomeViewMetrics.gridSpacing, WelcomeViewMetrics.sectionSpacing)
    }

    func testPrimaryActionHasStrongerVisualHierarchy() {
        XCTAssertGreaterThan(
            WelcomeViewMetrics.primaryCornerRadius,
            WelcomeViewMetrics.quickActionCornerRadius
        )
    }
}
