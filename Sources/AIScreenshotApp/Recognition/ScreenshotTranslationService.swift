import AppKit
import ImageIO
import UniformTypeIdentifiers
import AIScreenshotCore

enum ScreenshotTranslationServiceError: LocalizedError {
    case imageEncodingFailed
    case missingTextBoxes
    case localOCRUnavailableForImage

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: "无法为翻译模型编码截图。"
        case .missingTextBoxes: "没有找到可靠的文字位置，无法生成翻译图片；可以改用“翻译文字并复制”。"
        case .localOCRUnavailableForImage:
            "本地文字识别暂时无法定位图片中的文字，因此不能生成全文翻译图片。请重试，或在翻译设置中改用“翻译文字并复制”。"
        }
    }
}

struct ScreenshotTranslationService: @unchecked Sendable {
    // Kept as a migration compatibility alias for existing installations.
    static let keychainAccount = PersistentConfigurationIdentity.translationProviderAccount

    private let client: TranslationProviderClient
    private let profileStore: AIProviderProfileStore

    init(
        client: TranslationProviderClient = TranslationProviderClient(),
        profileStore: AIProviderProfileStore = AIProviderProfileStore()
    ) {
        self.client = client
        self.profileStore = profileStore
    }

    var isConfigured: Bool {
        (try? requiredProfile()) != nil
    }

    var selectedTextModelName: String {
        (try? requiredProfile().textModel) ?? "文字模型"
    }

    func validateConfiguration() throws {
        _ = try requiredProfile()
    }

    func translateText(_ text: String) async throws -> String {
        let configuration = TranslationConfiguration.load()
        let profile = try requiredProfile()
        let key = try profileStore.apiKey(for: profile.id)
        return try await client.translateText(
            baseURL: profile.baseURL,
            model: profile.textModel,
            apiKey: key,
            text: text,
            sourceLanguage: configuration.sourceLanguage,
            targetLanguage: configuration.targetLanguage,
            provider: profile.providerKind
        )
    }

    func translateLines(_ lines: [OCRTextLine]) async throws -> [TranslatedOCRLine] {
        let usableLines = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usableLines.isEmpty else { throw ScreenshotTranslationServiceError.missingTextBoxes }
        let configuration = TranslationConfiguration.load()
        let profile = try requiredProfile()
        let key = try profileStore.apiKey(for: profile.id)
        let segments = usableLines.enumerated().map {
            TranslationSourceSegment(id: $0.offset, text: $0.element.text)
        }
        let translated = try await client.translateSegments(
            baseURL: profile.baseURL,
            model: profile.textModel,
            apiKey: key,
            segments: segments,
            sourceLanguage: configuration.sourceLanguage,
            targetLanguage: configuration.targetLanguage,
            provider: profile.providerKind
        )
        let byID = Dictionary(uniqueKeysWithValues: translated.map { ($0.id, $0.text) })
        return usableLines.enumerated().compactMap { index, line in
            guard let translatedText = byID[index], !translatedText.isEmpty else { return nil }
            return TranslatedOCRLine(
                sourceText: line.text,
                translatedText: translatedText,
                boundingBox: line.boundingBox,
                confidence: line.confidence
            )
        }
    }

    func translateWithVision(image: CGImage) async throws -> String {
        let configuration = TranslationConfiguration.load()
        let profile = try requiredProfile()
        let key = try profileStore.apiKey(for: profile.id)
        let imageData = try encodePNG(prepareOCRImage(image, maximumDimension: 2560))
        return try await client.translateImage(
            baseURL: profile.baseURL,
            model: profile.visionModel,
            apiKey: key,
            imageData: imageData,
            sourceLanguage: configuration.sourceLanguage,
            targetLanguage: configuration.targetLanguage,
            provider: profile.providerKind
        )
    }

    func testTextModel(profile: AIProviderProfile, apiKey: String? = nil) async throws -> String {
        let key = try apiKey ?? profileStore.apiKey(for: profile.id)
        return try await client.testConnection(
            baseURL: profile.baseURL,
            model: profile.textModel,
            apiKey: key,
            provider: profile.providerKind
        )
    }

    func testVisionModel(profile: AIProviderProfile, apiKey: String? = nil) async throws -> String {
        let image = try makeVisionTestImage()
        let key = try apiKey ?? profileStore.apiKey(for: profile.id)
        let data = try encodePNG(image)
        return try await client.translateImage(
            baseURL: profile.baseURL,
            model: profile.visionModel,
            apiKey: key,
            imageData: data,
            sourceLanguage: "英文",
            targetLanguage: "简体中文",
            provider: profile.providerKind
        )
    }

    private func requiredProfile() throws -> AIProviderProfile {
        let state = try profileStore.loadState()
        if let selected = state.translationProfile,
           profileStore.translationEligibility(of: selected) == nil {
            return selected
        }
        let eligible = profileStore.eligibleTranslationProfiles(in: state)
        if eligible.count == 1, let only = eligible.first {
            _ = try profileStore.setTranslationProfile(id: only.id)
            return only
        }
        if state.translationProfile != nil {
            throw AIProviderProfileStoreError.translationIneligible(
                "当前翻译模型缺少文字模型、视觉模型或 API Key，请到“AI 模型”中补全。"
            )
        }
        throw AIProviderProfileStoreError.translationIneligible(
            "请先到“AI 模型”配置一套带文字模型和视觉模型的服务，然后在翻译设置中选择它。"
        )
    }

    private func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw ScreenshotTranslationServiceError.imageEncodingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotTranslationServiceError.imageEncodingFailed
        }
        return data as Data
    }

    private func makeVisionTestImage() throws -> CGImage {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 520,
            pixelsHigh: 180,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw ScreenshotTranslationServiceError.imageEncodingFailed }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 520, height: 180).fill()
        "Screenshot translation ready".draw(
            at: CGPoint(x: 32, y: 72),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
        )
        NSGraphicsContext.restoreGraphicsState()
        guard let image = representation.cgImage else {
            throw ScreenshotTranslationServiceError.imageEncodingFailed
        }
        return image
    }
}
