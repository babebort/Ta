import Carbon
import Foundation

struct HotKeyShortcut: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    var displayText: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyLabel
    }

}

enum GlobalHotKeyAction: String, CaseIterable, Codable, Hashable, Sendable {
    case intelligentCapture
    case interactiveCapture
    case imageCapture
    case pinCapture
    case longCapture
    case translationCapture

    var hotKeyID: UInt32 {
        switch self {
        case .interactiveCapture: 1
        case .intelligentCapture: 2
        case .imageCapture: 3
        case .pinCapture: 4
        case .longCapture: 5
        case .translationCapture: 6
        }
    }

    var displayName: String {
        switch self {
        case .intelligentCapture: "Instant Recognition"
        case .interactiveCapture: "General Screenshot"
        case .imageCapture: "Screenshot as Image"
        case .pinCapture: "Screenshot and Pin"
        case .longCapture: "Scrolling Long Screenshot"
        case .translationCapture: "Screenshot Translation"
        }
    }

    var detail: String {
        switch self {
        case .intelligentCapture: "Get content directly using recognition settings"
        case .interactiveCapture: "Select an area, then choose text, translate, copy, or edit"
        case .imageCapture: "Select an area and copy the image directly"
        case .pinCapture: "Select an area and pin it to the screen directly"
        case .longCapture: "Enter scrolling long-screenshot mode"
        case .translationCapture: "Recognize, translate, and copy text"
        }
    }

    var defaultShortcut: HotKeyShortcut {
        let modifiers = UInt32(cmdKey | optionKey | shiftKey)
        switch self {
        case .intelligentCapture:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: modifiers, keyLabel: "1")
        case .interactiveCapture:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: modifiers, keyLabel: "2")
        case .imageCapture:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_3), modifiers: modifiers, keyLabel: "3")
        case .pinCapture:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: modifiers, keyLabel: "4")
        case .longCapture:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_5), modifiers: modifiers, keyLabel: "5")
        case .translationCapture:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_6), modifiers: modifiers, keyLabel: "6")
        }
    }
}

enum HotKeyPreferencesError: LocalizedError, Equatable {
    case duplicate(action: GlobalHotKeyAction)

    var errorDescription: String? {
        switch self {
        case .duplicate(let action):
            "This combination is already used for “\(action.displayName)” — please choose a different shortcut."
        }
    }
}

struct HotKeyPreferences {
    static let didChangeNotification = Notification.Name("AIScreenshotHotKeyPreferencesDidChange")
    static let registrationFailedNotification = Notification.Name("AIScreenshotHotKeyRegistrationFailed")
    static let errorMessageUserInfoKey = "message"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shortcut(for action: GlobalHotKeyAction) -> HotKeyShortcut {
        guard let data = defaults.data(forKey: storageKey(for: action)),
              let shortcut = try? decoder.decode(HotKeyShortcut.self, from: data) else {
            return action.defaultShortcut
        }
        return shortcut
    }

    func allShortcuts() -> [GlobalHotKeyAction: HotKeyShortcut] {
        Dictionary(uniqueKeysWithValues: GlobalHotKeyAction.allCases.map { ($0, shortcut(for: $0)) })
    }

    func save(_ shortcut: HotKeyShortcut, for action: GlobalHotKeyAction) throws {
        if let duplicate = allShortcuts().first(where: { otherAction, otherShortcut in
            otherAction != action && otherShortcut.keyCode == shortcut.keyCode && otherShortcut.modifiers == shortcut.modifiers
        })?.key {
            throw HotKeyPreferencesError.duplicate(action: duplicate)
        }
        try store(shortcut, for: action)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func resetAll() {
        GlobalHotKeyAction.allCases.forEach { defaults.removeObject(forKey: storageKey(for: $0)) }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func replaceAll(_ shortcuts: [GlobalHotKeyAction: HotKeyShortcut], notify: Bool) throws {
        for action in GlobalHotKeyAction.allCases {
            guard let shortcut = shortcuts[action] else { continue }
            try store(shortcut, for: action)
        }
        if notify {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    private func store(_ shortcut: HotKeyShortcut, for action: GlobalHotKeyAction) throws {
        defaults.set(try encoder.encode(shortcut), forKey: storageKey(for: action))
    }

    private func storageKey(for action: GlobalHotKeyAction) -> String {
        "globalHotKey.\(action.rawValue)"
    }
}
