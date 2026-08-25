import AppKit
import AIScreenshotCore

enum MultimodalRecognitionError: LocalizedError {
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: "无法为视觉模型编码截图。"
        }
    }
}

@MainActor
struct MultimodalRecognitionService {
    private let client = MultimodalProviderClient()
    private let secretStore = KeychainSecretStore()
    private let account = PersistentConfigurationIdentity.multimodalProviderAccount

    var isConfigured: Bool {
        !(UserDefaults.standard.string(forKey: "providerBaseURL") ?? "").isEmpty
            && !(UserDefaults.standard.string(forKey: "providerVisionModel") ?? "").isEmpty
            && secretStore.contains(account: account)
    }

    func recognize(image: CGImage, task: MultimodalTaskTemplate? = nil) async throws -> String {
        let baseURL = UserDefaults.standard.string(forKey: "providerBaseURL") ?? ""
        let model = UserDefaults.standard.string(forKey: "providerVisionModel") ?? ""
        let apiKey = try secretStore.read(account: account) ?? ""
        let providerRaw = UserDefaults.standard.string(forKey: "providerKind")
            ?? VisionProviderKind.openAICompatible.rawValue
        let provider = VisionProviderKind(rawValue: providerRaw) ?? .openAICompatible
        let taskRaw = UserDefaults.standard.string(forKey: "multimodalTaskTemplate")
            ?? MultimodalTaskTemplate.general.rawValue
        let selectedTask = task ?? MultimodalTaskTemplate(rawValue: taskRaw) ?? .general
        let imageData = try encodeJPEG(image, maximumDimension: 2048)
        return try await client.recognize(
            provider: provider,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            imageData: imageData,
            prompt: selectedTask.prompt
        )
    }

    private func encodeJPEG(_ image: CGImage, maximumDimension: Int) throws -> Data {
        let sourceSize = CGSize(width: image.width, height: image.height)
        let scale = min(1, CGFloat(maximumDimension) / max(sourceSize.width, sourceSize.height))
        let width = max(1, Int((sourceSize.width * scale).rounded()))
        let height = max(1, Int((sourceSize.height * scale).rounded()))
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw MultimodalRecognitionError.imageEncodingFailed
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSImage(cgImage: image, size: sourceSize).draw(
            in: CGRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        guard let data = representation.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.88]
        ) else {
            throw MultimodalRecognitionError.imageEncodingFailed
        }
        return data
    }
}
