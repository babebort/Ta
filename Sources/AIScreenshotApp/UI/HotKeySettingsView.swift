import SwiftUI

struct HotKeySettingsView: View {
    @State private var shortcuts = HotKeyPreferences().allShortcuts()
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private let preferences = HotKeyPreferences()

    var body: some View {
        Form {
            Section("全局截图快捷键") {
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
                    Button("恢复默认快捷键") {
                        preferences.resetAll()
                        shortcuts = preferences.allShortcuts()
                        status("已恢复默认快捷键。")
                    }
                    Spacer()
                    Text("点击当前快捷键后，直接按下新的单键或组合键")
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
                Text("支持单键和组合键。单独使用字母或数字会占用它在所有应用中的正常输入，请优先选择不常用按键。Escape 取消录制；重复或被系统占用的快捷键不会覆盖当前配置。框选截图时可按右键或 Escape 退出。")
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
            status(message ?? "快捷键注册失败，已恢复上一组配置。", isError: true)
        }
    }

    private func update(_ shortcut: HotKeyShortcut, for action: GlobalHotKeyAction) {
        do {
            try preferences.save(shortcut, for: action)
            shortcuts = preferences.allShortcuts()
            status("“\(action.displayName)”已改为 \(shortcut.displayText)。")
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
