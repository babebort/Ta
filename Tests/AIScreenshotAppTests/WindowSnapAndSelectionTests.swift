import AppKit
import XCTest
@testable import AIScreenshotApp

final class WindowSnapAndSelectionTests: XCTestCase {
    func testFrozenDisplayCropUsesRetinaPixelsAndAppKitVerticalCoordinates() {
        let selection = CaptureSelection(
            globalRect: CGRect(x: 50, y: 25, width: 100, height: 50),
            screenFrame: CGRect(x: 0, y: 0, width: 200, height: 150),
            displayID: 1,
            backingScaleFactor: 2
        )

        XCTAssertEqual(
            FrozenDisplayCropper.pixelRect(
                for: selection,
                imageWidth: 400,
                imageHeight: 300
            ),
            CGRect(x: 100, y: 150, width: 200, height: 100)
        )
    }

    func testCaptureServiceCropsTheFrozenFrameInsteadOfRecapturingTheDisplay() async throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 400,
            height: 300,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let frozenImage = try XCTUnwrap(context.makeImage())
        let selection = CaptureSelection(
            globalRect: CGRect(x: 50, y: 25, width: 100, height: 50),
            screenFrame: CGRect(x: 0, y: 0, width: 200, height: 150),
            displayID: 999_999,
            backingScaleFactor: 2,
            frozenDisplayImage: frozenImage
        )

        let cropped = try await ScreenCaptureService().capture(selection)

