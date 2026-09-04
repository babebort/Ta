import AppKit
import SwiftUI
import AIScreenshotCore

struct ModelSettingsView: View {
    @AppStorage("multimodalTaskTemplate") private var taskTemplate = MultimodalTaskTemplate.general.rawValue

    @State private var state = AIProviderProfileState()
    @State private var selectedProfileID: UUID?
    @State private var draft = AIProviderProfile(name: "New Model")
    @State private var apiKey = ""
    @State private var hasStoredKey = false
    @State private var selectedPreset = ModelProviderPreset.custom
    @State private var providerChosen = false
    @State private var currentStep = ModelSetupStep.provider
    @State private var isCreatingProfile = false
    @State private var isShowingAdvanced = false
    @State private var isTesting = false
    @State private var isConfirmingDelete = false
    @State private var statusMessage: String?
    @State private var statusStyle = ModelConfigurationStatusStyle.neutral

    private let profileStore = AIProviderProfileStore()
    private let recognitionService = MultimodalRecognitionService()
    private let translationService = ScreenshotTranslationService()

    private var setupProgress: ModelSetupProgress {
        ModelSetupProgress(
            hasEndpoint: !draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasAPIKey: hasStoredKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasVisionModel: selectedPreset.supportsVisionDirectly ? draft.hasVisionModel : true,
            hasTextModel: draft.hasTextModel
        )
    }

    private var isDraftSaved: Bool {
        state.profiles.contains { $0.id == draft.id }
    }

    private var activeReadyProfiles: [AIProviderProfile] {
        state.profiles.filter {
            $0.validationMessage() == nil && profileStore.hasAPIKey(for: $0.id)
        }
    }

    private var translationReadyProfiles: [AIProviderProfile] {
        profileStore.eligibleTranslationProfiles(in: state)
    }

