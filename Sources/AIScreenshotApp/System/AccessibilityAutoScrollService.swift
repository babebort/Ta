import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics

struct AccessibilityScrollProgress: Equatable {
    let value: Double
    let minimum: Double
    let maximum: Double

    var normalizedValue: Double {
        guard maximum > minimum else { return 0 }
        return min(1, max(0, (value - minimum) / (maximum - minimum)))
    }

    var isAtEnd: Bool {
        normalizedValue >= 0.9995
    }
}

struct AccessibilityScrollTarget {
    enum Mode: Equatable {
        case accessibilityTracked
        case eventFallback
    }

    let sourceProcessID: pid_t?
    let eventLocation: CGPoint
    let scrollContainer: AXUIElement?
    let verticalScrollBar: AXUIElement?

    var mode: Mode {
        // A scrollbar that cannot report its range/value would make the state
        // machine show "tracked" while every bottom check silently falls back
        // to image matching. Only advertise tracking when the contract works.
        verticalScrollBar == nil ? .eventFallback : .accessibilityTracked
    }
}

enum AccessibilityAutoScrollService {
    static let maximumPixelDeltaPerEvent = 32
    static let scrollEventIntervalMilliseconds = 14
    static var isGranted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func request() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func resolveTarget(for selection: CaptureSelection) -> AccessibilityScrollTarget {
        let eventLocation = scrollTargetLocation(for: selection)
        guard isGranted else {
            return AccessibilityScrollTarget(
                sourceProcessID: selection.sourceApplicationProcessID,
                eventLocation: eventLocation,
                scrollContainer: nil,
                verticalScrollBar: nil
            )
        }

        let systemWide = AXUIElementCreateSystemWide()
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(eventLocation.x),
            Float(eventLocation.y),
            &hitElement
        ) == .success,
        let hitElement else {
            return AccessibilityScrollTarget(
                sourceProcessID: selection.sourceApplicationProcessID,
                eventLocation: eventLocation,
                scrollContainer: nil,
                verticalScrollBar: nil
            )
        }

        var hitPID: pid_t = 0
        AXUIElementGetPid(hitElement, &hitPID)
        guard selection.sourceApplicationProcessID == nil
                || selection.sourceApplicationProcessID == hitPID else {
            return AccessibilityScrollTarget(
                sourceProcessID: selection.sourceApplicationProcessID,
                eventLocation: eventLocation,
                scrollContainer: nil,
                verticalScrollBar: nil
            )
        }

        var current: AXUIElement? = hitElement
        var visited = 0
        while let element = current, visited < 32 {
            if let scrollBar = copyElementAttribute(
                element,
                attribute: kAXVerticalScrollBarAttribute as String
            ) {
                let candidate = AccessibilityScrollTarget(
                    sourceProcessID: selection.sourceApplicationProcessID,
                    eventLocation: eventLocation,
                    scrollContainer: element,
                    verticalScrollBar: scrollBar
                )
                if progress(of: candidate) != nil {
                    return candidate
                }
            }

            let role = copyStringAttribute(element, attribute: kAXRoleAttribute as String)
            if role == kAXScrollAreaRole as String,
               let scrollBar = findVerticalScrollBar(in: element, maximumDepth: 2) {
                let candidate = AccessibilityScrollTarget(
                    sourceProcessID: selection.sourceApplicationProcessID,
                    eventLocation: eventLocation,
                    scrollContainer: element,
                    verticalScrollBar: scrollBar
                )
                if progress(of: candidate) != nil {
                    return candidate
                }
            }

            current = copyElementAttribute(element, attribute: kAXParentAttribute as String)
            visited += 1
        }

