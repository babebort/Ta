import AppKit
import SwiftUI
import AIScreenshotCore

struct ModelSettingsView: View {
    @AppStorage("multimodalTaskTemplate") private var taskTemplate = MultimodalTaskTemplate.general.rawValue

    @State private var state = AIProviderProfileState()
    @State private var selectedProfileID: UUID?
    @State private var draft = AIProviderProfile(name: "新模型")
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
            "删除“\(draft.trimmedName)”？",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("删除配置和 API Key", role: .destructive, action: deleteSelectedProfile)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只删除这套模型配置，不会影响其他配置。")
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
                Text("AI 模型")
                    .font(.headline)
                    .foregroundStyle(TaPalette.ink)
                Text("配置一次，即可用于 AI 识图和截图翻译")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.profiles.isEmpty {
                Text("尚未配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                profileMenu
            }
            Button("新增", systemImage: "plus", action: beginNewProfile)
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
            Button("添加另一套", systemImage: "plus", action: beginNewProfile)
        } label: {
            HStack(spacing: 5) {
                Text(isCreatingProfile ? "新配置" : draft.trimmedName)
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
                Menu("我已经配置过") {
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
                Text("选择 AI 服务商")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(TaPalette.ink)
                Text("选择你常用的服务，拓会自动填写接口和推荐模型。")
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
                Button("下一步") {
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
                            Text("推荐")
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
                            Text("配置 \(selectedPreset.title)")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(TaPalette.ink)
                            Text("填写 API Key；推荐模型已自动带入，可按需修改。")
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
                        SecureField(hasStoredKey ? "已保存；不更换可以留空" : "粘贴 API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isTesting)
                        Label(
                            hasStoredKey ? "已安全保存在本机钥匙串" : "仅保存在这台 Mac 的钥匙串，不会写入普通配置文件",
                            systemImage: hasStoredKey ? "checkmark.shield.fill" : "lock.shield"
                        )
                        .font(.caption2)
                        .foregroundStyle(hasStoredKey ? .green : .secondary)
                    }
                    .padding(12)
                    .background(compactSurface)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("推荐模型")
                            .font(.callout.weight(.semibold))
                        if selectedPreset.supportsVisionDirectly {
                            modelField(title: "视觉模型", value: $draft.visionModel, suggestion: selectedPreset.suggestedVisionModel)
                        }
                        modelField(title: "文字模型", value: $draft.textModel, suggestion: selectedPreset.suggestedTextModel)
                        if !selectedPreset.supportsVisionDirectly {
                            Label(
                                "Coding Plan 官方直连不支持图片输入；这套配置不会出现在 AI 识图或截图翻译列表中。",
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
                Button("上一步") {
                    withAnimation(.easeOut(duration: 0.16)) { currentStep = .provider }
                }
                Spacer()
                if isTesting {
                    ProgressView().controlSize(.small)
                    Text("正在验证…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("仅保存", action: saveOnly)
                    .disabled(isTesting || !setupProgress.isComplete)
                Button("测试并保存", action: saveAndTest)
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
                    Button("推荐") { value.wrappedValue = suggestion }
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
                LabeledContent("配置名称") {
                    TextField("例如：DeepSeek 日常", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 350)
                }
                LabeledContent("接口协议") {
                    Picker("接口协议", selection: $draft.providerKind) {
                        ForEach(VisionProviderKind.allCases, id: \.rawValue) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
                LabeledContent("服务地址") {
                    TextField("https://api.example.com/v1", text: $draft.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 350)
                }
                LabeledContent("识图默认任务") {
                    Picker("识图默认任务", selection: $taskTemplate) {
                        ForEach(MultimodalTaskTemplate.allCases, id: \.rawValue) { task in
                            Text(task.displayName).tag(task.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
                if hasStoredKey {
                    Button("移除这套配置的 API Key", role: .destructive, action: removeKey)
                        .controlSize(.small)
                        .disabled(isTesting)
                }
            }
            .padding(.top, 7)
        } label: {
            Label("高级设置 · 配置名称、服务地址与默认任务", systemImage: "slider.horizontal.3")
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
                    ? "这套配置可以同时用于 AI 识图和截图翻译。"
                    : "这套配置可用于文字请求；Coding Plan 不提供截图视觉直连。",
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
                    Text(hasVerifiedConnection ? "连接成功" : "配置已保存")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(TaPalette.ink)
                    Text(
                        hasVerifiedConnection
                            ? "配置已保存到本机，后续升级不需要重新填写。"
                            : "模型信息已经完整，建议先测试一次连接。"
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
                    Label(selectedPreset.supportsVisionDirectly ? "可用" : "仅文字", systemImage: "circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selectedPreset.supportsVisionDirectly ? .green : .orange)
                }
                Divider().overlay(TaPalette.hairline)
                if selectedPreset.supportsVisionDirectly {
                    modelSummaryRow("视觉模型", draft.visionModel)
                }
                modelSummaryRow("文字模型", draft.textModel)
                HStack(spacing: 18) {
                    if selectedPreset.supportsVisionDirectly {
                        Label("AI 识图", systemImage: "photo")
                        Label("截图翻译", systemImage: "character.book.closed")
                    } else {
                        Label("文字模型配置", systemImage: "text.bubble")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(TaPalette.mutedInk)
            }
            .padding(14)
            .background(compactSurface)

            if selectedPreset.supportsVisionDirectly {
                VStack(alignment: .leading, spacing: 10) {
                    Text("应用到功能")
                        .font(.callout.weight(.semibold))
                    LabeledContent("识图默认") {
                        Picker("识图默认", selection: activeProfileBinding) {
                            ForEach(activeReadyProfiles) { profile in
                                Text(profile.trimmedName).tag(Optional(profile.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 250)
                    }
                    LabeledContent("翻译使用") {
                        Picker("翻译使用", selection: translationProfileBinding) {
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
                    "智谱 Coding Plan 直连仅支持文字模型，因此不会被设为 AI 识图默认，也不会出现在截图翻译模型列表。",
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
                Button("添加另一套", action: beginNewProfile)
                Spacer()
                Button(hasVerifiedConnection ? "重新测试" : "测试连接") {
                    currentStep = .credentials
                    saveAndTest()
                }
                .disabled(isTesting)
                Button("完成") { NSApp.keyWindow?.performClose(nil) }
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
            Button("复制配置", systemImage: "doc.on.doc", action: duplicateSelectedProfile)
            if selectedPreset.supportsVisionDirectly, state.activeProfileID != draft.id {
                Button("设为 AI 识图默认", systemImage: "checkmark.circle", action: setAsActive)
            }
            Divider()
            Button("删除配置", systemImage: "trash", role: .destructive) {
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
                    showStatus("已更新 AI 识图默认模型。", style: .success)
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
                    showStatus("已更新截图翻译模型。", style: .success)
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
        let profile = AIProviderProfile(name: "新模型 \(state.profiles.count + 1)")
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
        copy.name = "\(draft.trimmedName) 副本"
        copy.visionVerifiedAt = nil
        do {
            let key = try? profileStore.apiKey(for: draft.id)
            _ = try profileStore.saveProfile(copy, apiKey: key)
            reload(selecting: copy.id)
            showStatus("已复制配置。", style: .success)
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
            showStatus("已设为 AI 识图默认配置。", style: .success)
        } catch {
            showStatus(error.localizedDescription, style: .error)
        }
    }

    private func apply(_ preset: ModelProviderPreset) {
        let previousPreset = selectedPreset
        let wasGenericName = draft.trimmedName.isEmpty
            || draft.trimmedName.hasPrefix("新模型")
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
            showStatus("配置已保存。", style: .success)
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
                ? "已保存，正在测试文字模型和视觉模型…"
                : "已保存，正在测试 Coding Plan 文字模型…",
            style: .neutral
        )
        Task {
            do {
                let textResponse = try await translationService.testTextModel(profile: draft)
                draft.visionVerifiedAt = Date()
                let successMessage: String
                if selectedPreset.supportsVisionDirectly {
                    let visionResponse = try await recognitionService.testConnection(profile: draft)
                    successMessage = "两种模型连接成功。文字：\(textResponse.prefix(24)) · 视觉：\(visionResponse.prefix(24))"
                } else {
                    successMessage = "Coding Plan 文字模型连接成功：\(textResponse.prefix(36))"
                }
                _ = try profileStore.saveProfile(draft)
                reload(selecting: draft.id)
                showStatus(successMessage, style: .success)
                currentStep = .complete
            } catch {
                showStatus("配置已保存，但连接测试失败：\(error.localizedDescription)", style: .error)
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
            throw ModelConfigurationError.invalid("请粘贴 API Key。")
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
            showStatus("API Key 已移除，这套配置暂时不可用。", style: .neutral)
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
        case .zhipuAPI: "智谱 API"
        case .zhipuCodingPlan: "智谱 Coding Plan"
        case .azure: "Azure"
        case .custom: "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .deepSeek: "自动填写常用模型"
        case .openAI: "OpenAI 官方接口"
        case .openRouter: "统一接入多家模型"
        case .anthropic: "Anthropic Messages"
        case .gemini: "Google AI 接口"
        case .zhipuAPI: "通用开放平台 API"
        case .zhipuCodingPlan: "编码套餐专属接口"
        case .azure: "填写专属资源地址"
        case .custom: "本地或兼容服务"
        }
    }

    var guidedSubtitle: String {
        switch self {
        case .deepSeek: "中文理解自然，适合识图和翻译"
        case .openAI: "综合能力强，适合复杂截图"
        case .gemini: "Google 视觉与文字模型"
        case .anthropic: "Anthropic 视觉与文字模型"
        case .openRouter: "一个接口使用多家模型"
        case .zhipuAPI: "通用额度，支持识图和翻译"
        case .zhipuCodingPlan: "订阅套餐，仅支持文字模型直连"
        case .azure: "企业 Azure OpenAI 服务"
        case .custom: "本地模型或兼容接口"
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
        self == .custom ? "自定义模型" : "\(title) 日常"
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
        case .provider: "选择服务商"
        case .credentials: "填写 API Key"
        case .complete: "测试并保存"
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
        if !hasEndpoint { return "先选择服务商" }
        if !hasAPIKey { return "接下来填写 API Key" }
        if !hasVisionModel { return "填写视觉模型" }
        if !hasTextModel { return "最后填写文字模型" }
        return "可以保存并测试连接"
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
