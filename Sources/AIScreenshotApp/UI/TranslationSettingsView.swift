import SwiftUI
import AIScreenshotCore

struct TranslationSettingsView: View {
    @AppStorage("translationSourceLanguage") private var sourceLanguage = TranslationConfiguration.defaultSourceLanguage
    @AppStorage("translationTargetLanguage") private var targetLanguage = TranslationConfiguration.defaultTargetLanguage
    @AppStorage("translationDefaultMode") private var defaultMode = ScreenshotTranslationMode.textOnly.rawValue
    @AppStorage("translationUsesVisionFallback") private var usesVisionFallback = true

    @State private var state = AIProviderProfileState()
    @State private var eligibleProfiles: [AIProviderProfile] = []
    @State private var selectedProfileID: UUID?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false
    @State private var translationShortcut = HotKeyPreferences().shortcut(for: .translationCapture)

    private let profileStore = AIProviderProfileStore()
    private let translationService = ScreenshotTranslationService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                compactHeader
                modelSection
                languageSection
                behaviorSection
                privacyNote
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.automatic)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: HotKeyPreferences.didChangeNotification)) { _ in
            translationShortcut = HotKeyPreferences().shortcut(for: .translationCapture)
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(TaPalette.cinnabar)
                .frame(width: 38, height: 38)
                .background(TaPalette.cinnabar.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text("Screenshot Translation")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(TaPalette.ink)
                Text("Reuses your saved AI model — just set the language and default behavior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selectedProfile != nil {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 2)
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Model Configuration Used", detail: "Only shows configurations with API key, text model, and vision model all ready.")
            if eligibleProfiles.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No models available for translation")
                            .font(.callout.weight(.semibold))
                        Text("Set up an AI model configuration first — the translation page will reuse it automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Configure AI Model") {
                        NotificationCenter.default.post(name: .openAIModelSettings, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(13)
                .background(surface)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.green)
                        Picker("Model Configuration", selection: $selectedProfileID) {
                            ForEach(eligibleProfiles) { profile in
                                Text(profile.trimmedName).tag(Optional(profile.id))
                            }
                        }
                        .onChange(of: selectedProfileID) { _, newValue in
                            selectTranslationProfile(newValue)
                        }
                        Spacer()
                        Label("Available", systemImage: "circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }

                    if let profile = selectedProfile {
                        HStack(spacing: 10) {
                            modelValue("Text", profile.textModel)
                            Divider().frame(height: 24)
                            modelValue("Vision", profile.visionModel)
                            Spacer()
                        }
                    }

                    HStack {
                        if state.profiles.count > eligibleProfiles.count {
                            Text("\(state.profiles.count - eligibleProfiles.count) more configuration(s) not yet complete.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Manage Models") {
                            NotificationCenter.default.post(name: .openAIModelSettings, object: nil)
                        }
                        Button("Test") { testSelectedProfile() }
                            .disabled(isTesting || selectedProfile == nil)
                    }
                    .controlSize(.small)
                }
                .padding(13)
                .background(surface)
            }

            if isTesting {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Testing text and vision capabilities…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let statusMessage {
                Label(statusMessage, systemImage: statusIsError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(statusIsError ? .red : .green)
                    .textSelection(.enabled)
            }
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Translation Language", detail: "Auto-detects the screenshot's language by default — you can also type another language.")
            VStack(spacing: 8) {
                languageRow(title: "Source Language", value: $sourceLanguage, presets: ["Auto-detect", "English", "Simplified Chinese", "Japanese", "Korean"])
                languageRow(title: "Target Language", value: $targetLanguage, presets: ["Simplified Chinese", "English", "Traditional Chinese", "Japanese", "Korean", "Spanish"])
            }
            .padding(12)
            .background(surface)
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Default Behavior", detail: "Clicking \u{201c}Translate\u{201d} in the screenshot toolbar runs immediately, with no extra confirmation.")
            VStack(alignment: .leading, spacing: 9) {
                Picker("Default Translation Mode", selection: $defaultMode) {
                    ForEach(ScreenshotTranslationMode.allCases, id: \.rawValue) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                Toggle("Use the vision model to read the screenshot when local OCR confidence is low", isOn: $usesVisionFallback)
                Text("The \(translationShortcut.displayText) shortcut always runs \u{201c}Translate Text and Copy\u{201d}.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(surface)
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
            Text("The API key is stored only in this Mac's Keychain and persists across app updates; the selected screenshot is only sent when you translate or read it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 3)
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(TaPalette.ink)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func modelValue(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
        }
    }

    private func languageRow(title: String, value: Binding<String>, presets: [String]) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField(title, text: value)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 360)
                Menu("Presets") {
                    ForEach(presets, id: \.self) { language in
                        Button(language) { value.wrappedValue = language }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var surface: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(TaPalette.elevatedPaper.opacity(0.84))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(TaPalette.hairline, lineWidth: 1) }
    }

    private var selectedProfile: AIProviderProfile? {
        eligibleProfiles.first { $0.id == selectedProfileID }
    }

    private func reload() {
        do {
            state = try profileStore.loadState()
            eligibleProfiles = profileStore.eligibleTranslationProfiles(in: state)
            if eligibleProfiles.contains(where: { $0.id == state.translationProfileID }) {
                selectedProfileID = state.translationProfileID
            } else {
                selectedProfileID = eligibleProfiles.first?.id
                if let selectedProfileID {
                    _ = try profileStore.setTranslationProfile(id: selectedProfileID)
                }
            }
        } catch {
            status(error.localizedDescription, isError: true)
        }
    }

    private func selectTranslationProfile(_ id: UUID?) {
        do {
            state = try profileStore.setTranslationProfile(id: id)
            status("Translation model switched.")
        } catch {
            status(error.localizedDescription, isError: true)
        }
    }

    private func testSelectedProfile() {
        guard let profile = selectedProfile else { return }
        isTesting = true
        status("Testing…")
        Task {
            do {
                _ = try await translationService.testTextModel(profile: profile)
                _ = try await translationService.testVisionModel(profile: profile)
                status("Both text and vision models are working.")
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
