import AppKit
import CoreGraphics
import AIScreenshotCore

struct CaptureSelection: @unchecked Sendable {
    let globalRect: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID
    let backingScaleFactor: CGFloat
    let excludedWindowIDs: [CGWindowID]
    let sourceApplicationProcessID: pid_t?

    init(
        globalRect: CGRect,
        screenFrame: CGRect,
        displayID: CGDirectDisplayID,
        backingScaleFactor: CGFloat,
        excludedWindowIDs: [CGWindowID] = [],
        sourceApplicationProcessID: pid_t? = nil
    ) {
        self.globalRect = globalRect
        self.screenFrame = screenFrame
        self.displayID = displayID
        self.backingScaleFactor = backingScaleFactor
        self.excludedWindowIDs = excludedWindowIDs
        self.sourceApplicationProcessID = sourceApplicationProcessID
    }
}

@MainActor
final class SelectionOverlayController {
    private var panel: SelectionOverlayPanel?
    private var eventMonitor: Any?
    private var isStarting = false
    private var isFinishing = false

    func begin(
        showsActionToolbar: Bool,
        presetRect: CGRect? = nil,
        completion: @escaping (CaptureSelection?, CaptureQuickAction?) -> Void
    ) {
        guard panel == nil, !isStarting else { return }
        isStarting = true
        isFinishing = false

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let displayID = CGDirectDisplayID(screenNumber?.uint32Value ?? 0)
        let sourceProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let targets = WindowSnapService().targets(
            on: screen,
            frontmostProcessID: sourceProcessID
        )

        showPanel(
            screen: screen,
            displayID: displayID,
            sourceProcessID: sourceProcessID,
            snapTargets: targets,
            showsActionToolbar: showsActionToolbar,
            presetRect: presetRect,
            completion: completion
        )
    }

    private func showPanel(
        screen: NSScreen,
        displayID: CGDirectDisplayID,
        sourceProcessID: pid_t?,
        snapTargets: [WindowSnapTarget],
        showsActionToolbar: Bool,
        presetRect: CGRect?,
        completion: @escaping (CaptureSelection?, CaptureQuickAction?) -> Void
    ) {
        guard panel == nil else { return }
        isStarting = false

        let panel = SelectionOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false

        let overlay = SelectionOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        overlay.showsActionToolbar = showsActionToolbar
        overlay.onFinish = { [weak self, weak panel, weak overlay] localRect, action in
            guard let self, let panel else { return }
            let globalRect = localRect.map { panel.convertToScreen($0) }
            if let globalRect {
                let selection = CaptureSelection(
                    globalRect: globalRect,
                    screenFrame: screen.frame,
                    displayID: displayID,
                    backingScaleFactor: screen.backingScaleFactor,
                    excludedWindowIDs: [CGWindowID(panel.windowNumber)],
                    sourceApplicationProcessID: sourceProcessID
                )
                if action == .edit {
                    overlay?.prepareForDeferredDismissal()
                } else {
                    finish()
                }
                completion(selection, action)
            } else {
                finish()
                completion(nil, nil)
            }
        }
        panel.contentView = overlay
        self.panel = panel
        isFinishing = false

        let targets = snapTargets.map { target in
            WindowSnapTarget(
                windowID: target.windowID,
                frame: panel.convertFromScreen(target.frame),
                zOrder: target.zOrder
            )
        }
        overlay.configureSnapTargets(targets)

        if let presetRect {
            overlay.showPresetSelection(presetRect.intersection(overlay.bounds))
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak overlay, weak panel] event in
            guard event.window === panel else { return event }
            overlay?.cancelSelection()
            return nil
        }

        // Keep the current app and Space untouched. This panel captures input
        // without making Ta the active application.
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(overlay)
    }

    func dismiss() {
        finish()
    }

    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        isStarting = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

private final class SelectionOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
