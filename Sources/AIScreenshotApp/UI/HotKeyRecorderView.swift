import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorderView: NSViewRepresentable {
    let shortcut: HotKeyShortcut
    let onChange: (HotKeyShortcut) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> HotKeyRecorderButton {
        let button = HotKeyRecorderButton()
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        button.target = context.coordinator
        button.action = #selector(Coordinator.beginRecording(_:))
        button.onChange = context.coordinator.onChange
        button.shortcut = shortcut
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: HotKeyRecorderButton, context: Context) {
        context.coordinator.onChange = onChange
        button.onChange = onChange
        if !button.isRecording {
            button.shortcut = shortcut
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onChange: (HotKeyShortcut) -> Void

        init(onChange: @escaping (HotKeyShortcut) -> Void) {
            self.onChange = onChange
        }

        @objc func beginRecording(_ sender: HotKeyRecorderButton) {
            sender.startRecording()
        }
    }
}

final class HotKeyRecorderButton: NSButton {
    var onChange: ((HotKeyShortcut) -> Void)?
    var shortcut: HotKeyShortcut? {
        didSet { if !isRecording { refreshTitle() } }
    }
    private(set) var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    func startRecording() {
        isRecording = true
        title = "Press a new shortcut…"
        toolTip = "Press Escape to cancel"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return
        }

        let modifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard let keyLabel = Self.keyLabel(for: event),
              !keyLabel.isEmpty else {
            NSSound.beep()
            title = "Key not recognized"
            return
        }

        let newShortcut = HotKeyShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers,
            keyLabel: keyLabel
        )
        shortcut = newShortcut
        isRecording = false
        refreshTitle()
        window?.makeFirstResponder(nil)
        onChange?(newShortcut)
    }

    override func rightMouseDown(with event: NSEvent) {
        if isRecording {
            cancelRecording()
        } else {
            super.rightMouseDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { cancelRecording() }
        return super.resignFirstResponder()
    }

    private func cancelRecording() {
        isRecording = false
        refreshTitle()
        window?.makeFirstResponder(nil)
    }

    private func refreshTitle() {
        title = shortcut?.displayText ?? "Click to set"
        toolTip = "Set a single key or key combination; press Escape to cancel"
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        let special: [UInt16: String] = [
            UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Delete): "⌫",
            UInt16(kVK_ForwardDelete): "⌦",
            UInt16(kVK_Home): "Home",
            UInt16(kVK_End): "End",
            UInt16(kVK_PageUp): "Page Up",
            UInt16(kVK_PageDown): "Page Down",
            UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_F1): "F1",
            UInt16(kVK_F2): "F2",
            UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4",
            UInt16(kVK_F5): "F5",
            UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7",
            UInt16(kVK_F8): "F8",
            UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10",
            UInt16(kVK_F11): "F11",
            UInt16(kVK_F12): "F12"
        ]
        if let label = special[event.keyCode] { return label }
        guard let characters = event.charactersIgnoringModifiers?.uppercased(),
              characters.count == 1,
              let scalar = characters.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar) else {
            return nil
        }
        return characters
    }
}
