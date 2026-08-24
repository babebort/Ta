import AppKit
import XCTest
@testable import AIScreenshotApp

final class WindowSnapAndSelectionTests: XCTestCase {
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

    @MainActor
    private func mouseEvent(type: NSEvent.EventType, point: CGPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
    }
}
