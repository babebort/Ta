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

    var hasPrimaryModifier: Bool {
        modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
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
        case .intelligentCapture: "极速识别内容"
        case .interactiveCapture: "通用截图"
        case .imageCapture: "截图图片"
        case .pinCapture: "截图并钉住"
        case .longCapture: "滚动长截图"
        case .translationCapture: "截图翻译"
        }
    }

    var detail: String {
        switch self {
        case .intelligentCapture: "按识别设置直接获取内容"
        case .interactiveCapture: "框选后再选择取字、翻译、复制或编辑"
        case .imageCapture: "框选后直接复制图片"
        case .pinCapture: "框选后直接钉在屏幕上"
        case .longCapture: "进入滚动长截图模式"
        case .translationCapture: "识别、翻译并复制文字"
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
    case missingPrimaryModifier
    case duplicate(action: GlobalHotKeyAction)

    var errorDescription: String? {
        switch self {
        case .missingPrimaryModifier:
            "全局快捷键至少需要包含 ⌘、⌥ 或 ⌃ 中的一个修饰键。"
        case .duplicate(let action):
            "这个组合已用于“\(action.displayName)”，请换一个快捷键。"
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
        guard shortcut.hasPrimaryModifier else {
            throw HotKeyPreferencesError.missingPrimaryModifier
        }
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
