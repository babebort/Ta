import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AIScreenshotCore

enum DeepSeekOCRRecognitionError: LocalizedError {
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: "Failed to encode the screenshot for DeepSeek-OCR-2."
        }
    }
}

struct DeepSeekOCRRecognitionService: @unchecked Sendable {
    static let keychainAccount = PersistentConfigurationIdentity.deepSeekOCRAccount

    private let client = DeepSeekOCR2Client()
    private let secretStore = KeychainSecretStore()

    func recognize(image: CGImage, languages: [String]) async throws -> OCRResult {
        let defaults = UserDefaults.standard
        let baseURL = defaults.string(forKey: "deepSeekOCRBaseURL") ?? ""
        let model = defaults.string(forKey: "deepSeekOCRModel") ?? DeepSeekOCR2Client.latestOfficialModel
        let modeRaw = defaults.string(forKey: "deepSeekOCRPromptMode") ?? DeepSeekOCRPromptMode.plainText.rawValue
        let mode = DeepSeekOCRPromptMode(rawValue: modeRaw) ?? .plainText
        let apiKey = try secretStore.read(account: Self.keychainAccount) ?? ""
        let imageData = try encodePNG(prepareOCRImage(image, maximumDimension: 2560))
        let text = try await client.recognize(
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            imageData: imageData,
            mode: mode
        )
        return OCRResult(
            text: text,
            contentType: ContentClassifier().classify(text),
            confidence: 0.85,
            languages: languages,
            engine: .deepSeekOCR2
        )
    }

    private func encodePNG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw DeepSeekOCRRecognitionError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DeepSeekOCRRecognitionError.imageEncodingFailed
        }
        return data as Data
    }
}
