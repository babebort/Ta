import AppKit
import SwiftUI
import AIScreenshotCore

struct MenuBarContentView: View {
    @ObservedObject var appModel: AppModel
    @State private var shortcuts = HotKeyPreferences().allShortcuts()

    var body: some View {
        ZStack {
            TaPalette.paper

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    TaAppIcon(size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TaBrand.name)
                            .font(.system(.headline, design: .serif, weight: .bold))
                            .foregroundStyle(TaPalette.ink)
                        Label(appModel.statusText, systemImage: "lock.shield.fill")
                            .font(.caption)
                            .foregroundStyle(TaPalette.mutedInk)
                    }
                    Spacer()
                    Text("Local First")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(TaPalette.mutedInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(TaPalette.elevatedPaper, in: Capsule())
                        .overlay { Capsule().stroke(TaPalette.hairline) }
                }
                .padding(14)

                Divider()

                VStack(spacing: 5) {
                    MenuActionButton(
                        title: "Start Capture",
                        subtitle: "After capturing, extract text, copy, pin, or edit",
                        shortcut: shortcutText(for: .interactiveCapture),
                        symbol: "viewfinder",
                        emphasized: true
                    ) {
                        appModel.startCapture(.interactive)
                    }

                    MenuActionButton(
                        title: "Quick Recognition",
                        subtitle: "Uses OCR or multimodal based on settings",
                        shortcut: shortcutText(for: .intelligentCapture),
                        symbol: "text.viewfinder"
                    ) {
                        appModel.startCapture(.intelligent)
                    }

                    MenuActionButton(
                        title: "Screenshot Translation",
                        subtitle: "Recognize, translate, and copy text",
                        shortcut: shortcutText(for: .translationCapture),
                        symbol: "character.book.closed"
                    ) {
                        appModel.startCapture(.translation)
                    }

                    MenuActionButton(
                        title: "Capture Image",
                        subtitle: "Always copies the original image",
                        shortcut: shortcutText(for: .imageCapture),
                        symbol: "rectangle.dashed"
                    ) {
                        appModel.startCapture(.image)
                    }

                    MenuActionButton(
                        title: "Capture and Pin",
                        subtitle: "Stays on top of other windows",
                        shortcut: shortcutText(for: .pinCapture),
                        symbol: "pin.fill"
                    ) {
                        appModel.startCapture(.pin)
                    }

                    MenuActionButton(
                        title: "Long Screenshot",
                        subtitle: "For browsers, WeChat, and AI conversations",
                        shortcut: shortcutText(for: .longCapture),
                        symbol: "rectangle.and.arrow.up.right.and.arrow.down.left"
                    ) {
                        appModel.startCapture(.long)
                    }
                }
                .padding(6)

                Divider()

                VStack(alignment: .leading, spacing: 7) {
                    Text("Pin Management")
                        .font(.caption.bold())
                        .foregroundStyle(TaPalette.mutedInk)
                    HStack(spacing: 10) {
                        Button("Pin Clipboard") { appModel.pinClipboardContent() }
                        Button("Hide All") { appModel.hideAllPins() }
                        Button("Show All") { appModel.showAllPins() }
                    }
                    .buttonStyle(.link)
                    HStack(spacing: 10) {
                        Button("Restore Click-Through") { appModel.restorePinInteraction() }
                        Button("Restore Last Closed") { appModel.restoreLastClosedPin() }
                    }
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                HStack {
                    Button {
                        appModel.showWelcome()
                    } label: {
                        Label("Open Main Window", systemImage: "macwindow")
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(height: 14)

                    Button {
                        appModel.showSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(AIScreenshotCore.version)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
        }
        .frame(width: 326)
        .tint(TaPalette.cinnabar)
        .task {
            appModel.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: HotKeyPreferences.didChangeNotification)) { _ in
            shortcuts = HotKeyPreferences().allShortcuts()
        }
    }

    private func shortcutText(for action: GlobalHotKeyAction) -> String {
        (shortcuts[action] ?? action.defaultShortcut).displayText
    }
}

private struct MenuActionButton: View {
    let title: String
    let subtitle: String
    let shortcut: String
    let symbol: String
    var emphasized = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(emphasized ? TaPalette.paper : TaPalette.cinnabar)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(emphasized ? TaPalette.paper : TaPalette.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(emphasized ? TaPalette.paper.opacity(0.62) : TaPalette.mutedInk)
                }
                Spacer()
                Text(shortcut)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(emphasized ? TaPalette.paper.opacity(0.72) : TaPalette.mutedInk)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                emphasized
                    ? TaPalette.ink.opacity(isHovering ? 0.92 : 1)
                    : TaPalette.cinnabar.opacity(isHovering ? 0.07 : 0),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if emphasized {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(TaPalette.cinnabar.opacity(isHovering ? 0.58 : 0.20))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
