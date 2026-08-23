import CoreGraphics
import XCTest
@testable import AIScreenshotCore

final class OCRDocumentLayoutAnalyzerTests: XCTestCase {
    func testDetectsRowsAndCellsAsTable() {
        let lines = [
            line("Name", x: 0.1, y: 0.8), line("Score", x: 0.55, y: 0.8),
            line("Alice", x: 0.1, y: 0.7), line("98", x: 0.55, y: 0.7),
            line("Bob", x: 0.1, y: 0.6), line("95", x: 0.55, y: 0.6)
        ]

        let document = OCRDocumentLayoutAnalyzer().analyze(lines: lines)

        XCTAssertEqual(document.tables.first?.rows, [["Name", "Score"], ["Alice", "98"], ["Bob", "95"]])
        XCTAssertTrue(document.tables.first?.markdown.contains("| Name | Score |") == true)
    }

    func testSeparatesParagraphsAcrossLargeVerticalGap() {
        let lines = [
            line("Heading", x: 0.1, y: 0.85),
            line("First paragraph", x: 0.1, y: 0.78),
            line("Second section", x: 0.1, y: 0.42)
        ]

        let document = OCRDocumentLayoutAnalyzer().analyze(lines: lines)

        XCTAssertEqual(document.blocks.count, 2)
        XCTAssertEqual(document.blocks.last?.text, "Second section")
    }

    func testSplitsWhitespaceSeparatedCells() {
        let lines = [
            line("Product   Price   Qty", x: 0.1, y: 0.8),
            line("Tea       12      2", x: 0.1, y: 0.7)
        ]

        let document = OCRDocumentLayoutAnalyzer().analyze(lines: lines)

        XCTAssertEqual(document.tables.first?.rows.first, ["Product", "Price", "Qty"])
    }

    private func line(_ text: String, x: CGFloat, y: CGFloat) -> OCRTextLine {
        OCRTextLine(text: text, confidence: 0.95, boundingBox: CGRect(x: x, y: y, width: 0.25, height: 0.04))
    }
}
