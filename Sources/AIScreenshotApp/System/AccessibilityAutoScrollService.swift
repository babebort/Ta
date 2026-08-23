import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics

enum AccessibilityAutoScrollService {
    static let standardWheelBurstCount = 2
    static var isGranted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func request() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func postDownwardScroll(in selection: CaptureSelection, pixels: Int = 260) -> Bool {
        guard isGranted else { return false }
        let location = scrollTargetLocation(for: selection)
        let originalPointerLocation = CGEvent(source: nil)?.location ?? location
        let source = CGEventSource(stateID: .hidSystemState)
        let wheelLines = recommendedWheelLines(for: pixels)
        // WebView/Electron apps often ignore scroll-wheel events posted directly
        // to their PID. Post through HID for compatibility, then restore the
        // pointer only if it is still at our synthetic location. This avoids
        // overwriting genuine mouse movement that happens concurrently.
        for _ in 0..<standardWheelBurstCount {
            guard let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .line,
                wheelCount: 1,
                wheel1: Int32(-wheelLines),
                wheel2: 0,
                wheel3: 0
            ) else { return false }
            event.location = location
            event.post(tap: .cghidEventTap)
        }
        restorePointerIfOwned(
            original: originalPointerLocation,
            synthetic: location
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(12)) {
            restorePointerIfOwned(
                original: originalPointerLocation,
                synthetic: location
            )
        }
        return true
    }

    static func recommendedWheelLines(for requestedPixels: Int) -> Int {
        min(10, max(3, abs(requestedPixels) / 48))
    }

    static func scrollTargetLocation(for selection: CaptureSelection) -> CGPoint {
        let displayBounds = CGDisplayBounds(selection.displayID)
        return CGPoint(
            x: displayBounds.minX + selection.globalRect.midX - selection.screenFrame.minX,
            y: displayBounds.minY + selection.screenFrame.maxY - selection.globalRect.midY
        )
    }

    static func pointerRestorationPoint(
        original: CGPoint,
        current: CGPoint,
        synthetic: CGPoint,
        tolerance: CGFloat = 3
    ) -> CGPoint? {
        let distance = hypot(current.x - synthetic.x, current.y - synthetic.y)
        return distance <= tolerance ? original : nil
    }

    private static func restorePointerIfOwned(original: CGPoint, synthetic: CGPoint) {
        guard let current = CGEvent(source: nil)?.location,
              let restorationPoint = pointerRestorationPoint(
                original: original,
                current: current,
                synthetic: synthetic
              ) else {
            return
        }
        CGWarpMouseCursorPosition(restorationPoint)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
