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
        if trimmedName.isEmpty { return "请给这套配置起一个名称。" }
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先选择服务商，或填写服务地址。"
        }
        if let endpointError = ProviderEndpointValidator().validationMessage(for: baseURL) {
            return endpointError
        }
        if requiresVisionModel && !hasVisionModel { return "请填写一个支持图片输入的视觉模型。" }
        if requiresTextModel && !hasTextModel { return "请填写文字模型，截图翻译需要同时使用文字与视觉模型。" }
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
