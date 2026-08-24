import AppKit
import Carbon
import XCTest
@testable import AIScreenshotApp

final class HotKeyPreferencesTests: XCTestCase {
    func testDefaultsAreUniqueAndKeepExpectedDisplayText() {
        let shortcuts = Dictionary(uniqueKeysWithValues: GlobalHotKeyAction.allCases.map { ($0, $0.defaultShortcut) })
        let registrations = Set(shortcuts.values.map { "\($0.modifiers):\($0.keyCode)" })
        XCTAssertEqual(registrations.count, GlobalHotKeyAction.allCases.count)
        XCTAssertEqual(shortcuts[.intelligentCapture]?.displayText, "⇧⌥⌘1")
        XCTAssertEqual(shortcuts[.translationCapture]?.displayText, "⇧⌥⌘6")
    }

    func testCustomShortcutPersistsAndResetRestoresDefault() throws {
        let (preferences, defaults, suiteName) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let custom = HotKeyShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey | optionKey),
            keyLabel: "A"
        )

        try preferences.save(custom, for: .interactiveCapture)
        XCTAssertEqual(preferences.shortcut(for: .interactiveCapture), custom)
        preferences.resetAll()
        XCTAssertEqual(preferences.shortcut(for: .interactiveCapture), GlobalHotKeyAction.interactiveCapture.defaultShortcut)
    }

    func testDuplicateShortcutIsRejectedWithoutOverwriting() throws {
        let (preferences, defaults, suiteName) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let original = preferences.shortcut(for: .interactiveCapture)

        XCTAssertThrowsError(
            try preferences.save(GlobalHotKeyAction.intelligentCapture.defaultShortcut, for: .interactiveCapture)
        ) { error in
            XCTAssertEqual(error as? HotKeyPreferencesError, .duplicate(action: .intelligentCapture))
        }
        XCTAssertEqual(preferences.shortcut(for: .interactiveCapture), original)
    }

    func testSingleKeyShortcutPersistsWithoutModifier() throws {
        let (preferences, defaults, suiteName) = makePreferences()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let singleKey = HotKeyShortcut(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: 0,
            keyLabel: "A"
        )

        try preferences.save(singleKey, for: .interactiveCapture)
        XCTAssertEqual(preferences.shortcut(for: .interactiveCapture), singleKey)
        XCTAssertEqual(preferences.shortcut(for: .interactiveCapture).displayText, "A")
    }

    @MainActor
    func testRightClickCancelsSelection() throws {
        let view = SelectionOverlayView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        var didCancel = false
        view.onFinish = { rect, action in
            didCancel = rect == nil && action == nil
        }
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        view.rightMouseDown(with: event)
        XCTAssertTrue(didCancel)
    }

    private func makePreferences() -> (HotKeyPreferences, UserDefaults, String) {
        let suiteName = "com.kangarooking.AIScreenshot.hotkey-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (HotKeyPreferences(defaults: defaults), defaults, suiteName)
    }
}
