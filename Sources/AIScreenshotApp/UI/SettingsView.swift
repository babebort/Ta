import SwiftUI
import AIScreenshotCore

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .permissions

    var body: some View {
        ZStack {
            TaPaperBackground()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(SettingsTab.allCases) { tab in
                        settingsTabButton(tab)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(TaPalette.elevatedPaper.opacity(0.96))

                Divider()
                    .overlay(TaPalette.hairline)

                Group {
                    switch selectedTab {
                    case .permissions: PermissionsSettingsView()
                    case .general: GeneralSettingsView()
                    case .hotKeys: HotKeySettingsView()
                    case .recognition: RecognitionSettingsView()
                    case .translation: TranslationSettingsView()
                    case .models: ModelSettingsView()
                    case .agent: AgentSettingsView()
                    }
                }
                .padding(18)
            }
        }
        .frame(width: 780, height: 600)
        .accentColor(TaPalette.cinnabar)
        .tint(TaPalette.cinnabar)
        .onReceive(NotificationCenter.default.publisher(for: .openAIModelSettings)) { _ in
            withAnimation(.easeOut(duration: 0.16)) { selectedTab = .models }
        }
    }

    private func settingsTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 30, height: 25)
                Text(tab.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? TaPalette.cinnabar : TaPalette.mutedInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? TaPalette.cinnabar.opacity(0.10) : Color.clear)
            )
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(isSelected ? TaPalette.cinnabar : Color.clear)
                    .frame(width: 18, height: 2)
                    .offset(y: 2)
            }
        }
        .buttonStyle(.plain)
        .help(tab.title)
    }
}

extension Notification.Name {
    static let openAIModelSettings = Notification.Name("Ta.OpenAIModelSettings")
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case permissions
    case general
    case hotKeys
    case recognition
    case translation
    case models
    case agent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .permissions: "Permissions"
        case .general: "General"
        case .hotKeys: "Hotkeys"
        case .recognition: "Recognition"
        case .translation: "Translation"
        case .models: "AI Models"
        case .agent: "Agent"
        }
    }

    var icon: String {
        switch self {
        case .permissions: "lock.shield"
        case .general: "gearshape"
        case .hotKeys: "command"
        case .recognition: "text.viewfinder"
        case .translation: "character.book.closed"
        case .models: "sparkles"
        case .agent: "cpu"
        }
    }
}

private struct PermissionsSettingsView: View {
    @State private var isGranted = ScreenCapturePermissionService.isGranted
    @State private var accessibilityGranted = AccessibilityAutoScrollService.isGranted

    var body: some View {
        Form {
            Section("Screen Recording") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            isGranted ? "Granted" : "Not granted",
                            systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(isGranted ? .green : .orange)
                        Text("Only captures the region you select; the app never records the screen continuously in the background.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isGranted ? "Recheck" : "Request Access") {
                        if !isGranted {
                            _ = ScreenCapturePermissionService.request()
                        }
                        isGranted = ScreenCapturePermissionService.isGranted
                    }
                    Button("Open System Settings") {
                        ScreenCapturePermissionService.openSystemSettings()
                    }
                }
            }