        return AccessibilityScrollTarget(
            sourceProcessID: selection.sourceApplicationProcessID,
            eventLocation: eventLocation,
            scrollContainer: hitElement,
            verticalScrollBar: nil
        )
    }

    static func progress(of target: AccessibilityScrollTarget) -> AccessibilityScrollProgress? {
        guard let scrollBar = target.verticalScrollBar,
              let value = copyNumberAttribute(scrollBar, attribute: kAXValueAttribute as String) else {
            return nil
        }
        let minimum = copyNumberAttribute(scrollBar, attribute: kAXMinValueAttribute as String) ?? 0
        let maximum = copyNumberAttribute(scrollBar, attribute: kAXMaxValueAttribute as String) ?? 1
        guard maximum > minimum else { return nil }
        return AccessibilityScrollProgress(value: value, minimum: minimum, maximum: maximum)
    }

    static func postDownwardScroll(
        in selection: CaptureSelection,
        target: AccessibilityScrollTarget? = nil,
        pixels: Int = 260
    ) async -> Bool {
        await postVerticalScroll(in: selection, target: target, pixelsDown: abs(pixels))
    }

    @discardableResult
    static func postVerticalScroll(
        in selection: CaptureSelection,
        target: AccessibilityScrollTarget? = nil,
        pixelsDown: Int
    ) async -> Bool {
        guard isGranted else { return false }
        // AX scrollbars are observation-only. Their value is frequently a
        // normalized 0...1 fraction rather than a pixel offset, so adding a
        // 300-pixel capture step jumps straight to the maximum in Chromium and
        // Electron. Use AX only to track progress/bottom and deliver the actual
        // motion through a normal wheel gesture at the locked hit point.
        let location = target?.eventLocation ?? scrollTargetLocation(for: selection)
        let source = CGEventSource(stateID: .hidSystemState)
        let deltas = pixelDeltas(for: pixelsDown)
        for (index, pixelDelta) in deltas.enumerated() {
            guard let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 1,
                wheel1: pixelDelta,
                wheel2: 0,
                wheel3: 0
            ) else { return false }
            event.location = location
            event.post(tap: .cghidEventTap)
            if index < deltas.count - 1 {
                try? await Task.sleep(for: .milliseconds(scrollEventIntervalMilliseconds))
            }
        }
        return true
    }

    static func progressAdvanced(
        from before: AccessibilityScrollProgress?,
        to after: AccessibilityScrollProgress?,
        tolerance: Double = 0.000_05
    ) -> Bool {
        guard let before, let after else { return false }
        return after.normalizedValue > before.normalizedValue + tolerance
    }

    static func pixelDeltas(for requestedPixels: Int) -> [Int32] {
        var remaining = max(1, abs(requestedPixels))
        var deltas: [Int32] = []
        let wheelSign: Int32 = requestedPixels >= 0 ? -1 : 1
        while remaining > 0 {
            let step = min(maximumPixelDeltaPerEvent, remaining)
            deltas.append(wheelSign * Int32(step))
            remaining -= step
        }
        return deltas
    }

    static func scrollTargetLocation(for selection: CaptureSelection) -> CGPoint {
        let displayBounds = CGDisplayBounds(selection.displayID)
        return CGPoint(
            x: displayBounds.minX + selection.globalRect.midX - selection.screenFrame.minX,
            y: displayBounds.minY + selection.screenFrame.maxY - selection.globalRect.midY
        )
    }

    private static func findVerticalScrollBar(
        in element: AXUIElement,
        maximumDepth: Int
    ) -> AXUIElement? {
        guard maximumDepth >= 0 else { return nil }
        if copyStringAttribute(element, attribute: kAXRoleAttribute as String) == kAXScrollBarRole as String {
            let orientation = copyStringAttribute(element, attribute: kAXOrientationAttribute as String)
            if orientation == kAXVerticalOrientationValue as String || orientation == nil {
                return element
            }
        }
        guard maximumDepth > 0,
              let children = copyElementArrayAttribute(
                element,
                attribute: kAXChildrenAttribute as String
              ) else { return nil }
        for child in children {
            if let result = findVerticalScrollBar(in: child, maximumDepth: maximumDepth - 1) {
                return result
            }
        }
        return nil
    }

    private static func copyElementAttribute(
        _ element: AXUIElement,
        attribute: String
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
    }

    private static func copyElementArrayAttribute(
        _ element: AXUIElement,
        attribute: String
    ) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [Any] else { return nil }
        return array.compactMap { item in
            let object = item as CFTypeRef
            guard CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(object as AnyObject, to: AXUIElement.self)
        }
    }

    private static func copyStringAttribute(
        _ element: AXUIElement,
        attribute: String
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func copyNumberAttribute(
        _ element: AXUIElement,
        attribute: String
    ) -> Double? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.doubleValue
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
