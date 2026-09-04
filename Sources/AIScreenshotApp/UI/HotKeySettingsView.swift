import SwiftUI

struct HotKeySettingsView: View {
    @State private var shortcuts = HotKeyPreferences().allShortcuts()
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private let preferences = HotKeyPreferences()

    var body: some View {
        Form {
            Section("Global Screenshot Shortcuts") {
                ForEach(GlobalHotKeyAction.allCases, id: \.rawValue) { action in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(action.displayName)
                                .font(.body.weight(.medium))
                            Text(action.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HotKeyRecorderView(
                            shortcut: shortcuts[action] ?? action.defaultShortcut,
                            onChange: { update($0, for: action) }
                        )
                        .frame(minWidth: 126, minHeight: 28)
                    }
                    .padding(.vertical, 3)
                }
            }

            Section {
                HStack {
                    Button("Restore Default Shortcuts") {
                        preferences.resetAll()
                        shortcuts = preferences.allShortcuts()
                        status("Default shortcuts restored.")
                    }
                    Spacer()
                    Text("Click the current shortcut, then press a new key or key combination")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let statusMessage {
                    Label(
                        statusMessage,
                        systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(statusIsError ? .red : .green)
                }
            } footer: {
                Text("Supports single keys and key combinations. Using a letter or number alone will block its normal input in every app, so prefer a less-common key. Press Escape to cancel recording; a duplicate or system-reserved shortcut won't overwrite the current configuration. While selecting a screenshot region, press the right mouse button or Escape to cancel.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .onReceive(NotificationCenter.default.publisher(for: HotKeyPreferences.didChangeNotification)) { _ in
            shortcuts = preferences.allShortcuts()
        }
        .onReceive(NotificationCenter.default.publisher(for: HotKeyPreferences.registrationFailedNotification)) { notification in
            shortcuts = preferences.allShortcuts()
            let message = notification.userInfo?[HotKeyPreferences.errorMessageUserInfoKey] as? String
            status(message ?? "Shortcut registration failed; the previous configuration was restored.", isError: true)
        }
    }

    private func update(_ shortcut: HotKeyShortcut, for action: GlobalHotKeyAction) {
        do {
            try preferences.save(shortcut, for: action)
            shortcuts = preferences.allShortcuts()
            status("\u{201c}\(action.displayName)\u{201d} changed to \(shortcut.displayText).")
        } catch {
            shortcuts = preferences.allShortcuts()
            status(error.localizedDescription, isError: true)
        }
    }

    private func status(_ message: String, isError: Bool = false) {
        statusMessage = message
        statusIsError = isError
    }
}
