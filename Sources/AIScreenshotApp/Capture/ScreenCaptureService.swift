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
            return "Could not find the matching display. Please select again."
        case .windowUnavailable:
            return "Could not find the matching window. Please select again."
        case .invalidSelection:
            return "The selection is invalid. Please re-select the area."
        }
    }
}

enum FrozenDisplayCropper {
    static func pixelRect(
        for selection: CaptureSelection,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect {
        let clipped = selection.globalRect.intersection(selection.screenFrame)
        guard clipped.width >= 1,
              clipped.height >= 1,
              selection.screenFrame.width > 0,
              selection.screenFrame.height > 0,
              imageWidth > 0,
              imageHeight > 0 else {
            return .null
        }

        let scaleX = CGFloat(imageWidth) / selection.screenFrame.width
        let scaleY = CGFloat(imageHeight) / selection.screenFrame.height
        let localX = clipped.minX - selection.screenFrame.minX
        let localTop = selection.screenFrame.maxY - clipped.maxY
        let pixels = CGRect(
            x: localX * scaleX,
            y: localTop * scaleY,
            width: clipped.width * scaleX,
            height: clipped.height * scaleY
        ).integral
        return pixels.intersection(
            CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        )
    }

    static func crop(_ image: CGImage, to selection: CaptureSelection) throws -> CGImage {
        let pixelRect = pixelRect(
            for: selection,
            imageWidth: image.width,
            imageHeight: image.height
        )
        guard !pixelRect.isNull,
              pixelRect.width >= 1,
              pixelRect.height >= 1,
              let cropped = image.cropping(to: pixelRect) else {
            throw ScreenCaptureError.invalidSelection
        }
        return cropped
    }
}

struct ScreenCaptureService: Sendable {
    func capture(_ selection: CaptureSelection) async throws -> CGImage {
        if let frozenDisplayImage = selection.frozenDisplayImage {
            return try FrozenDisplayCropper.crop(frozenDisplayImage, to: selection)
        }

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
        pixelScale: CGFloat,
        showsCursor: Bool = false
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureError.windowUnavailable
        }
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
