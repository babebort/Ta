import AppKit
import CoreGraphics
import AIScreenshotCore

struct CaptureSelection: Sendable {
    let globalRect: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID
    let backingScaleFactor: CGFloat
}

@MainActor
final class SelectionOverlayController {
    private var panel: SelectionOverlayPanel?
    private weak var previousApplication: NSRunningApplication?

    func begin(
        showsActionToolbar: Bool,
        presetRect: CGRect? = nil,
        completion: @escaping (CaptureSelection?, CaptureQuickAction?) -> Void
    ) {
        guard panel == nil else { return }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        previousApplication = NSWorkspace.shared.frontmostApplication

        let panel = SelectionOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none

        let overlay = SelectionOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        overlay.showsActionToolbar = showsActionToolbar
        overlay.onFinish = { [weak self, weak panel] localRect, action in
            guard let self, let panel else { return }
            let globalRect = localRect.map { panel.convertToScreen($0) }
            finish()
            if let globalRect {
                let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                completion(CaptureSelection(
                    globalRect: globalRect,
                    screenFrame: screen.frame,
                    displayID: CGDirectDisplayID(screenNumber?.uint32Value ?? 0),
                    backingScaleFactor: screen.backingScaleFactor
                ), action)
            } else {
                completion(nil, nil)
            }
        }
        panel.contentView = overlay
        self.panel = panel

        if let presetRect {
            overlay.showPresetSelection(presetRect.intersection(overlay.bounds))
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(overlay)
    }

    private func finish() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        previousApplication?.activate(options: [])
    }
}

private final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
