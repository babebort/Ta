import Foundation
import AIScreenshotCore

struct AIProviderProfile: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var providerKind: VisionProviderKind
    var baseURL: String
    var visionModel: String
    var textModel: String
    var visionVerifiedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        providerKind: VisionProviderKind = .openAICompatible,
        baseURL: String = "",
        visionModel: String = "",
        textModel: String = "",
        visionVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.providerKind = providerKind
        self.baseURL = baseURL
        self.visionModel = visionModel
        self.textModel = textModel
        self.visionVerifiedAt = visionVerifiedAt
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasVisionModel: Bool {
        !visionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasTextModel: Bool {
        !textModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func validationMessage(
        requiresVisionModel: Bool = true,
        requiresTextModel: Bool = false
    ) -> String? {
        if trimmedName.isEmpty { return "Please give this configuration a name." }
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please select a provider, or enter a service URL."
        }
        if let endpointError = ProviderEndpointValidator().validationMessage(for: baseURL) {
            return endpointError
        }
        if requiresVisionModel && !hasVisionModel { return "Please enter a vision model that supports image input." }
        if requiresTextModel && !hasTextModel { return "Please enter a text model — screenshot translation needs both a text model and a vision model." }
        return nil
    }
}

struct AIProviderProfileState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var profiles: [AIProviderProfile] = []
    var activeProfileID: UUID?
    var translationProfileID: UUID?

    var activeProfile: AIProviderProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    var translationProfile: AIProviderProfile? {
        profiles.first { $0.id == translationProfileID }
    }
}
