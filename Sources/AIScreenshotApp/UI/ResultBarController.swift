import AppKit
import SwiftUI

@MainActor
final class ResultBarController {
    private var panel: NSPanel?
    private var dismissalTask: Task<Void, Never>?

    func show(_ state: ResultBarState, autoHide: Bool) {
        dismissalTask?.cancel()

        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(
            rootView: ResultBarView(state: state) { [weak self] in
                self?.hide()
            }
        )
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel

        // Processing states remain visible until they are replaced. Every final
        // state eventually leaves the screen, even when a caller asks for a
        // longer-lived error that the user may want time to read.
        guard autoHide || state.kind != .processing else { return }
        let duration = UserDefaults.standard.double(forKey: "resultBarDuration")
        let preferredSeconds = duration > 0 ? duration : 3
        let seconds = autoHide ? preferredSeconds : max(preferredSeconds, 6)
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissalTask?.cancel()
        dismissalTask = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 390, height: 54),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = false
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.minY + 28
        ))
    }
}