        XCTAssertEqual(cropped.width, 200)
        XCTAssertEqual(cropped.height, 100)
    }

    @MainActor
    func testInitialCaptureCursorIsCrosshair() {
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

        view.activateInitialCursor()

        XCTAssertTrue(NSCursor.current === NSCursor.crosshair)
    }

    func testFrontmostContainingWindowWins() {
        let targets = [
            WindowSnapTarget(windowID: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), zOrder: 4),
            WindowSnapTarget(windowID: 2, frame: CGRect(x: 100, y: 100, width: 400, height: 300), zOrder: 1)
        ]

        XCTAssertEqual(
            WindowSnapTargetSelector.target(at: CGPoint(x: 200, y: 200), from: targets)?.windowID,
            2
        )
    }

    func testSmallestWindowWinsWhenZOrderMatches() {
        let targets = [
            WindowSnapTarget(windowID: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), zOrder: 1),
            WindowSnapTarget(windowID: 2, frame: CGRect(x: 100, y: 100, width: 200, height: 120), zOrder: 1)
        ]

        XCTAssertEqual(
            WindowSnapTargetSelector.target(at: CGPoint(x: 150, y: 150), from: targets)?.windowID,
            2
        )
    }

    func testWindowCandidatesAreRestrictedToFrontmostApplication() {
        XCTAssertTrue(WindowSnapSnapshotPolicy.includes(ownerProcessID: 200, frontmostProcessID: 200))
        XCTAssertFalse(WindowSnapSnapshotPolicy.includes(ownerProcessID: 100, frontmostProcessID: 200))
    }

    @MainActor
    func testClickingHoveredWindowUsesSnappedFrame() throws {
        let target = WindowSnapTarget(
            windowID: 42,
            frame: CGRect(x: 100, y: 120, width: 320, height: 240),
            zOrder: 0
        )
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.showsActionToolbar = false
        view.configureSnapTargets([target])
        var selectedRect: CGRect?
        view.onFinish = { rect, _ in selectedRect = rect }

        view.mouseMoved(with: try mouseEvent(type: .mouseMoved, point: CGPoint(x: 200, y: 200)))
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: CGPoint(x: 200, y: 200)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: CGPoint(x: 200, y: 200)))

        XCTAssertEqual(selectedRect, target.frame.integral)
    }

    @MainActor
    func testTinyClickOutsideSnapTargetDoesNotCancelCapture() throws {
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        var didFinish = false
        view.onFinish = { _, _ in didFinish = true }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: CGPoint(x: 700, y: 500)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: CGPoint(x: 701, y: 501)))

        XCTAssertFalse(didFinish)
    }

    @MainActor
    func testManualDragOverridesHoveredWindowCandidate() throws {
        let target = WindowSnapTarget(
            windowID: 42,
            frame: CGRect(x: 100, y: 100, width: 500, height: 350),
            zOrder: 0
        )
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.showsActionToolbar = false
        view.configureSnapTargets([target])
        var selectedRect: CGRect?
        view.onFinish = { rect, _ in selectedRect = rect }

        view.mouseMoved(with: try mouseEvent(type: .mouseMoved, point: CGPoint(x: 150, y: 150)))
        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: CGPoint(x: 150, y: 150)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, point: CGPoint(x: 360, y: 280)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: CGPoint(x: 360, y: 280)))

        XCTAssertEqual(selectedRect, CGRect(x: 150, y: 150, width: 210, height: 130))
    }

    @MainActor
    func testOverlayAcceptsTheActivationClick() {
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))

        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }

    func testToolbarOrderMatchesRightToLeftProductOrder() {
        XCTAssertEqual(
            CaptureActionToolbarLayout.actions.map(\.action),
            [.beautify, .multimodal, .localOCR, .translate, .edit, .pin, .copyImage, .save]
        )
    }

    func testSelectionCanMoveWithoutLeavingScreenBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let original = CGRect(x: 100, y: 120, width: 320, height: 240)

        XCTAssertEqual(
            SelectionRectEditor.moved(original, by: CGPoint(x: 80, y: 40), inside: bounds),
            CGRect(x: 180, y: 160, width: 320, height: 240)
        )
        XCTAssertEqual(
            SelectionRectEditor.moved(original, by: CGPoint(x: 900, y: 900), inside: bounds),
            CGRect(x: 480, y: 360, width: 320, height: 240)
        )
    }

    func testSelectionCanResizeFromEveryEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let original = CGRect(x: 100, y: 120, width: 320, height: 240)

        XCTAssertEqual(
            SelectionRectEditor.resized(
                original,
                handle: .right,
                to: CGPoint(x: 510, y: 240),
                inside: bounds
            ),
            CGRect(x: 100, y: 120, width: 410, height: 240)
        )
        XCTAssertEqual(
            SelectionRectEditor.resized(
                original,
                handle: .bottomLeft,
                to: CGPoint(x: 40, y: 60),
                inside: bounds
            ),
            CGRect(x: 40, y: 60, width: 380, height: 300)
        )
    }

    func testResizeHitTargetsCoverCornersAndEntireEdges() {
        let rect = CGRect(x: 100, y: 120, width: 320, height: 240)

        XCTAssertEqual(SelectionRectEditor.resizeHandle(at: CGPoint(x: 100, y: 360), for: rect), .topLeft)
        XCTAssertEqual(SelectionRectEditor.resizeHandle(at: CGPoint(x: 260, y: 360), for: rect), .top)
        XCTAssertEqual(SelectionRectEditor.resizeHandle(at: CGPoint(x: 420, y: 220), for: rect), .right)
        XCTAssertEqual(SelectionRectEditor.resizeHandle(at: CGPoint(x: 260, y: 120), for: rect), .bottom)
        XCTAssertEqual(SelectionRectEditor.resizeHandle(at: CGPoint(x: 100, y: 220), for: rect), .left)
        XCTAssertNil(SelectionRectEditor.resizeHandle(at: CGPoint(x: 260, y: 220), for: rect))
    }

    @MainActor
    func testSelectionCanResizeByDraggingAnEdge() throws {
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.showsActionToolbar = true
        view.showPresetSelection(CGRect(x: 100, y: 120, width: 320, height: 240))
        var selectedRect: CGRect?
        view.onFinish = { rect, _ in selectedRect = rect }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: CGPoint(x: 420, y: 220)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, point: CGPoint(x: 510, y: 220)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: CGPoint(x: 510, y: 220)))
        view.mouseDown(with: try mouseEvent(
            type: .leftMouseDown,
            point: CGPoint(x: 300, y: 220),
            clickCount: 2
        ))

        XCTAssertEqual(selectedRect, CGRect(x: 100, y: 120, width: 410, height: 240))
    }

    @MainActor
    func testTinyInitialDragNeverRegistersInvalidCursorRects() throws {
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.showsActionToolbar = true

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: CGPoint(x: 100, y: 100)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, point: CGPoint(x: 105, y: 105)))

        // AppKit aborts the process when addCursorRect receives an empty or
        // negative-sized rectangle, so reaching this assertion is the regression check.
        view.resetCursorRects()
        XCTAssertTrue(true)
    }

    @MainActor
    func testToolbarUsesTopmostCustomTooltipAndPointingHandButtons() throws {
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.showsActionToolbar = true
        view.showPresetSelection(CGRect(x: 100, y: 120, width: 500, height: 300))
        let button = try XCTUnwrap(descendants(of: view).compactMap { $0 as? CaptureActionButton }.first)
        let toolbar = try XCTUnwrap(view.subviews.first {
            $0.identifier?.rawValue == "capture-action-toolbar"
        })
        let toolbarCenter = CGPoint(x: toolbar.frame.midX, y: toolbar.frame.midY)

        XCTAssertNil(button.toolTip)
        XCTAssertTrue(view.cursor(at: toolbarCenter) === NSCursor.pointingHand)
        view.mouseMoved(with: try mouseEvent(type: .mouseMoved, point: toolbarCenter))
        XCTAssertTrue(NSCursor.current === NSCursor.pointingHand)
        button.mouseEntered(with: try enterExitEvent(type: .mouseEntered))

        let tooltip = try XCTUnwrap(view.subviews.first {
            $0.identifier?.rawValue == "capture-action-tooltip"
        })
        XCTAssertTrue(view.subviews.last === tooltip)
        XCTAssertEqual(tooltip.layer?.zPosition, 10_000)

        button.mouseExited(with: try enterExitEvent(type: .mouseExited))
        XCTAssertFalse(view.subviews.contains { $0.identifier?.rawValue == "capture-action-tooltip" })
    }

    @MainActor
    func testPresetSelectionCanBeMovedBeforeChoosingAnAction() throws {
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.showsActionToolbar = true
        view.showPresetSelection(CGRect(x: 100, y: 120, width: 320, height: 240))
        var selectedRect: CGRect?
        view.onFinish = { rect, _ in selectedRect = rect }

        view.mouseDown(with: try mouseEvent(type: .leftMouseDown, point: CGPoint(x: 250, y: 220)))
        view.mouseDragged(with: try mouseEvent(type: .leftMouseDragged, point: CGPoint(x: 300, y: 250)))
        view.mouseUp(with: try mouseEvent(type: .leftMouseUp, point: CGPoint(x: 300, y: 250)))
        view.mouseDown(with: try mouseEvent(
            type: .leftMouseDown,
            point: CGPoint(x: 300, y: 250),
            clickCount: 2
        ))

        XCTAssertEqual(selectedRect, CGRect(x: 150, y: 150, width: 320, height: 240))
    }

    @MainActor
    private func mouseEvent(
        type: NSEvent.EventType,
        point: CGPoint,
        clickCount: Int = 1
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: clickCount,
            pressure: 1
        ))
    }

    @MainActor
    private func enterExitEvent(type: NSEvent.EventType) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(
            with: type,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            trackingNumber: 1,
            userData: nil
        ))
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }
}
