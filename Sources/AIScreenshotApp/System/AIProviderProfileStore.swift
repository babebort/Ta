import Foundation
import AIScreenshotCore

enum AIProviderProfileStoreError: LocalizedError {
    case invalidStoredData
    case profileNotFound
    case missingAPIKey
    case translationIneligible(String)

    var errorDescription: String? {
        switch self {
        case .invalidStoredData: "The saved AI model configuration could not be read."
        case .profileNotFound: "The selected AI model configuration could not be found."
        case .missingAPIKey: "No API Key has been saved for this model yet."
        case .translationIneligible(let reason): reason
        }
    }
}

struct AIProviderProfileStore {
    static let stateDefaultsKey = "aiProviderProfileStateV1"

    let defaults: UserDefaults
    let secretStore: KeychainSecretStore

    init(defaults: UserDefaults = .standard, secretStore: KeychainSecretStore = KeychainSecretStore()) {
        self.defaults = defaults
        self.secretStore = secretStore
    }

    func loadState() throws -> AIProviderProfileState {
        if let data = defaults.data(forKey: Self.stateDefaultsKey) {
            guard var state = try? JSONDecoder().decode(AIProviderProfileState.self, from: data) else {
                throw AIProviderProfileStoreError.invalidStoredData
            }
            let normalized = normalize(state)
            if normalized != state {
                state = normalized
                try saveState(state)
            }
            return state
        }
        let migrated = try migrateLegacyConfiguration()
        try saveState(migrated)
        return migrated
    }

    func saveState(_ state: AIProviderProfileState) throws {
        let normalized = normalize(state)
        defaults.set(try JSONEncoder().encode(normalized), forKey: Self.stateDefaultsKey)
    }

    @discardableResult
    func saveProfile(_ profile: AIProviderProfile, apiKey: String? = nil) throws -> AIProviderProfileState {
        var state = try loadState()
        if let index = state.profiles.firstIndex(where: { $0.id == profile.id }) {
            state.profiles[index] = profile
        } else {
            state.profiles.append(profile)
        }
        if state.activeProfileID == nil, profile.validationMessage() == nil {
            state.activeProfileID = profile.id
        }
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedKey.isEmpty {
            try secretStore.save(trimmedKey, account: keychainAccount(for: profile.id))
        }
        if state.translationProfileID == nil, translationEligibility(of: profile) == nil {
            state.translationProfileID = profile.id
        }
        try saveState(state)
        return state
    }

    @discardableResult
    func deleteProfile(id: UUID) throws -> AIProviderProfileState {
        var state = try loadState()
        state.profiles.removeAll { $0.id == id }
        try secretStore.delete(account: keychainAccount(for: id))
        state = normalize(state)
        try saveState(state)
        return state
    }

    @discardableResult
    func setActiveProfile(id: UUID?) throws -> AIProviderProfileState {
        var state = try loadState()
        state.activeProfileID = state.profiles.contains { $0.id == id } ? id : nil
        try saveState(state)
        return state
    }

    @discardableResult
    func setTranslationProfile(id: UUID?) throws -> AIProviderProfileState {
        var state = try loadState()
        if let id {
            guard let profile = state.profiles.first(where: { $0.id == id }) else {
                throw AIProviderProfileStoreError.profileNotFound
            }
            guard translationEligibility(of: profile) == nil else {
                throw AIProviderProfileStoreError.translationIneligible(
                    translationEligibility(of: profile) ?? "This configuration cannot be used for screenshot translation."
                )
            }
        }
        state.translationProfileID = id
        try saveState(state)
        return state
    }

    func apiKey(for profileID: UUID) throws -> String {
        guard let key = try secretStore.read(account: keychainAccount(for: profileID)), !key.isEmpty else {
            throw AIProviderProfileStoreError.missingAPIKey
        }
        return key
    }

    func hasAPIKey(for profileID: UUID) -> Bool {
        secretStore.contains(account: keychainAccount(for: profileID))
    }

