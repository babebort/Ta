@preconcurrency import Carbon
import Foundation

enum GlobalHotKeyError: LocalizedError {
    case eventHandler(OSStatus)
    case registration(action: GlobalHotKeyAction, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .eventHandler(let status):
            "无法安装快捷键处理器（\(status)）"
        case .registration(let action, let status):
            "“\(action.displayName)”快捷键已被系统或其他应用占用（\(status)）。"
        }
    }
}

private let aiScreenshotHotKeySignature: OSType = 0x41495353 // AISS

@MainActor
final class GlobalHotKeyManager: NSObject {
    private let preferences = HotKeyPreferences()
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var lastSuccessfulShortcuts: [GlobalHotKeyAction: HotKeyShortcut] = [:]
    private var preferencesObserver: NSObjectProtocol?

    func registerDefaults(
        interactiveCapture: @escaping () -> Void,
        intelligentCapture: @escaping () -> Void,
        translationCapture: @escaping () -> Void,
        imageCapture: @escaping () -> Void,
        pinCapture: @escaping () -> Void,
        longCapture: @escaping () -> Void
    ) throws {
        actions = [
            GlobalHotKeyAction.interactiveCapture.hotKeyID: interactiveCapture,
            GlobalHotKeyAction.intelligentCapture.hotKeyID: intelligentCapture,
            GlobalHotKeyAction.translationCapture.hotKeyID: translationCapture,
            GlobalHotKeyAction.imageCapture.hotKeyID: imageCapture,
            GlobalHotKeyAction.pinCapture.hotKeyID: pinCapture,
            GlobalHotKeyAction.longCapture.hotKeyID: longCapture
        ]

        try installEventHandlerIfNeeded()
        let shortcuts = preferences.allShortcuts()
        try register(shortcuts)
        lastSuccessfulShortcuts = shortcuts
        observePreferenceChangesIfNeeded()
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else { return }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                let manager = Unmanaged<GlobalHotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in manager.invoke(id: hotKeyID.id) }
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw GlobalHotKeyError.eventHandler(installStatus)
        }
    }

    private func observePreferenceChangesIfNeeded() {
        guard preferencesObserver == nil else { return }
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: HotKeyPreferences.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadFromPreferences() }
        }
    }

    private func reloadFromPreferences() {
        let requested = preferences.allShortcuts()
        unregisterHotKeys()
        do {
            try register(requested)
            lastSuccessfulShortcuts = requested
        } catch {
            unregisterHotKeys()
            if !lastSuccessfulShortcuts.isEmpty {
                try? preferences.replaceAll(lastSuccessfulShortcuts, notify: false)
                try? register(lastSuccessfulShortcuts)
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            NotificationCenter.default.post(
                name: HotKeyPreferences.registrationFailedNotification,
                object: nil,
                userInfo: [HotKeyPreferences.errorMessageUserInfoKey: message]
            )
        }
    }

    private func register(_ shortcuts: [GlobalHotKeyAction: HotKeyShortcut]) throws {
        for action in GlobalHotKeyAction.allCases {
            guard let shortcut = shortcuts[action] else { continue }
            var reference: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: aiScreenshotHotKeySignature, id: action.hotKeyID)
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.modifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &reference
            )
            guard status == noErr, let reference else {
                throw GlobalHotKeyError.registration(action: action, status: status)
            }
            hotKeyRefs.append(reference)
        }
    }

    private func invoke(id: UInt32) {
        actions[id]?()
    }

    private func unregisterHotKeys() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
    }
}
