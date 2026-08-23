import AppKit
import ImageIO
import UniformTypeIdentifiers
import AIScreenshotCore

enum ScreenshotTranslationServiceError: LocalizedError {
    case imageEncodingFailed
    case missingTextBoxes

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: "无法为翻译模型编码截图。"
        case .missingTextBoxes: "没有找到可靠的文字位置，无法生成翻译图片；可以改用“翻译文字并复制”。"
        }
    }
}

struct ScreenshotTranslationService: @unchecked Sendable {
    static let keychainAccount = "deepseek-translation-default"

    private let client: TranslationProviderClient
    private let secretStore = KeychainSecretStore()

    init(client: TranslationProviderClient = TranslationProviderClient()) {
        self.client = client
    }

    var isConfigured: Bool {
        let configuration = TranslationConfiguration.load()
        return configuration.validationMessage == nil
            && secretStore.contains(account: Self.keychainAccount)
    }

    func translateText(_ text: String) async throws -> String {
        let configuration = TranslationConfiguration.load()
        let key = try requiredKey()
        return try await client.translateText(
            baseURL: configuration.baseURL,
            model: configuration.textModel,
            apiKey: key,
            text: text,
            sourceLanguage: configuration.sourceLanguage,
            targetLanguage: configuration.targetLanguage
        )
    }

    func translateLines(_ lines: [OCRTextLine]) async throws -> [TranslatedOCRLine] {
        let usableLines = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usableLines.isEmpty else { throw ScreenshotTranslationServiceError.missingTextBoxes }
        let configuration = TranslationConfiguration.load()
        let key = try requiredKey()
        let segments = usableLines.enumerated().map {
            TranslationSourceSegment(id: $0.offset, text: $0.element.text)
        }
        let translated = try await client.translateSegments(
            baseURL: configuration.baseURL,
            model: configuration.textModel,
            apiKey: key,
            segments: segments,
            sourceLanguage: configuration.sourceLanguage,
            targetLanguage: configuration.targetLanguage
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
        let key = try requiredKey()
        let imageData = try encodePNG(prepareOCRImage(image, maximumDimension: 2560))
        return try await client.translateImage(
            baseURL: configuration.baseURL,
            model: configuration.visionModel,
            apiKey: key,
            imageData: imageData,
            sourceLanguage: configuration.sourceLanguage,
            targetLanguage: configuration.targetLanguage
        )
    }

    func testTextModel(apiKey: String? = nil) async throws -> String {
        let configuration = TranslationConfiguration.load()
        let key = try apiKey ?? requiredKey()
        return try await client.testConnection(
            baseURL: configuration.baseURL,
            model: configuration.textModel,
            apiKey: key
        )
    }

    func testVisionModel(apiKey: String? = nil) async throws -> String {
        let image = try makeVisionTestImage()
        let configuration = TranslationConfiguration.load()
        let key = try apiKey ?? requiredKey()
        let data = try encodePNG(image)
        return try await client.translateImage(
            baseURL: configuration.baseURL,
            model: configuration.visionModel,
            apiKey: key,
            imageData: data,
            sourceLanguage: "英文",
            targetLanguage: "简体中文"
        )
    }

    private func requiredKey() throws -> String {
        guard let key = try secretStore.read(account: Self.keychainAccount), !key.isEmpty else {
            throw TranslationProviderError.missingAPIKey
        }
        return key
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
