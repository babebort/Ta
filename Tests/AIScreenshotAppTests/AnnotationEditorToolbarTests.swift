import AppKit
import XCTest
@testable import AIScreenshotApp

final class AnnotationEditorToolbarTests: XCTestCase {
    func testEditorUsesNativeTitlebarAndTwoToolbarRows() {
        XCTAssertFalse(AnnotationEditorWindowLayout.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(AnnotationEditorToolbarMetrics.rowCount, 2)
        XCTAssertEqual(AnnotationEditorToolbarMetrics.height, 96)
    }

    func testEditorToolbarSpacingKeepsControlsComfortable() {
        XCTAssertGreaterThanOrEqual(AnnotationEditorToolbarMetrics.horizontalInset, 16)
        XCTAssertGreaterThanOrEqual(AnnotationEditorToolbarMetrics.groupSpacing, 8)
        XCTAssertGreaterThanOrEqual(AnnotationEditorToolbarMetrics.iconButtonSide, 30)
        XCTAssertGreaterThanOrEqual(AnnotationEditorToolbarMetrics.toolPickerWidth, 170)
    }
}
