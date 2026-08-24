import AppKit
import CoreGraphics

struct WindowSnapTarget: Equatable, Sendable {
    let windowID: CGWindowID
    let frame: CGRect
    let zOrder: Int
}

enum WindowSnapTargetSelector {
    static func target(at point: CGPoint, from targets: [WindowSnapTarget]) -> WindowSnapTarget? {
        targets
            .filter { $0.frame.contains(point) }
            .min { lhs, rhs in
                if lhs.zOrder != rhs.zOrder { return lhs.zOrder < rhs.zOrder }
                return lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
            }
    }
}

enum WindowSnapSnapshotPolicy {
    static func includes(ownerProcessID: pid_t, frontmostProcessID: pid_t?) -> Bool {
        guard let frontmostProcessID else { return true }
        return ownerProcessID == frontmostProcessID
    }
}

@MainActor
struct WindowSnapService {
    func targets(on screen: NSScreen, frontmostProcessID: pid_t?) -> [WindowSnapTarget] {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        return windowInfo.enumerated().compactMap { index, info in
            guard let number = info[kCGWindowNumber as String] as? NSNumber,
                  let ownerProcessID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let boundsDictionary = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let quartzFrame = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer >= 0 else {
                return nil
            }
            guard WindowSnapSnapshotPolicy.includes(
                ownerProcessID: ownerProcessID,
                frontmostProcessID: frontmostProcessID
            ) else { return nil }

            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01, quartzFrame.width >= 24, quartzFrame.height >= 16 else {
                return nil
            }

            let appKitFrame = CGRect(
                x: quartzFrame.minX,
                y: primaryTop - quartzFrame.maxY,
                width: quartzFrame.width,
                height: quartzFrame.height
            ).intersection(screen.frame)
            guard appKitFrame.width >= 24, appKitFrame.height >= 16 else { return nil }

            return WindowSnapTarget(
                windowID: CGWindowID(number.uint32Value),
                frame: appKitFrame.integral,
                zOrder: index
            )
        }
    }
}
