import Foundation
import AIScreenshotCore

struct TranslationConfiguration: Equatable, Sendable {
    static let defaultBaseURL = "https://api.deepseek.com/chat/completions"
    static let defaultTextModel = "deepseek-v4-flash"
    static let defaultVisionModel = "deepseek-v4-flash-vision-exp"
    static let defaultSourceLanguage = "自动检测"
    static let defaultTargetLanguage = "简体中文"

    var baseURL: String
    var textModel: String
    var visionModel: String
    var sourceLanguage: String
    var targetLanguage: String
    var defaultMode: ScreenshotTranslationMode
    var usesVisionFallback: Bool

    static func load(defaults: UserDefaults = .standard) -> TranslationConfiguration {
        TranslationConfiguration(
            baseURL: defaults.string(forKey: "translationBaseURL") ?? defaultBaseURL,
            textModel: defaults.string(forKey: "translationTextModel") ?? defaultTextModel,
            visionModel: defaults.string(forKey: "translationVisionModel") ?? defaultVisionModel,
            sourceLanguage: defaults.string(forKey: "translationSourceLanguage") ?? defaultSourceLanguage,
            targetLanguage: defaults.string(forKey: "translationTargetLanguage") ?? defaultTargetLanguage,
            defaultMode: ScreenshotTranslationMode(
                rawValue: defaults.string(forKey: "translationDefaultMode") ?? ScreenshotTranslationMode.textOnly.rawValue
            ) ?? .textOnly,
            usesVisionFallback: defaults.object(forKey: "translationUsesVisionFallback") == nil
                ? true
                : defaults.bool(forKey: "translationUsesVisionFallback")
        )
    }

    var validationMessage: String? {
        if let endpointError = ProviderEndpointValidator().validationMessage(for: baseURL) {
            return endpointError
        }
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写翻译 API 地址。"
        }
        if textModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写文字翻译模型。"
        }
        if targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写目标语言。"
        }
        return nil
    }
}

enum TranslationModeRouting {
    static func mode(
        for action: CaptureQuickAction,
        configuredDefault: ScreenshotTranslationMode
    ) -> ScreenshotTranslationMode? {
        switch action {
        case .translate:
            configuredDefault
        case .translateText:
            .textOnly
        default:
            nil
        }
    }
}
