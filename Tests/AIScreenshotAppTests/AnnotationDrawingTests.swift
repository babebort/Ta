import AppKit
import XCTest
@testable import AIScreenshotApp

final class AnnotationDrawingTests: XCTestCase {
    func testTaperedArrowHasThinTailAndWideHead() {
        let points = TaperedArrowGeometry.polygon(
            from: CGPoint(x: 10, y: 40),
            to: CGPoint(x: 210, y: 40),
            width: 6
        )

        XCTAssertEqual(points.count, 7)
        XCTAssertEqual(points[3], CGPoint(x: 210, y: 40))
        let tailWidth = abs(points[6].y - points[0].y)
        let headWidth = abs(points[4].y - points[2].y)
        XCTAssertLessThan(tailWidth, headWidth)
        XCTAssertGreaterThan(headWidth, 20)
    }

    func testShortTaperedArrowKeepsHeadBehindTip() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 18, y: 0)
        let points = TaperedArrowGeometry.polygon(from: start, to: end, width: 8)

        XCTAssertEqual(points[3], end)
        XCTAssertTrue(points[2].x >= start.x)
        XCTAssertTrue(points[2].x < end.x)
    }

    func testAnnotationToolsExposeBothMosaicModes() {
        XCTAssertEqual(AnnotationTool.mosaic.displayName, "框选马赛克")
        XCTAssertEqual(AnnotationTool.mosaicBrush.displayName, "涂抹马赛克")
    }

    func testTextSizesStepThroughSnipasteStylePresets() {
        XCTAssertEqual(AnnotationTextMetrics.defaultSize, 24)
        XCTAssertEqual(AnnotationTextMetrics.stepped(from: 24, direction: 1), 28)
        XCTAssertEqual(AnnotationTextMetrics.stepped(from: 24, direction: -1), 20)
        XCTAssertEqual(AnnotationTextMetrics.stepped(from: 72, direction: 1), 72)
        XCTAssertEqual(AnnotationTextMetrics.stepped(from: 12, direction: -1), 12)
    }

    func testMultilineTextMeasurementGrowsVertically() {
        let font = NSFont.systemFont(ofSize: 24)
        let singleLine = AnnotationTextMetrics.boundingSize(for: "第一行", font: font, maximumWidth: 240)
        let twoLines = AnnotationTextMetrics.boundingSize(for: "第一行\n第二行", font: font, maximumWidth: 240)

        XCTAssertGreaterThan(twoLines.height, singleLine.height)
        XCTAssertLessThanOrEqual(twoLines.width, 240)
    }

    func testMosaicStrokeSmootherFillsFastPointerGaps() throws {
        let points = AnnotationStrokeSmoother.points(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 100, y: 0),
            maximumSpacing: 8
        )

        XCTAssertEqual(try XCTUnwrap(points.last), CGPoint(x: 100, y: 0))
        XCTAssertGreaterThan(points.count, 10)
        var previous = CGPoint.zero
        for point in points {
            XCTAssertLessThanOrEqual(hypot(point.x - previous.x, point.y - previous.y), 8.01)
            previous = point
        }
    }

    func testCornerResizeUsesOppositeCornerAndUniformScale() {
        let bounds = CGRect(x: 20, y: 30, width: 100, height: 80)
        XCTAssertEqual(AnnotationResizeHandle.topRight.anchor(in: bounds), CGPoint(x: 20, y: 30))

        let scale = AnnotationSelectionGeometry.uniformScale(
            anchor: CGPoint(x: 20, y: 30),
            originalHandle: CGPoint(x: 120, y: 110),
            draggedHandle: CGPoint(x: 220, y: 190)
        )
        XCTAssertEqual(scale, 2, accuracy: 0.001)
    }

    func testCornerResizeClampsBeforeObjectCanInvert() {
        let scale = AnnotationSelectionGeometry.uniformScale(
            anchor: .zero,
            originalHandle: CGPoint(x: 100, y: 100),
            draggedHandle: CGPoint(x: -20, y: -20)
        )
        XCTAssertEqual(scale, 0.1, accuracy: 0.001)
    }
}
