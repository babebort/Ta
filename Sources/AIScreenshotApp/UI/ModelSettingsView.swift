import SwiftUI
import AIScreenshotCore

struct ModelSettingsView: View {
    @AppStorage("providerKind") private var providerKind = VisionProviderKind.openAICompatible.rawValue
    @AppStorage("providerBaseURL") private var baseURL = ""
    @AppStorage("providerVisionModel") private var visionModel = ""
    @AppStorage("providerTextModel") private var textModel = ""
    @AppStorage("multimodalTaskTemplate") private var taskTemplate = MultimodalTaskTemplate.general.rawValue

    @State private var apiKey = ""
    @State private var hasStoredKey = false
    @State private var statusMessage: String?

    private let secretStore = KeychainSecretStore()
    private let account = PersistentConfigurationIdentity.multimodalProviderAccount

    var body: some View {
        Form {
            Section("识别路径") {
                Label("OCR 引擎", systemImage: "cpu")
                Text("Apple Vision 与增强包在本机运行；DeepSeek-OCR-2 使用“识别”页单独配置的服务和 Key。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("多模态大模型", systemImage: "sparkles")
                Text("只在你明确选择 AI 识图或启用对应自动策略时，发送主动框选的图片。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OpenAI-compatible")
                            .font(.headline)
                        Text(hasStoredKey ? "API Key 已安全保存" : "未配置 API Key，本地功能仍可用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(hasStoredKey ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                }
            }

            Section("连接") {
                Picker("Provider 协议", selection: $providerKind) {
                    ForEach(VisionProviderKind.allCases, id: \.rawValue) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                TextField("Base URL", text: $baseURL, prompt: Text("https://api.example.com/v1"))
                LabeledContent("API Key") {
                    Label(
                        hasStoredKey ? "•••••••••••• · 已安全保存" : "尚未保存",
                        systemImage: hasStoredKey ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(hasStoredKey ? Color.green : Color.orange)
                }
                SecureField(
                    hasStoredKey ? "新的 API Key（不更新可留空）" : "API Key",
                    text: $apiKey
                )
                TextField("视觉模型名称", text: $visionModel)
                TextField("文本模型名称", text: $textModel)
                Picker("默认识图任务", selection: $taskTemplate) {
                    ForEach(MultimodalTaskTemplate.allCases, id: \.rawValue) { task in
                        Text(task.displayName).tag(task.rawValue)
                    }
                }

                HStack {
                    Text("推荐地址")
                    Spacer()
                    Text(recommendedBaseURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Button("应用") { baseURL = recommendedBaseURL }
                        .disabled(recommendedBaseURL.isEmpty)
                }

                let configuration = ProviderConfiguration(
                    baseURL: baseURL,
                    visionModel: visionModel,
                    textModel: textModel
                )
                if let validation = configuration.validationMessage {
                    Label(validation, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Provider 兼容矩阵") {
                compatibilityRow("OpenAI / OpenRouter / Qwen / Ollama", detail: "OpenAI-compatible Chat Completions", ready: true)
                compatibilityRow("Azure OpenAI", detail: "openai/v1 + api-key", ready: true)
                compatibilityRow("Anthropic Claude", detail: "Messages API + base64 image", ready: true)
                compatibilityRow("Google Gemini", detail: "generateContent + inlineData", ready: true)
                Text("“已适配”表示请求协议已实现；最终能否识图仍取决于你填写的具体模型是否支持视觉输入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if hasStoredKey {
                        Button("移除 Key", role: .destructive) {
                            removeKey()
                        }
                    }
                    Button("保存") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        !hasStoredKey
                            && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            } footer: {
                Text("API Key 只保存在 macOS Keychain，不进入偏好设置、日志或配置导出；在同一台 Mac 上覆盖升级拓时会继续保留。")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .onAppear {
            hasStoredKey = secretStore.contains(account: account)
        }
    }

    private var recommendedBaseURL: String {
        switch VisionProviderKind(rawValue: providerKind) ?? .openAICompatible {
        case .openAICompatible: "https://api.openai.com/v1"
        case .azureOpenAI: ""
        case .anthropic: "https://api.anthropic.com"
        case .googleGemini: "https://generativelanguage.googleapis.com"
        }
    }

    private func compatibilityRow(_ name: String, detail: String, ready: Bool) -> some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "clock")
                .foregroundStyle(ready ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        let configuration = ProviderConfiguration(
            baseURL: baseURL,
            visionModel: visionModel,
            textModel: textModel
        )
        if let validation = configuration.validationMessage {
            statusMessage = validation
            return
        }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty || hasStoredKey else {
            statusMessage = "请输入 API Key"
            return
        }
        do {
            if !trimmedKey.isEmpty {
                try secretStore.save(trimmedKey, account: account)
                apiKey = ""
                hasStoredKey = true
            }
            statusMessage = "已保存到 Keychain"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try secretStore.delete(account: account)
            apiKey = ""
            hasStoredKey = false
            statusMessage = "Key 已移除"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
