import SwiftUI
import TaAgentContracts

struct AgentSettingsView: View {
    @AppStorage(TaAgentPreferenceKey.accessEnabled) private var accessEnabled = true
    @AppStorage(TaAgentPreferenceKey.automaticCaptureAllowed) private var automaticCaptureAllowed = true
    @AppStorage(TaAgentPreferenceKey.cloudPolicy) private var cloudPolicy = AgentCloudPolicy.auto.rawValue
    @AppStorage(TaAgentPreferenceKey.privacyDenylist) private var privacyDenylist = ""
    @AppStorage(TaAgentPreferenceKey.allowCaptureTa) private var allowCaptureTa = true

    @State private var recentCalls: [TaAgentAuditEntry] = []
    @State private var operationMessage: String?
    private let auditLog = TaAgentAuditLog()
    private let artifactStore = TaAgentArtifactStore()

    var body: some View {
        Form {
            Section("Agent 与自动化") {
                Toggle("允许本机 Agent 调用拓", isOn: $accessEnabled)
                Text(accessEnabled
                     ? "CLI、Agent Skill 和 DeepSeek Harness 可以通过仅限当前用户的本机 Bridge 调用拓。"
                     : "除状态与权限检查外，所有 Agent 能力都会被拒绝。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("允许无感自动截图", isOn: $automaticCaptureAllowed)
                    .disabled(!accessEnabled)
                Label("普通截图不会弹出拓、抢占前台 App、移动鼠标或发送键盘事件。", systemImage: "cursorarrow.rays")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("云端与模型") {
                Picker("默认云端策略", selection: $cloudPolicy) {
                    Text("按能力决定（推荐）").tag(AgentCloudPolicy.auto.rawValue)
                    Text("允许已配置的云端模型").tag(AgentCloudPolicy.allow.rawValue)
                    Text("始终禁止上传").tag(AgentCloudPolicy.deny.rawValue)
                }
                .disabled(!accessEnabled)
                Text(cloudPolicyDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("Agent 只能请求拓执行模型任务，无法读取 Keychain 中的 API Key。", systemImage: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("隐私 App 黑名单") {
                TextEditor(text: $privacyDenylist)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 68)
                    .padding(6)
                    .scrollContentBackground(.hidden)
                    .background(TaPalette.elevatedPaper.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(TaPalette.hairline, lineWidth: 1)
                    }
                    .disabled(!accessEnabled)
                Text("每行填写一个 Bundle ID，例如 com.1password.1password。截显示器时，只要画面包含黑名单 App 就会拒绝截图。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("允许 Agent 截取拓自身", isOn: $allowCaptureTa)
                    .disabled(!accessEnabled)
            }

            Section("缓存与调用记录") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("临时截图缓存")
                        Text("图片保存在本机缓存，默认 24 小时后自动清理。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("立即清理") { clearArtifacts() }
                }

                HStack {
                    Text("最近调用")
                    Spacer()
                    Button("刷新") { refreshAudit() }
                        .buttonStyle(.link)
                    Button("清除记录") { clearAudit() }
                        .buttonStyle(.link)
                        .disabled(recentCalls.isEmpty)
                }

                if recentCalls.isEmpty {
                    Text("暂无调用记录。审计不会保存 API Key、OCR/翻译正文或图片数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentCalls.prefix(8)) { entry in
                        auditRow(entry)
                    }
                    Text("仅保留最近 100 次调用；不记录请求参数和识别内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let operationMessage {
                    Text(operationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .onAppear { refreshAudit() }
    }

    private var cloudPolicyDescription: String {
        switch AgentCloudPolicy(rawValue: cloudPolicy) ?? .auto {
        case .auto:
            "本地截图和 OCR 留在设备上；识图、翻译或 DeepSeek OCR 等模型能力按任务使用云端。调用方仍可用 cloud=deny 强制本地。"
        case .allow:
            "允许 Agent 使用你已经在拓中配置的云端模型。每次调用仍会写入是否上云的审计标记。"
        case .deny:
            "所有需要上传图片或文字的 Agent 调用都会被拒绝，只保留本地截图和本地 OCR。"
        }
    }

    @ViewBuilder
    private func auditRow(_ entry: TaAgentAuditEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.succeeded ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.method.rawValue)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                Text("\(entry.clientName) · \(entry.occurredAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.cloudUploaded {
                Label("云端", systemImage: "icloud.and.arrow.up")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Text("本地")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("\(entry.durationMs) ms")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)
        }
    }

    private func refreshAudit() {
        Task {
            do {
                recentCalls = try await auditLog.recent(limit: 20)
                operationMessage = nil
            } catch {
                operationMessage = "无法读取调用记录：\(error.localizedDescription)"
            }
        }
    }

    private func clearAudit() {
        Task {
            do {
                try await auditLog.clear()
                recentCalls = []
                operationMessage = "调用记录已清除。"
            } catch {
                operationMessage = "清除失败：\(error.localizedDescription)"
            }
        }
    }

    private func clearArtifacts() {
        Task {
            do {
                let count = try await artifactStore.clearAll()
                operationMessage = count == 0 ? "当前没有临时截图缓存。" : "已清理 \(count) 组临时截图。"
            } catch {
                operationMessage = "缓存清理失败：\(error.localizedDescription)"
            }
        }
    }
}
