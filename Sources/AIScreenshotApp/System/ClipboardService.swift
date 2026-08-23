import AppKit
import AIScreenshotCore

@MainActor
struct ClipboardService {
    private let pasteboard = NSPasteboard.general
    private let policy = ClipboardCommitPolicy()

    var changeCount: Int { pasteboard.changeCount }

    func copyText(
        _ text: String,
        initialChangeCount: Int,
        jobIsLatest: Bool
    ) -> Bool {
        guard policy.shouldCommit(
            initialChangeCount: initialChangeCount,
            currentChangeCount: pasteboard.changeCount,
            jobIsLatest: jobIsLatest
        ) else {
            return false
        }

        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    func copyImage(
        _ image: CGImage,
        initialChangeCount: Int,
        jobIsLatest: Bool
    ) -> Bool {
        guard policy.shouldCommit(
            initialChangeCount: initialChangeCount,
            currentChangeCount: pasteboard.changeCount,
            jobIsLatest: jobIsLatest
        ) else {
            return false
        }

        let representation = NSBitmapImageRep(cgImage: image)
        guard let png = representation.representation(using: .png, properties: [:]) else {
            return false
        }

        pasteboard.clearContents()
        return pasteboard.setData(png, forType: .png)
    }
}
