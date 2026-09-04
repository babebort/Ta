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
        case .imageEncodingFailed: "Failed to encode the screenshot for the translation model."
        case .missingTextBoxes: "No reliable text positions were found, so a translated image can't be generated; try “Translate Text and Copy” instead."
        case .localOCRUnavailableForImage:
            "Local text recognition couldn't locate text in the image right now, so a full-image translation can't be generated. Please try again, or switch to “Translate Text and Copy” in the translation settings."
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
        (try? requiredProfile().textModel) ?? "Text Model"
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
            sourceLanguage: "English",
            targetLanguage: "Simplified Chinese",
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
                "The current translation model is missing a text model, vision model, or API Key — please complete it in “AI Models”."
            )
        }
        throw AIProviderProfileStoreError.translationIneligible(
            "Please first configure a service with both a text model and a vision model in “AI Models”, then select it in translation settings."
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
