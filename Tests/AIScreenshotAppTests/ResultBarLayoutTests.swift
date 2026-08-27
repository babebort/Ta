import XCTest
@testable import AIScreenshotApp

final class ResultBarLayoutTests: XCTestCase {
    @MainActor
    func testShortSuccessToastUsesCompactMinimumWidth() {
        let state = ResultBarState(kind: .success, title: "已复制图片", detail: "910 × 358")

        XCTAssertEqual(ResultBarLayout.preferredWidth(for: state), 320)
        XCTAssertEqual(ResultBarLayout.height, 58)
    }

    @MainActor
    func testLongFailureToastNeverExceedsCompactMaximumWidth() {
        let state = ResultBarState(
            kind: .failure,
            title: "截图翻译失败",
            detail: "模型服务暂时不可用，请稍后重试或检查当前网络连接"
        )

        let width = ResultBarLayout.preferredWidth(for: state)
        XCTAssertGreaterThan(width, ResultBarLayout.minimumWidth)
        XCTAssertLessThanOrEqual(width, 352)
    }

    func testSelectedVisualUsesTaBrandPaletteAndOutlineStatusSymbols() {
        XCTAssertEqual(ResultBarKind.success.symbol, "checkmark.circle")
        XCTAssertEqual(ResultBarKind.failure.symbol, "xmark.circle")
        XCTAssertEqual(ResultBarLayout.cornerRadius, 18)
        XCTAssertEqual(ResultBarLayout.borderWidth, 0)
        XCTAssertEqual(ResultBarLayout.shadowOpacity, 0)
    }
}