            Section("Accessibility") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            accessibilityGranted ? "Granted" : "Needed for auto-scroll only",
                            systemImage: accessibilityGranted ? "checkmark.circle.fill" : "hand.raised.fill"
                        )
                        .foregroundStyle(accessibilityGranted ? .green : .secondary)
                        Text("Manual long screenshots don't need this permission; it's only used if you turn on auto-scroll.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(accessibilityGranted ? "Recheck" : "Request Access") {
                        if !accessibilityGranted { _ = AccessibilityAutoScrollService.request() }
                        accessibilityGranted = AccessibilityAutoScrollService.isGranted
                    }
                    Button("Open System Settings") { AccessibilityAutoScrollService.openSystemSettings() }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .onAppear {
            isGranted = ScreenCapturePermissionService.isGranted
            accessibilityGranted = AccessibilityAutoScrollService.isGranted
        }
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("resultBarDuration") private var resultBarDuration = 3.0
    @AppStorage("saveHistory") private var saveHistory = false
    @AppStorage("postCaptureAction") private var postCaptureAction = PostCaptureAction.choose.rawValue

    var body: some View {
        Form {
            Section("After Capture") {
                Picker("Default Action", selection: $postCaptureAction) {
                    Text("Ask me every time (recommended)").tag(PostCaptureAction.choose.rawValue)
                    Text("Recognize and copy").tag(PostCaptureAction.recognize.rawValue)
                    Text("Translate and copy").tag(PostCaptureAction.translateText.rawValue)
                    Text("Copy image").tag(PostCaptureAction.copyImage.rawValue)
                    Text("Pin to screen").tag(PostCaptureAction.pin.rawValue)
                    Text("Open annotation").tag(PostCaptureAction.edit.rawValue)
                    Text("Remember last action").tag(PostCaptureAction.rememberLast.rawValue)
                }
                Text("This only affects general captures; quick recognize, capture-translate, copy image, and pin hotkeys run directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Result Bar") {
                HStack {
                    Text("Auto-hide")
                    Slider(value: $resultBarDuration, in: 1.5...8, step: 0.5)
                    Text("\(resultBarDuration, specifier: "%.1f") sec")
                        .monospacedDigit()
                        .frame(width: 54, alignment: .trailing)
                }
            }

            Section("History & Privacy") {
                Toggle("Save screenshot history locally", isOn: $saveHistory)
                Text(saveHistory ? "Screenshots are saved locally only; cloud calls will still prompt separately." : "Screenshot files are not persisted right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
}

private struct RecognitionSettingsView: View {
    @AppStorage("recognitionLanguages") private var languages = "zh-Hans,en-US"
    @AppStorage("mergeWrappedLines") private var mergeWrappedLines = false
    @AppStorage("recognitionRoute") private var recognitionRoute = RecognitionRoute.localOCR.rawValue
    @AppStorage("ocrEngine") private var ocrEngine = OCREnginePreference.appleVision.rawValue
    @State private var packStatus: String?
    @State private var showingRemoveConfirmation = false
    @StateObject private var packInstaller = OCRPackInstallationViewModel()

    var body: some View {
        Form {
            Section("Default Recognition Route") {
                Picker("Recognition Method", selection: $recognitionRoute) {
                    Text("OCR engine (recommended)").tag(RecognitionRoute.localOCR.rawValue)
                    Text("Multimodal model").tag(RecognitionRoute.multimodal.rawValue)
                    Text("Smart routing").tag(RecognitionRoute.smart.rawValue)
                }
                Text(routeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OCR") {
                Picker("OCR Engine", selection: $ocrEngine) {
                    ForEach(OCREnginePreference.allCases, id: \.rawValue) { engine in
                        Text(engine.displayName).tag(engine.rawValue)
                    }
                }
                TextField("Recognition Language", text: $languages)
                Text(languageDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Auto-merge suspected line wraps", isOn: $mergeWrappedLines)
                if selectedEngine.usesOptionalPack {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(
                                installedLabel,
                                systemImage: packInstaller.installedInfo == nil ? "shippingbox" : "checkmark.circle.fill"
                            )
                            .foregroundStyle(packInstaller.installedInfo == nil ? .orange : .green)
                            Spacer()
                            if selectedEngine == .paddleOCR {
                                Button(installButtonLabel) {
                                    packInstaller.install(selectedEngine)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(packInstaller.isBusy)
                            }
                            Button("Import Manually…") { importPack() }
                                .disabled(packInstaller.isBusy)
                            if packInstaller.installedInfo != nil {
                                Button("Remove", role: .destructive) {
                                    showingRemoveConfirmation = true
                                }
                                .disabled(packInstaller.isBusy)
                            }
                        }
                        if let progress = packInstaller.progress {
                            VStack(alignment: .leading, spacing: 4) {
                                if let fraction = progress.fraction {
                                    ProgressView(value: fraction)
                                } else {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                HStack {
                                    Text(progress.stage.rawValue)
                                    Spacer()
                                    if packInstaller.isBusy {
                                        Button("Cancel") { packInstaller.cancel() }
                                            .buttonStyle(.link)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        if let availability = packInstaller.availability, selectedEngine == .paddleOCR {
                            Text("Available version \(availability.package.version) · \(availability.formattedSize) · \(availability.isLocal ? "bundled locally" : "online download") · Apple Silicon")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let message = packInstaller.message {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(packInstaller.isError ? .red : .secondary)
                        }
                    }
                    if let packStatus {
                        Text(packStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(selectedEngine == .paddleOCR
                         ? "PaddleOCR runs fully offline on-device; once selected it pre-warms and reuses the model in the background, releasing the ~700–800 MB of temporary memory after 5 minutes idle. Installs are still fully verified."
                         : "The enhancement pack must include manifest.json and an executable adapter; it falls back to Apple Vision automatically when not installed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if selectedEngine == .deepSeekOCR2 {
                    DeepSeekOCRConfigurationRows()
                }
            }

            Section("Data Path") {
                Label(
                    selectedEngine.isLocalEngine ? "Standard recognition always runs on-device" : "Screenshots are sent to your configured DeepSeek OCR service",
                    systemImage: selectedEngine.isLocalEngine ? "lock.shield.fill" : "network"
                )
                .foregroundStyle(selectedEngine.isLocalEngine ? .green : .orange)
                Text(selectedEngine.isLocalEngine
                     ? "Low-confidence results only prompt for enhancement — nothing is uploaded silently."
                     : "Uploads happen only when DeepSeek-OCR-2 is selected; switching back to Apple Vision or PaddleOCR restores fully offline recognition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .onAppear {
            packInstaller.refresh(selectedEngine)
            packInstaller.prewarm(selectedEngine)
        }
        .onChange(of: ocrEngine) { _, _ in
            packInstaller.refresh(selectedEngine)
            packInstaller.prewarm(selectedEngine)
        }
        .confirmationDialog(
            "Remove \(selectedEngine.displayName)?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Enhancement Pack", role: .destructive) {
                packInstaller.remove(selectedEngine)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Recognition will immediately fall back to Apple Vision after removal; core features remain available.")
        }
    }

    private var selectedEngine: OCREnginePreference {
        OCREnginePreference(rawValue: ocrEngine) ?? .appleVision
    }

    private func importPack() {
        do {
            if let version = try packInstaller.manager.chooseAndImport(selectedEngine) {
                packStatus = "Imported version \(version)"
                packInstaller.refresh(selectedEngine)
                packInstaller.prewarm(selectedEngine)
            }
        } catch {
            packStatus = error.localizedDescription
        }
    }

    private var installedLabel: String {
        if let info = packInstaller.installedInfo {
            return "Installed version \(info.version)"
        }
        return "Enhancement pack not installed, currently falling back to Apple Vision"
    }

    private var languageDescription: String {
        switch selectedEngine {
        case .appleVision:
            "Enter Apple Vision language codes in priority order, comma-separated."
        case .rapidOCR, .paddleOCR:
            "The enhancement pack uses a built-in Chinese/English model; this language list only applies when falling back to Apple Vision."
        case .deepSeekOCR2:
            "DeepSeek-OCR-2 recognizes multiple languages automatically; these codes are used for result metadata and fallback hints."
        }
    }

    private var installButtonLabel: String {
        guard let installed = packInstaller.installedInfo else { return "Download & Install" }
        guard let available = packInstaller.availability else { return "Reinstall" }
        return available.package.version.compare(installed.version, options: .numeric) == .orderedDescending
            ? "Update to \(available.package.version)"
            : "Reinstall"
    }

    private var routeDescription: String {
        switch RecognitionRoute(rawValue: recognitionRoute) ?? .localOCR {
        case .localOCR:
            selectedEngine == .deepSeekOCR2
                ? "Recognizes via the DeepSeek-OCR-2 service; this screenshot will be sent to your configured endpoint."
                : "Recognizes on-device using the selected OCR engine; falls back to Apple Vision when the enhancement pack isn't installed, no API key needed."
        case .multimodal:
            "Sends the selected image to your configured OpenAI-compatible vision model and copies the model's result."
        case .smart:
            selectedEngine == .deepSeekOCR2
                ? "DeepSeek-OCR-2 is itself a remote recognizer; for \"local-first, upload only on low confidence\" choose Apple Vision or PaddleOCR."
                : "Runs local OCR first; prompts for AI enhancement on low confidence, without silently uploading the image."
        }
    }
}

private struct DeepSeekOCRConfigurationRows: View {
    @AppStorage("deepSeekOCRBaseURL") private var baseURL = ""
    @AppStorage("deepSeekOCRModel") private var model = DeepSeekOCR2Client.latestOfficialModel
    @AppStorage("deepSeekOCRPromptMode") private var promptMode = DeepSeekOCRPromptMode.plainText.rawValue

    @State private var apiKey = ""
    @State private var hasStoredKey = false
    @State private var statusMessage: String?

    private let secretStore = KeychainSecretStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    configurationReady ? "DeepSeek-OCR-2 service configured" : "DeepSeek-OCR-2 service needs configuration",
                    systemImage: configurationReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(configurationReady ? .green : .orange)
                Spacer()
                Link(
                    "Official Model Page",
                    destination: URL(string: "https://huggingface.co/deepseek-ai/DeepSeek-OCR-2")!
                )
                .font(.caption)
            }

            TextField(
                "Service URL",
                text: $baseURL,
                prompt: Text(DeepSeekOCR2Client.recommendedLocalBaseURL)
            )
            TextField("Model Name", text: $model)
            Picker("Output Format", selection: $promptMode) {
                ForEach(DeepSeekOCRPromptMode.allCases, id: \.rawValue) { mode in
                    Text(mode.displayName).tag(mode.rawValue)
                }
            }
            SecureField(hasStoredKey ? "Enter a new key to update (leave blank for local service)" : "API Key (leave blank for local service)", text: $apiKey)

            HStack {
                Button("Fill In Local Default") {
                    baseURL = DeepSeekOCR2Client.recommendedLocalBaseURL
                    model = DeepSeekOCR2Client.latestOfficialModel
                    statusMessage = "Filled in the default vLLM address; make sure the service is running first."
                }
                if hasStoredKey {
                    Button("Remove Key", role: .destructive) { removeKey() }
                }
                Spacer()
                Button(hasStoredKey ? "Update Key" : "Save Key") { saveKey() }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("The current dedicated model is DeepSeek-OCR-2. At about 6.79 GB, the official inference stack targets CUDA, so this app connects to a vLLM/SGLang or compatible service rather than downloading the model silently on your Mac. The DeepSeek official chat API endpoint cannot substitute for an OCR-2 service address.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("The service URL, model name, and key persist across app updates on the same Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            hasStoredKey = secretStore.contains(account: DeepSeekOCRRecognitionService.keychainAccount)
        }
    }

    private var validationMessage: String? {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedModel.isEmpty { return "Please enter the model name actually used by the server." }
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty { return "Please enter the URL of the service where DeepSeek-OCR-2 is deployed." }
        if URLComponents(string: trimmedURL)?.host?.lowercased() == "api.deepseek.com" {
            return "The official DeepSeek chat API doesn't provide a DeepSeek-OCR-2 endpoint; use a self-hosted or compatible service instead."
        }
        return ProviderEndpointValidator().validationMessage(for: trimmedURL)
    }

    private var configurationReady: Bool {
        validationMessage == nil
    }

    private func saveKey() {
        do {
            try secretStore.save(apiKey, account: DeepSeekOCRRecognitionService.keychainAccount)
            apiKey = ""
            hasStoredKey = true
            statusMessage = "DeepSeek OCR API key saved to Keychain."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func removeKey() {
        do {
            try secretStore.delete(account: DeepSeekOCRRecognitionService.keychainAccount)
            apiKey = ""
            hasStoredKey = false
            statusMessage = "DeepSeek OCR API key removed."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

@MainActor
private final class OCRPackInstallationViewModel: ObservableObject {
    let manager = OptionalOCRPackManager()

    @Published var availability: OCRPackAvailability?
    @Published var installedInfo: OCRPackInstalledInfo?
    @Published var progress: OCRPackInstallProgress?
    @Published var message: String?
    @Published var isBusy = false
    @Published var isError = false

    private var installationTask: Task<Void, Never>?

    init() {
        let rawValue = UserDefaults.standard.string(forKey: "ocrEngine")
            ?? OCREnginePreference.appleVision.rawValue
        let initialEngine = OCREnginePreference(rawValue: rawValue) ?? .appleVision
        Task { [weak self] in
            await self?.refreshAvailability(initialEngine)
        }
    }

    func refresh(_ engine: OCREnginePreference) {
        Task { await refreshAvailability(engine) }
    }

    private func refreshAvailability(_ engine: OCREnginePreference) async {
        installedInfo = manager.installedInfo(engine)
        guard engine == .paddleOCR else {
            availability = nil
            return
        }
        do {
            availability = try await manager.availablePackage(for: engine)
            if !isBusy {
                message = nil
                isError = false
            }
        } catch {
            availability = nil
            if installedInfo == nil {
                message = "No one-click installable package found yet; you can also use manual import."
                isError = false
            }
        }
    }

    func install(_ engine: OCREnginePreference) {
        installationTask?.cancel()
        isBusy = true
        isError = false
        message = nil
        progress = .init(stage: .resolving, fraction: nil)
        installationTask = Task {
            do {
                let info = try await manager.installRecommended(for: engine) { [weak self] update in
                    Task { @MainActor in self?.progress = update }
                }
                installedInfo = info
                message = "PaddleOCR \(info.version) installed; warming up the model in the background."
                progress = nil
                manager.prewarm(engine)
            } catch is CancellationError {
                message = "Installation canceled; your existing OCR configuration is unchanged."
                progress = nil
            } catch {
                message = error.localizedDescription
                isError = true
                progress = nil
            }
            isBusy = false
            await refreshAvailability(engine)
        }
    }

    func cancel() {
        installationTask?.cancel()
    }

    func prewarm(_ engine: OCREnginePreference) {
        guard engine == .paddleOCR, manager.isInstalled(engine) else { return }
        manager.prewarm(engine)
    }

    func remove(_ engine: OCREnginePreference) {
        do {
            try manager.remove(engine)
            installedInfo = nil
            message = "Enhancement pack removed; now falling back to Apple Vision."
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }
}