    func removeAPIKey(for profileID: UUID) throws {
        try secretStore.delete(account: keychainAccount(for: profileID))
    }

    func keychainAccount(for profileID: UUID) -> String {
        "\(PersistentConfigurationIdentity.providerProfileAccountPrefix)\(profileID.uuidString.lowercased())"
    }

    func translationEligibility(of profile: AIProviderProfile) -> String? {
        if let message = profile.validationMessage(requiresTextModel: true) { return message }
        if !hasAPIKey(for: profile.id) { return "Please save an API Key for this configuration first." }
        return nil
    }

    func eligibleTranslationProfiles(in state: AIProviderProfileState) -> [AIProviderProfile] {
        state.profiles.filter { translationEligibility(of: $0) == nil }
    }

    private func normalize(_ state: AIProviderProfileState) -> AIProviderProfileState {
        var result = state
        result.schemaVersion = AIProviderProfileState.currentSchemaVersion
        if !result.profiles.contains(where: { $0.id == result.activeProfileID }) {
            result.activeProfileID = result.profiles.first { $0.validationMessage() == nil }?.id
        }
        if let translationID = result.translationProfileID,
           !result.profiles.contains(where: { $0.id == translationID }) {
            result.translationProfileID = nil
        }
        return result
    }

    private func migrateLegacyConfiguration() throws -> AIProviderProfileState {
        var state = AIProviderProfileState()

        let legacyBaseURL = defaults.string(forKey: "providerBaseURL") ?? ""
        let legacyVisionModel = defaults.string(forKey: "providerVisionModel") ?? ""
        let legacyTextModel = defaults.string(forKey: "providerTextModel") ?? ""
        let legacyProvider = VisionProviderKind(
            rawValue: defaults.string(forKey: "providerKind") ?? VisionProviderKind.openAICompatible.rawValue
        ) ?? .openAICompatible
        let legacyAIKey = try secretStore.read(account: PersistentConfigurationIdentity.multimodalProviderAccount)

        if !legacyBaseURL.isEmpty || !legacyVisionModel.isEmpty || legacyAIKey != nil {
            let profile = AIProviderProfile(
                name: "Legacy AI Model",
                providerKind: legacyProvider,
                baseURL: legacyBaseURL,
                visionModel: legacyVisionModel,
                textModel: legacyTextModel
            )
            state.profiles.append(profile)
            state.activeProfileID = profile.id
            if let legacyAIKey, !legacyAIKey.isEmpty {
                try secretStore.save(legacyAIKey, account: keychainAccount(for: profile.id))
            }
        }

        let legacyTranslationKey = try secretStore.read(
            account: PersistentConfigurationIdentity.translationProviderAccount
        )
        if legacyTranslationKey != nil {
            let translation = TranslationConfiguration.load(defaults: defaults)
            if let existing = state.profiles.first(where: {
                $0.providerKind == .openAICompatible
                    && normalizedURL($0.baseURL) == normalizedURL(translation.baseURL)
                    && $0.visionModel == translation.visionModel
                    && $0.textModel == translation.textModel
            }) {
                state.translationProfileID = existing.id
                if let legacyTranslationKey, !legacyTranslationKey.isEmpty {
                    try secretStore.save(legacyTranslationKey, account: keychainAccount(for: existing.id))
                }
            } else {
                let profile = AIProviderProfile(
                    name: "Legacy Translation Model",
                    providerKind: .openAICompatible,
                    baseURL: translation.baseURL,
                    visionModel: translation.visionModel,
                    textModel: translation.textModel
                )
                state.profiles.append(profile)
                state.translationProfileID = profile.id
                if state.activeProfileID == nil { state.activeProfileID = profile.id }
                if let legacyTranslationKey, !legacyTranslationKey.isEmpty {
                    try secretStore.save(legacyTranslationKey, account: keychainAccount(for: profile.id))
                }
            }
        }

        return normalize(state)
    }

    private func normalizedURL(_ value: String) -> String {
        value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/，,"))
            .replacingOccurrences(of: "/chat/completions", with: "")
    }
}
