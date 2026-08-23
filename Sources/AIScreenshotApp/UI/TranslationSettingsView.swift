import SwiftUI
import AIScreenshotCore

struct TranslationSettingsView: View {
    @AppStorage("translationBaseURL") private var baseURL = TranslationConfiguration.defaultBaseURL
    @AppStorage("translationTextModel") private var textModel = TranslationConfiguration.defaultTextModel
    @AppStorage("translationVisionModel") private var visionModel = TranslationConfiguration.defaultVisionModel
    @AppStorage("translationSourceLanguage") private var sourceLanguage = TranslationConfiguration.defaultSourceLanguage
    @AppStorage("translationTargetLanguage") private var targetLanguage = TranslationConfiguration.defaultTargetLanguage
    @AppStorage("translationDefaultMode") private var defaultMode = ScreenshotTranslationMode.textOnly.rawValue
    @AppStorage("translationUsesVisionFallback") private var usesVisionFallback = true

    @State private var apiKey = ""
    @State private var hasStoredKey = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false
    @State private var translationShortcut = HotKeyPreferences().shortcut(for: .translationCapture)

    private let secretStore = KeychainSecretStore()
    private let service = ScreenshotTranslationService()

    var body: some View {
        Form {
            Section("翻译语言") {
                languageRow(title: "源语言", value: $sourceLanguage, presets: ["自动检测", "英文", "简体中文", "日文", "韩文"])
                languageRow(title: "目标语言", value: $targetLanguage, presets: ["简体中文", "英文", "繁体中文", "日文", "韩文", "西班牙文"])
                Picker("默认翻译方式", selection: $defaultMode) {
                    ForEach(ScreenshotTranslationMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                Text("语言可以直接输入任意名称；快捷键 \(translationShortcut.displayText) 始终执行“翻译文字并复制”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("DeepSeek 模型") {
                TextField("API 地址", text: $baseURL)
                TextField("文字模型", text: $textModel)
                TextField("视觉模型", text: $visionModel)
                Toggle("本地 OCR 低置信度时使用视觉模型", isOn: $usesVisionFallback)
                Text("默认文字模型负责翻译；视觉模型只在 OCR 失败或置信度较低时读取本次选区。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("API Key") {
                HStack {
                    Circle()
                        .fill(hasStoredKey ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(hasStoredKey ? "API Key 已保存到 macOS Keychain" : "尚未保存 API Key")
                        .font(.callout)
                }
                SecureField(hasStoredKey ? "输入新 Key 以更新" : "DeepSeek API Key", text: $apiKey)

                HStack {
                    Button("恢复 DeepSeek 默认值") {
                        baseURL = TranslationConfiguration.defaultBaseURL
                        textModel = TranslationConfiguration.defaultTextModel
                        visionModel = TranslationConfiguration.defaultVisionModel
                        status("已恢复当前 DeepSeek 默认模型。")
                    }
                    Spacer()
                    if hasStoredKey {
                        Button("移除 Key", role: .destructive) { removeKey() }
                    }
                    Button("保存") { save() }
                        .buttonStyle(.borderedProminent)
                }
            }

            Section {
                HStack {
                    Button("测试文字模型") { testTextModel() }
                    Button("测试视觉模型") { testVisionModel() }
                    Spacer()
                    if isTesting { ProgressView().controlSize(.small) }
                }
                .disabled(isTesting)

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? .red : .secondary)
                }
            } header: {
                Text("连接测试")
            } footer: {
                Text("Key 不会写入偏好设置、源码或日志。全文和双语图片由本机重新排版；视觉回退开启时，截图会发送到所配置的视觉模型。")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .onAppear {
            hasStoredKey = secretStore.contains(account: ScreenshotTranslationService.keychainAccount)
        }
        .onReceive(NotificationCenter.default.publisher(for: HotKeyPreferences.didChangeNotification)) { _ in
            translationShortcut = HotKeyPreferences().shortcut(for: .translationCapture)
        }
    }

    private func languageRow(
        title: String,
        value: Binding<String>,
        presets: [String]
    ) -> some View {
        HStack {
            TextField(title, text: value)
            Menu("常用") {
                ForEach(presets, id: \.self) { language in
                    Button(language) { value.wrappedValue = language }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var currentConfiguration: TranslationConfiguration {
        TranslationConfiguration(
            baseURL: baseURL,
            textModel: textModel,
            visionModel: visionModel,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            defaultMode: ScreenshotTranslationMode(rawValue: defaultMode) ?? .textOnly,
            usesVisionFallback: usesVisionFallback
        )
    }

    private var validationMessage: String? {
        currentConfiguration.validationMessage
    }

    private func save() {
        guard validationMessage == nil else {
            status(validationMessage ?? "配置无效。", isError: true)
            return
        }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty || hasStoredKey else {
            status("请输入 API Key。", isError: true)
            return
        }
        do {
            if !trimmedKey.isEmpty {
                try secretStore.save(trimmedKey, account: ScreenshotTranslationService.keychainAccount)
                apiKey = ""
                hasStoredKey = true
            }
            status("翻译配置已保存。")
        } catch {
            status(error.localizedDescription, isError: true)
        }
    }

    private func removeKey() {
        do {
            try secretStore.delete(account: ScreenshotTranslationService.keychainAccount)
            apiKey = ""
            hasStoredKey = false
            status("翻译 API Key 已移除。")
        } catch {
            status(error.localizedDescription, isError: true)
        }
    }

    private func testTextModel() {
        guard validationMessage == nil else {
            status(validationMessage ?? "配置无效。", isError: true)
            return
        }
        isTesting = true
        status("正在测试文字模型…")
        let candidate = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let response = try await service.testTextModel(apiKey: candidate.isEmpty ? nil : candidate)
                status("文字模型连接成功：\(response.prefix(80))")
            } catch {
                status(error.localizedDescription, isError: true)
            }
            isTesting = false
        }
    }

    private func testVisionModel() {
        guard validationMessage == nil else {
            status(validationMessage ?? "配置无效。", isError: true)
            return
        }
        guard !visionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status("请填写视觉模型。", isError: true)
            return
        }
        isTesting = true
        status("正在生成测试图片并调用视觉模型…")
        let candidate = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let response = try await service.testVisionModel(apiKey: candidate.isEmpty ? nil : candidate)
                status("视觉模型连接成功：\(response.prefix(80))")
            } catch {
                status(error.localizedDescription, isError: true)
            }
            isTesting = false
        }
    }

    private func status(_ message: String, isError: Bool = false) {
        statusMessage = message
        statusIsError = isError
    }
}
