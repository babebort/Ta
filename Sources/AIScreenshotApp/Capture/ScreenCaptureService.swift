@preconcurrency import ScreenCaptureKit
import AppKit
import CoreGraphics

enum ScreenCaptureError: LocalizedError {
    case displayUnavailable
    case invalidSelection

    var errorDescription: String? {
        switch self {
        case .displayUnavailable:
            return "找不到对应的显示器，请重新选择。"
        case .invalidSelection:
            return "选区无效，请重新框选。"
        }
    }
}

struct ScreenCaptureService {
    func capture(_ selection: CaptureSelection) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw ScreenCaptureError.displayUnavailable
        }

        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == ownProcessID }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )

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

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = localRect
        configuration.width = max(1, Int((localRect.width * scale).rounded()))
        configuration.height = max(1, Int((localRect.height * scale).rounded()))
        configuration.scalesToFit = false
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }
}
