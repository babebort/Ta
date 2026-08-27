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

enum GeneralVisionResponsePolicy {
    static let recoveryPrompt = """
        请重新查看图片本身。这是视觉理解任务，不是 OCR。请直接描述图中可见的主体、动物或人物、物体、场景、动作、颜色和构图。即使没有任何文字，也必须描述画面；不要只回答“没有文字”。
        """

    static func shouldRetry(_ response: String) -> Bool {
        let normalized = response
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
        let textOnlyAnswers = [
            "图片中未包含任何文字内容",
            "图片中未包含任何文字",
            "图片中没有任何文字",
            "图片中没有文字",
            "未检测到文字",
            "没有检测到文字",
            "未发现文字",
            "没有可识别的文字",
            "no text in the image",
            "the image contains no text",
            "no readable text"
        ]
        return textOnlyAnswers.contains(normalized)
    }
}

@MainActor
struct MultimodalRecognitionService {
    private let client = MultimodalProviderClient()
    private let profileStore = AIProviderProfileStore()

    var isConfigured: Bool {
        guard let state = try? profileStore.loadState(), let profile = state.activeProfile else { return false }
        return profile.validationMessage() == nil && profileStore.hasAPIKey(for: profile.id)
    }

    var activeVisionModelName: String {
        (try? profileStore.loadState().activeProfile?.visionModel) ?? "视觉模型"
    }

    func recognize(image: CGImage, task: MultimodalTaskTemplate? = nil) async throws -> String {
        let state = try profileStore.loadState()
        guard let profile = state.activeProfile else { throw AIProviderProfileStoreError.profileNotFound }
        if let validation = profile.validationMessage() {
            throw AIProviderProfileStoreError.translationIneligible(validation)
        }
        let apiKey = try profileStore.apiKey(for: profile.id)
        let taskRaw = UserDefaults.standard.string(forKey: "multimodalTaskTemplate")
            ?? MultimodalTaskTemplate.general.rawValue
        let selectedTask = task ?? MultimodalTaskTemplate(rawValue: taskRaw) ?? .general
        let imageData = try encodeJPEG(image, maximumDimension: 2048)
        let response = try await client.recognize(
            provider: profile.providerKind,
            baseURL: profile.baseURL,
            model: profile.visionModel,
            apiKey: apiKey,
            imageData: imageData,
            prompt: selectedTask.prompt
        )
        guard selectedTask == .general,
              GeneralVisionResponsePolicy.shouldRetry(response) else {
            return response
        }
        return try await client.recognize(
            provider: profile.providerKind,
            baseURL: profile.baseURL,
            model: profile.visionModel,
            apiKey: apiKey,
            imageData: imageData,
            prompt: GeneralVisionResponsePolicy.recoveryPrompt
        )
    }

    func testConnection(profile: AIProviderProfile, apiKey: String? = nil) async throws -> String {
        let key = try apiKey ?? profileStore.apiKey(for: profile.id)
        let image = try makeTestImage()
        let imageData = try encodeJPEG(image, maximumDimension: 1024)
        return try await client.recognize(
            provider: profile.providerKind,
            baseURL: profile.baseURL,
            model: profile.visionModel,
            apiKey: key,
            imageData: imageData,
            prompt: "这是拓的连接测试图片。请只回复你在图片中看到的英文单词和数字，不要添加解释。"
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

    private func makeTestImage() throws -> CGImage {
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
        ) else {
            throw MultimodalRecognitionError.imageEncodingFailed
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSColor(calibratedRed: 250 / 255, green: 246 / 255, blue: 238 / 255, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 520, height: 180).fill()
        "TA VISION 2026".draw(
            at: CGPoint(x: 72, y: 68),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 34, weight: .bold),
                .foregroundColor: NSColor(calibratedRed: 214 / 255, green: 64 / 255, blue: 47 / 255, alpha: 1)
            ]
        )
        guard let image = representation.cgImage else {
            throw MultimodalRecognitionError.imageEncodingFailed
        }
        return image
    }
}
