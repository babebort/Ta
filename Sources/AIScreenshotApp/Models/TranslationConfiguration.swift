import Foundation
import AIScreenshotCore

struct TranslationConfiguration: Equatable, Sendable {
    static let defaultBaseURL = "https://api.deepseek.com/chat/completions"
    static let defaultTextModel = "deepseek-v4-flash"
    static let defaultVisionModel = "deepseek-v4-flash-vision-exp"
    static let defaultSourceLanguage = "Auto-detect"
    static let defaultTargetLanguage = "Simplified Chinese"

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
        if targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please enter a target language."
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
