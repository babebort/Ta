import AppKit
import XCTest
@testable import AIScreenshotApp

final class InlineAnnotationLayoutTests: XCTestCase {
    func testCompactToolbarMetrics() {
        XCTAssertEqual(InlineAnnotationToolbarMetrics.buttonSize, CGSize(width: 32, height: 30))
        XCTAssertEqual(InlineAnnotationToolbarMetrics.symbolPointSize, 10)
        XCTAssertEqual(InlineAnnotationToolbarMetrics.textPointSize, 12)
        XCTAssertEqual(InlineAnnotationToolbarMetrics.spacing, 3)
    }

    func testToolbarPrefersBelowSelection() {
        let frame = InlineAnnotationLayout.toolbarFrame(
            selection: CGRect(x: 300, y: 240, width: 400, height: 260),
            screenBounds: CGRect(x: 0, y: 0, width: 1200, height: 800),
            toolbarSize: CGSize(width: 700, height: 48)
        )

        XCTAssertEqual(frame.minY, 182)
        XCTAssertEqual(frame.midX, 500)
    }

    func testToolbarMovesAboveWhenThereIsNoRoomBelow() {
        let frame = InlineAnnotationLayout.toolbarFrame(
            selection: CGRect(x: 100, y: 20, width: 420, height: 260),
            screenBounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
            toolbarSize: CGSize(width: 620, height: 48)
        )

        XCTAssertEqual(frame.minY, 290)
    }

    func testToolbarClampsToScreenHorizontally() {
        let frame = InlineAnnotationLayout.toolbarFrame(
            selection: CGRect(x: 910, y: 300, width: 80, height: 180),
            screenBounds: CGRect(x: 0, y: 0, width: 1000, height: 700),
            toolbarSize: CGSize(width: 700, height: 48)
        )

        XCTAssertEqual(frame.maxX, 992)
    }

    @MainActor
    func testInlineCanvasDisplaysImageEdgeToEdge() throws {
        let image = try XCTUnwrap(makeImage(width: 400, height: 200))
        let inline = AnnotationCanvasView(image: image, contentInset: 0)
        inline.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        let standalone = AnnotationCanvasView(image: image)
        standalone.frame = CGRect(x: 0, y: 0, width: 448, height: 248)

        XCTAssertEqual(inline.displayedImageFrame, inline.bounds)
        XCTAssertEqual(standalone.displayedImageFrame, standalone.bounds.insetBy(dx: 24, dy: 24))
    }

    @MainActor
    func testRightClickCancelsInlineCanvas() throws {
        let image = try XCTUnwrap(makeImage(width: 400, height: 200))
        let canvas = AnnotationCanvasView(image: image, contentInset: 0)
        var didCancel = false
        canvas.onCancel = { didCancel = true }
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: CGPoint(x: 20, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        canvas.rightMouseDown(with: event)
        XCTAssertTrue(didCancel)
    }

    @MainActor
    func testTextEntryUsesInlineCanvasEditor() throws {
        let image = try XCTUnwrap(makeImage(width: 400, height: 200))
        let canvas = AnnotationCanvasView(image: image, contentInset: 0)
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 200)

        canvas.beginTextEntry(at: CGPoint(x: 80, y: 90))

        XCTAssertTrue(canvas.isTextEntryActive)
        let editor = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        XCTAssertFalse(editor.drawsBackground)
        XCTAssertFalse(editor.isRichText)
    }

    @MainActor
    func testRightClickFinishesActiveTextInsteadOfCancellingCapture() throws {
        let image = try XCTUnwrap(makeImage(width: 400, height: 200))
        let canvas = AnnotationCanvasView(image: image, contentInset: 0)
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        var didCancel = false
        canvas.onCancel = { didCancel = true }
        canvas.beginTextEntry(at: CGPoint(x: 80, y: 90))
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: CGPoint(x: 80, y: 90),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        canvas.rightMouseDown(with: event)

        XCTAssertFalse(canvas.isTextEntryActive)
        XCTAssertFalse(didCancel)
    }

    private func makeImage(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
