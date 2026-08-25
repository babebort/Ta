@preconcurrency import ScreenCaptureKit
import AppKit
import CoreGraphics

enum ScreenCaptureError: LocalizedError {
    case displayUnavailable
    case windowUnavailable
    case invalidSelection

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "找不到对应的显示器，请重新选择。"
        case .windowUnavailable:
            return "找不到对应的窗口，请重新选择。"
        case .invalidSelection:
            return "选区无效，请重新框选。"
        }
    }
}

struct ScreenCaptureService: Sendable {
    func capture(_ selection: CaptureSelection) async throws -> CGImage {
        let screenFrame = selection.screenFrame
        let clipped = selection.globalRect.intersection(screenFrame)
        guard clipped.width >= 1, clipped.height >= 1 else {
            throw ScreenCaptureError.invalidSelection
        }

        let localRect = CGRect(
            x: clipped.minX - screenFrame.minX,
            y: screenFrame.maxY - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        )
        let scale = selection.backingScaleFactor

        return try await captureDisplay(
            displayID: selection.displayID,
            sourceRect: localRect,
            pixelScale: scale,
            excludedWindowIDs: selection.excludedWindowIDs,
            showsCursor: false
        )
    }

    func captureDisplay(
        displayID: CGDirectDisplayID,
        sourceRect: CGRect? = nil,
        pixelScale: CGFloat,
        excludedWindowIDs: [CGWindowID] = [],
        showsCursor: Bool = false
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenCaptureError.displayUnavailable
        }
        let excludedIDs = Set(excludedWindowIDs)
        let excludedWindows = content.windows.filter { excludedIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let captureRect = sourceRect ?? CGRect(origin: .zero, size: display.frame.size)
        guard captureRect.width >= 1, captureRect.height >= 1 else {
            throw ScreenCaptureError.invalidSelection
        }
        let configuration = Self.configuration(
            size: captureRect.size,
            sourceRect: sourceRect,
            pixelScale: pixelScale,
            showsCursor: showsCursor,
            ignoreWindowShadows: true
        )

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    func captureWindow(
        windowID: CGWindowID,
        showsCursor: Bool = false
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureError.windowUnavailable
        }
        let pixelScale = content.displays
            .filter { $0.frame.intersects(window.frame) && $0.frame.width > 0 }
            .map { CGFloat($0.width) / $0.frame.width }
            .max() ?? 1
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = Self.configuration(
            size: window.frame.size,
            sourceRect: nil,
            pixelScale: max(1, pixelScale),
            showsCursor: showsCursor,
            ignoreWindowShadows: true
        )

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private static func configuration(
        size: CGSize,
        sourceRect: CGRect?,
        pixelScale: CGFloat,
        showsCursor: Bool,
        ignoreWindowShadows: Bool
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        if let sourceRect { configuration.sourceRect = sourceRect }
        configuration.width = max(1, Int((size.width * pixelScale).rounded()))
        configuration.height = max(1, Int((size.height * pixelScale).rounded()))
        configuration.scalesToFit = false
        configuration.showsCursor = showsCursor
        configuration.ignoreShadowsSingleWindow = ignoreWindowShadows
        return configuration
    }
}