    var body: some View {
        VStack(spacing: 0) {
            compactHeader
            Divider().overlay(TaPalette.hairline)
            HStack(spacing: 0) {
                progressRail
                Divider().overlay(TaPalette.hairline)
                stepContent
            }
        }
        .background(TaPalette.elevatedPaper.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TaPalette.hairline, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { reload() }
        .confirmationDialog(
            "Delete \u{201C}\(draft.trimmedName)\u{201D}?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Configuration and API Key", role: .destructive, action: deleteSelectedProfile)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes this model configuration; other configurations are unaffected.")
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TaPalette.cinnabar)
                .frame(width: 30, height: 30)
                .background(TaPalette.cinnabar.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text("AI Model")
                    .font(.headline)
                    .foregroundStyle(TaPalette.ink)
                Text("Set up once, use for AI recognition and screenshot translation")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.profiles.isEmpty {
                Text("Not configured yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                profileMenu
            }
            Button("Add", systemImage: "plus", action: beginNewProfile)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private var profileMenu: some View {
        Menu {
            ForEach(state.profiles) { profile in
                Button {
                    select(profile.id)
                } label: {
                    if profile.id == selectedProfileID {
                        Label(profile.trimmedName, systemImage: "checkmark")
                    } else {
                        Text(profile.trimmedName)
                    }
                }
            }
            Divider()
            Button("Add Another", systemImage: "plus", action: beginNewProfile)
        } label: {
            HStack(spacing: 5) {
                Text(isCreatingProfile ? "New Configuration" : draft.trimmedName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(TaPalette.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(TaPalette.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(TaPalette.hairline, lineWidth: 1) }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var progressRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ModelSetupStep.allCases.enumerated()), id: \.element) { index, step in
                HStack(alignment: .top, spacing: 9) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(step == currentStep ? TaPalette.cinnabar : TaPalette.paper)
                                .overlay {
                                    Circle().stroke(
                                        step.rawValue < currentStep.rawValue ? TaPalette.cinnabar.opacity(0.35) : TaPalette.hairline,
                                        lineWidth: 1
                                    )
                                }
                            if step.rawValue < currentStep.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(TaPalette.cinnabar)
                            } else {
                                Text("\(step.rawValue + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(step == currentStep ? Color.white : TaPalette.mutedInk)
                            }
                        }
                        .frame(width: 24, height: 24)

                        if index < ModelSetupStep.allCases.count - 1 {
                            Rectangle()
                                .fill(step.rawValue < currentStep.rawValue ? TaPalette.cinnabar.opacity(0.24) : TaPalette.hairline)
                                .frame(width: 1, height: 52)
                        }
                    }
                    Text(step.title)
                        .font(.caption.weight(step == currentStep ? .semibold : .medium))
                        .foregroundStyle(step == currentStep ? TaPalette.cinnabar : TaPalette.mutedInk)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            if !state.profiles.isEmpty && currentStep == .provider {
                Menu("I've already set this up") {
                    ForEach(state.profiles) { profile in
                        Button(profile.trimmedName) { select(profile.id) }
                    }
                }
                .menuStyle(.borderlessButton)
                .font(.caption)
                .foregroundStyle(TaPalette.cinnabar)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(width: 154)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(TaPalette.paper.opacity(0.40))
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .provider:
            providerSelectionStep
        case .credentials:
            credentialSetupStep
        case .complete:
            completionStep
        }
    }

    private var providerSelectionStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose an AI Provider")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(TaPalette.ink)
                Text("Pick the service you use, and Ta will auto-fill the endpoint and recommended models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.vertical) {
                VStack(spacing: 6) {
                    ForEach(ModelProviderPreset.guidedCases) { preset in
                        providerRow(preset)
                    }
                }
            }
            .scrollIndicators(.visible)

            HStack {
                Spacer()
                Button("Next") {
                    withAnimation(.easeOut(duration: 0.16)) { currentStep = .credentials }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!providerChosen)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func providerRow(_ preset: ModelProviderPreset) -> some View {
        let isSelected = providerChosen && selectedPreset == preset
        return Button { apply(preset) } label: {
            HStack(spacing: 10) {
                ProviderBrandIcon(preset: preset, size: 23)
                    .frame(width: 25)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 7) {
                        Text(preset.title)
                            .font(.callout.weight(.semibold))
                        if preset.isRecommended {
                            Text("Recommended")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(TaPalette.cinnabar.opacity(0.10), in: Capsule())
                        }
                    }
                    Text(preset.guidedSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(TaPalette.cinnabar)
                }
            }
            .foregroundStyle(isSelected ? TaPalette.cinnabar : TaPalette.ink)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? TaPalette.cinnabar.opacity(0.07) : TaPalette.paper.opacity(0.42))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? TaPalette.cinnabar.opacity(0.72) : TaPalette.hairline, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isTesting)
    }

    private var credentialSetupStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Configure \(selectedPreset.title)")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(TaPalette.ink)
                            Text("Enter your API key; recommended models are pre-filled and can be changed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isDraftSaved {
                            profileActionsMenu
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("API Key")
                            .font(.callout.weight(.semibold))
                        SecureField(hasStoredKey ? "Saved; leave blank to keep it" : "Paste your API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isTesting)
                        Label(
                            hasStoredKey ? "Securely stored in this Mac's keychain" : "Stored only in this Mac's keychain, never written to a plain config file",
                            systemImage: hasStoredKey ? "checkmark.shield.fill" : "lock.shield"
                        )
                        .font(.caption2)
                        .foregroundStyle(hasStoredKey ? .green : .secondary)
                    }
                    .padding(12)
                    .background(compactSurface)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommended Models")
                            .font(.callout.weight(.semibold))
                        if selectedPreset.supportsVisionDirectly {
                            modelField(title: "Vision Model", value: $draft.visionModel, suggestion: selectedPreset.suggestedVisionModel)
                        }
                        modelField(title: "Text Model", value: $draft.textModel, suggestion: selectedPreset.suggestedTextModel)
                        if !selectedPreset.supportsVisionDirectly {
                            Label(
                                "The official Coding Plan connection doesn't support image input; this configuration won't appear in AI recognition or screenshot translation lists.",
                                systemImage: "info.circle.fill"
                            )
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        }
                    }
                    .padding(12)
                    .background(compactSurface)

                    advancedSettings
                    validationAndStatus
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }

            Divider().overlay(TaPalette.hairline)
            HStack(spacing: 9) {
                Button("Back") {
                    withAnimation(.easeOut(duration: 0.16)) { currentStep = .provider }
                }
                Spacer()
                if isTesting {
                    ProgressView().controlSize(.small)
                    Text("Verifying\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Save Only", action: saveOnly)
                    .disabled(isTesting || !setupProgress.isComplete)
                Button("Test and Save", action: saveAndTest)
                    .buttonStyle(.borderedProminent)
                    .disabled(isTesting || !setupProgress.isComplete)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func modelField(title: String, value: Binding<String>, suggestion: String?) -> some View {
        LabeledContent(title) {
            HStack(spacing: 7) {
                TextField(title, text: value)
                    .textFieldStyle(.roundedBorder)
                if let suggestion {
                    Button("Use Suggested") { value.wrappedValue = suggestion }
                        .controlSize(.small)
                }
            }
            .frame(minWidth: 360)
        }
    }

    private var advancedSettings: some View {
        DisclosureGroup(isExpanded: $isShowingAdvanced) {
            VStack(alignment: .leading, spacing: 9) {
                Divider().overlay(TaPalette.hairline)
                LabeledContent("Configuration Name") {
                    TextField("e.g. DeepSeek Everyday", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 350)
                }
                LabeledContent("API Protocol") {
                    Picker("API Protocol", selection: $draft.providerKind) {
                        ForEach(VisionProviderKind.allCases, id: \.rawValue) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
                LabeledContent("Endpoint URL") {
                    TextField("https://api.example.com/v1", text: $draft.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 350)
                }
                LabeledContent("Default Recognition Task") {
                    Picker("Default Recognition Task", selection: $taskTemplate) {
                        ForEach(MultimodalTaskTemplate.allCases, id: \.rawValue) { task in
                            Text(task.displayName).tag(task.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
                if hasStoredKey {
                    Button("Remove This Configuration's API Key", role: .destructive, action: removeKey)
                        .controlSize(.small)
                        .disabled(isTesting)
                }
            }
            .padding(.top, 7)
        } label: {
            Label("Advanced Settings \u{00B7} Name, Endpoint, and Default Task", systemImage: "slider.horizontal.3")
                .font(.callout.weight(.medium))
                .foregroundStyle(TaPalette.ink)
        }
        .padding(12)
        .background(compactSurface)
    }

    @ViewBuilder
    private var validationAndStatus: some View {
        if let validation = draft.validationMessage(
            requiresVisionModel: selectedPreset.supportsVisionDirectly,
            requiresTextModel: true
        ) {
            Label(validation, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if statusMessage == nil {
            Label(
                selectedPreset.supportsVisionDirectly
                    ? "This configuration can be used for both AI recognition and screenshot translation."
                    : "This configuration can be used for text requests; Coding Plan has no direct screenshot vision support.",
                systemImage: "checkmark.circle.fill"
            )
                .font(.caption)
                .foregroundStyle(.green)
        }
        if let statusMessage {
            Label(statusMessage, systemImage: statusStyle.icon)
                .font(.caption)
                .foregroundStyle(statusStyle.color)
                .textSelection(.enabled)
        }
    }

    private var completionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasVerifiedConnection ? "Connected Successfully" : "Configuration Saved")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(TaPalette.ink)
                    Text(
                        hasVerifiedConnection
                            ? "Saved locally on this Mac; you won't need to re-enter it after future updates."
                            : "The model info is complete; it's recommended to test the connection first."
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                profileActionsMenu
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProviderBrandIcon(preset: selectedPreset, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.trimmedName)
                            .font(.headline)
                        Text(selectedPreset.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(selectedPreset.supportsVisionDirectly ? "Available" : "Text Only", systemImage: "circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selectedPreset.supportsVisionDirectly ? .green : .orange)
                }
                Divider().overlay(TaPalette.hairline)
                if selectedPreset.supportsVisionDirectly {
                    modelSummaryRow("Vision Model", draft.visionModel)
                }
                modelSummaryRow("Text Model", draft.textModel)
                HStack(spacing: 18) {
                    if selectedPreset.supportsVisionDirectly {
                        Label("AI Recognition", systemImage: "photo")
                        Label("Screenshot Translation", systemImage: "character.book.closed")
                    } else {
                        Label("Text Model Configuration", systemImage: "text.bubble")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(TaPalette.mutedInk)
            }
            .padding(14)
            .background(compactSurface)

            if selectedPreset.supportsVisionDirectly {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Apply to Features")
                        .font(.callout.weight(.semibold))
                    LabeledContent("Recognition Default") {
                        Picker("Recognition Default", selection: activeProfileBinding) {
                            ForEach(activeReadyProfiles) { profile in
                                Text(profile.trimmedName).tag(Optional(profile.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 250)
                    }
                    LabeledContent("Used for Translation") {
                        Picker("Used for Translation", selection: translationProfileBinding) {
                            ForEach(translationReadyProfiles) { profile in
                                Text(profile.trimmedName).tag(Optional(profile.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 250)
                    }
                }
                .padding(14)
                .background(compactSurface)
            } else {
                Label(
                    "Zhipu Coding Plan's direct connection only supports text models, so it can't be set as the AI recognition default or appear in the screenshot translation model list.",
                    systemImage: "info.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(14)
                .background(compactSurface)
            }

            if let statusMessage {
                Label(statusMessage, systemImage: statusStyle.icon)
                    .font(.caption)
                    .foregroundStyle(statusStyle.color)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
            HStack {
                Button("Add Another", action: beginNewProfile)
                Spacer()
                Button(hasVerifiedConnection ? "Test Again" : "Test Connection") {
                    currentStep = .credentials
                    saveAndTest()
                }
                .disabled(isTesting)
                Button("Done") { NSApp.keyWindow?.performClose(nil) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func modelSummaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(TaPalette.ink)
                .lineLimit(1)
            Spacer()
        }
    }

    private var hasVerifiedConnection: Bool {
        draft.visionVerifiedAt != nil
    }

    private var profileActionsMenu: some View {
        Menu {
            Button("Duplicate Configuration", systemImage: "doc.on.doc", action: duplicateSelectedProfile)
            if selectedPreset.supportsVisionDirectly, state.activeProfileID != draft.id {
                Button("Set as AI Recognition Default", systemImage: "checkmark.circle", action: setAsActive)
            }
            Divider()
            Button("Delete Configuration", systemImage: "trash", role: .destructive) {
                isConfirmingDelete = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var compactSurface: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(TaPalette.paper.opacity(0.54))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(TaPalette.hairline, lineWidth: 1) }
    }

    private var activeProfileBinding: Binding<UUID?> {
        Binding(
            get: { state.activeProfileID },
            set: { id in
                do {
                    state = try profileStore.setActiveProfile(id: id)
                    showStatus("Updated the AI recognition default model.", style: .success)
                } catch {
                    showStatus(error.localizedDescription, style: .error)
                }
            }
        )
    }

    private var translationProfileBinding: Binding<UUID?> {
        Binding(
            get: { state.translationProfileID },
            set: { id in
                do {
                    state = try profileStore.setTranslationProfile(id: id)
                    showStatus("Updated the screenshot translation model.", style: .success)
                } catch {
                    showStatus(error.localizedDescription, style: .error)
                }
            }
        )
    }

    private func reload(selecting requestedID: UUID? = nil) {
        do {
            state = try profileStore.loadState()
            let target = requestedID ?? selectedProfileID ?? state.activeProfileID ?? state.profiles.first?.id
            if let target, state.profiles.contains(where: { $0.id == target }) {
                select(target)
            } else {
                beginNewProfile()
            }
        } catch {
            showStatus(error.localizedDescription, style: .error)
            beginNewProfile()
        }
    }

    private func select(_ id: UUID) {
        guard let profile = state.profiles.first(where: { $0.id == id }) else { return }
        selectedProfileID = id
        draft = profile
        apiKey = ""
        hasStoredKey = profileStore.hasAPIKey(for: id)
        selectedPreset = ModelProviderPreset.matching(
            providerKind: profile.providerKind.rawValue,
            baseURL: profile.baseURL
        )
        providerChosen = !profile.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        isCreatingProfile = false
        isShowingAdvanced = selectedPreset.requiresCustomEndpoint
        statusMessage = nil
        currentStep = ModelSetupStep.recommended(for: setupProgress)
    }

    private func beginNewProfile() {
        let profile = AIProviderProfile(name: "New Model \(state.profiles.count + 1)")
        selectedProfileID = profile.id
        draft = profile
        apiKey = ""
        hasStoredKey = false
        selectedPreset = .custom
        providerChosen = false
        isCreatingProfile = true
        isShowingAdvanced = false
        statusMessage = nil
        currentStep = .provider
    }

    private func duplicateSelectedProfile() {
        guard isDraftSaved else { return }
        var copy = draft
        copy.id = UUID()
        copy.name = "\(draft.trimmedName) Copy"
        copy.visionVerifiedAt = nil
        do {
            let key = try? profileStore.apiKey(for: draft.id)
            _ = try profileStore.saveProfile(copy, apiKey: key)
            reload(selecting: copy.id)
            showStatus("Configuration duplicated.", style: .success)
        } catch {
            showStatus(error.localizedDescription, style: .error)
        }
    }

    private func deleteSelectedProfile() {
        guard isDraftSaved else {
            beginNewProfile()
            return
        }
        do {
            state = try profileStore.deleteProfile(id: draft.id)
            reload()
        } catch {
            showStatus(error.localizedDescription, style: .error)
        }
    }

    private func setAsActive() {
        do {
            try persistDraft()
            state = try profileStore.setActiveProfile(id: draft.id)
            showStatus("Set as the AI recognition default configuration.", style: .success)
        } catch {
            showStatus(error.localizedDescription, style: .error)
        }
    }

    private func apply(_ preset: ModelProviderPreset) {
        let previousPreset = selectedPreset
        let wasGenericName = draft.trimmedName.isEmpty
            || draft.trimmedName.hasPrefix("New Model")
            || draft.trimmedName == previousPreset.suggestedConfigurationName
        selectedPreset = preset
        providerChosen = true
        draft.providerKind = preset.providerKind
        if preset != .custom {
            draft.baseURL = preset.baseURL
            draft.visionModel = preset.suggestedVisionModel ?? ""
            draft.textModel = preset.suggestedTextModel ?? ""
        } else {
            draft.baseURL = ""
            draft.visionModel = ""
            draft.textModel = ""
        }
        if wasGenericName {
            draft.name = preset.suggestedConfigurationName
        }
        isShowingAdvanced = preset.requiresCustomEndpoint
        draft.visionVerifiedAt = nil
        statusMessage = nil
    }

    private func saveOnly() {
        do {
            try persistDraft()
            showStatus("Configuration saved.", style: .success)
        } catch {
            showStatus(error.localizedDescription, style: .error)
        }
    }

    private func saveAndTest() {
        do {
            try persistDraft()
        } catch {
            showStatus(error.localizedDescription, style: .error)
            return
        }
        isTesting = true
        showStatus(
            selectedPreset.supportsVisionDirectly
                ? "Saved, testing text and vision models\u{2026}"
                : "Saved, testing the Coding Plan text model\u{2026}",
            style: .neutral
        )
        Task {
            do {
                let textResponse = try await translationService.testTextModel(profile: draft)
                draft.visionVerifiedAt = Date()
                let successMessage: String
                if selectedPreset.supportsVisionDirectly {
                    let visionResponse = try await recognitionService.testConnection(profile: draft)
                    successMessage = "Both models connected successfully. Text: \(textResponse.prefix(24)) \u{00B7} Vision: \(visionResponse.prefix(24))"
                } else {
                    successMessage = "Coding Plan text model connected successfully: \(textResponse.prefix(36))"
                }
                _ = try profileStore.saveProfile(draft)
                reload(selecting: draft.id)
                showStatus(successMessage, style: .success)
                currentStep = .complete
            } catch {
                showStatus("Configuration saved, but the connection test failed: \(error.localizedDescription)", style: .error)
                currentStep = .credentials
            }
            isTesting = false
        }
    }

    private func persistDraft() throws {
        if let validation = draft.validationMessage(
            requiresVisionModel: selectedPreset.supportsVisionDirectly,
            requiresTextModel: true
        ) {
            throw ModelConfigurationError.invalid(validation)
        }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty || hasStoredKey else {
            throw ModelConfigurationError.invalid("Please paste an API key.")
        }
        state = try profileStore.saveProfile(draft, apiKey: trimmedKey.isEmpty ? nil : trimmedKey)
        apiKey = ""
        hasStoredKey = true
        isCreatingProfile = false
    }

    private func removeKey() {
        do {
            try profileStore.removeAPIKey(for: draft.id)
            apiKey = ""
            hasStoredKey = false
            showStatus("API key removed; this configuration is temporarily unavailable.", style: .neutral)
        } catch {
            showStatus(error.localizedDescription, style: .error)
        }
    }

    private func showStatus(_ message: String, style: ModelConfigurationStatusStyle) {
        statusMessage = message
        statusStyle = style
    }
}

private struct ProviderBrandIcon: View {
    let preset: ModelProviderPreset
    let size: CGFloat

    var body: some View {
        Group {
            if let brandImage {
                Image(nsImage: brandImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: preset.icon)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
                    .foregroundStyle(TaPalette.cinnabar)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }

    private var brandImage: NSImage? {
        guard let name = preset.brandAssetName else { return nil }
        let subdirectory = "Brand/Providers"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: subdirectory) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

enum ModelProviderPreset: String, CaseIterable, Identifiable {
    case deepSeek, openAI, openRouter, anthropic, gemini
    case zhipuAPI, zhipuCodingPlan
    case azure, custom

    static let guidedCases: [ModelProviderPreset] = [
        .zhipuAPI,
        .zhipuCodingPlan,
        .deepSeek,
        .openAI,
        .gemini,
        .anthropic,
        .openRouter,
        .azure,
        .custom,
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .anthropic: "Claude"
        case .gemini: "Gemini"
        case .zhipuAPI: "Zhipu API"
        case .zhipuCodingPlan: "Zhipu Coding Plan"
        case .azure: "Azure"
        case .custom: "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .deepSeek: "Auto-fills common models"
        case .openAI: "OpenAI's official API"
        case .openRouter: "Unified access to many models"
        case .anthropic: "Anthropic Messages"
        case .gemini: "Google AI API"
        case .zhipuAPI: "General open platform API"
        case .zhipuCodingPlan: "Dedicated coding-plan endpoint"
        case .azure: "Enter your own resource endpoint"
        case .custom: "Local or compatible service"
        }
    }

    var guidedSubtitle: String {
        switch self {
        case .deepSeek: "Natural Chinese understanding, good for recognition and translation"
        case .openAI: "Strong general ability, good for complex screenshots"
        case .gemini: "Google vision and text models"
        case .anthropic: "Anthropic vision and text models"
        case .openRouter: "One API for many models"
        case .zhipuAPI: "General quota, supports recognition and translation"
        case .zhipuCodingPlan: "Subscription plan, text-model direct connection only"
        case .azure: "Enterprise Azure OpenAI service"
        case .custom: "Local model or compatible API"
        }
    }

    var icon: String {
        switch self {
        case .deepSeek: "brain.head.profile"
        case .openAI: "bolt.circle"
        case .openRouter: "arrow.triangle.branch"
        case .anthropic: "text.bubble"
        case .gemini: "diamond"
        case .zhipuAPI, .zhipuCodingPlan: "z.square"
        case .azure: "cloud"
        case .custom: "slider.horizontal.3"
        }
    }

    var brandAssetName: String? {
        switch self {
        case .deepSeek: "deepseek"
        case .openAI: "openai"
        case .openRouter: "openrouter"
        case .anthropic: "claude"
        case .gemini: "gemini"
        case .zhipuAPI, .zhipuCodingPlan: "zhipu"
        case .azure, .custom: nil
        }
    }

    var providerKind: VisionProviderKind {
        switch self {
        case .anthropic: .anthropic
        case .gemini: .googleGemini
        case .azure: .azureOpenAI
        default: .openAICompatible
        }
    }

    var baseURL: String {
        switch self {
        case .deepSeek: "https://api.deepseek.com"
        case .openAI: "https://api.openai.com/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .anthropic: "https://api.anthropic.com"
        case .gemini: "https://generativelanguage.googleapis.com"
        case .zhipuAPI: "https://open.bigmodel.cn/api/paas/v4"
        case .zhipuCodingPlan: "https://open.bigmodel.cn/api/coding/paas/v4"
        case .azure, .custom: ""
        }
    }

    var suggestedVisionModel: String? {
        switch self {
        case .deepSeek: TranslationConfiguration.defaultVisionModel
        case .zhipuAPI: "glm-5v-turbo"
        default: nil
        }
    }

    var suggestedTextModel: String? {
        switch self {
        case .deepSeek: TranslationConfiguration.defaultTextModel
        case .zhipuAPI, .zhipuCodingPlan: "glm-5.2"
        default: nil
        }
    }

    var supportsVisionDirectly: Bool { self != .zhipuCodingPlan }

    var isRecommended: Bool {
        self == .zhipuAPI || self == .zhipuCodingPlan || self == .deepSeek
    }

    var suggestedConfigurationName: String {
        self == .custom ? "Custom Model" : "\(title) Everyday"
    }

    var requiresCustomEndpoint: Bool { self == .azure || self == .custom }

    static func matching(providerKind: String, baseURL: String) -> ModelProviderPreset {
        let url = baseURL.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if url.contains("api.deepseek.com") { return .deepSeek }
        if url.contains("api.openai.com") { return .openAI }
        if url.contains("openrouter.ai") { return .openRouter }
        if url.contains("api.anthropic.com") { return .anthropic }
        if url.contains("generativelanguage.googleapis.com") { return .gemini }
        if url.contains("open.bigmodel.cn/api/coding") { return .zhipuCodingPlan }
        if url.contains("open.bigmodel.cn/api/paas") { return .zhipuAPI }
        if providerKind == VisionProviderKind.azureOpenAI.rawValue { return .azure }
        return .custom
    }
}

enum ModelSetupStep: Int, CaseIterable, Equatable {
    case provider
    case credentials
    case complete

    var title: String {
        switch self {
        case .provider: "Choose Provider"
        case .credentials: "Enter API Key"
        case .complete: "Test and Save"
        }
    }

    static func recommended(for progress: ModelSetupProgress) -> ModelSetupStep {
        if !progress.hasEndpoint { return .provider }
        if !progress.isComplete { return .credentials }
        return .complete
    }
}

struct ModelSetupProgress: Equatable {
    let hasEndpoint: Bool
    let hasAPIKey: Bool
    let hasVisionModel: Bool
    let hasTextModel: Bool

    var completedSteps: Int {
        [hasEndpoint, hasAPIKey, hasVisionModel, hasTextModel].filter { $0 }.count
    }

    var isComplete: Bool {
        hasEndpoint && hasAPIKey && hasVisionModel && hasTextModel
    }

    var nextStep: String {
        if !hasEndpoint { return "Choose a provider first" }
        if !hasAPIKey { return "Next, enter your API key" }
        if !hasVisionModel { return "Enter the vision model" }
        if !hasTextModel { return "Finally, enter the text model" }
        return "Ready to save and test the connection"
    }
}

private enum ModelConfigurationStatusStyle {
    case neutral, success, error

    var icon: String {
        switch self {
        case .neutral: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .neutral: TaPalette.mutedInk
        case .success: .green
        case .error: .red
        }
    }
}

private enum ModelConfigurationError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}
