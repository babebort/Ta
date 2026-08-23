import Foundation

public enum ScreenshotTranslationMode: String, CaseIterable, Codable, Sendable {
    case textOnly
    case fullImage
    case bilingualImage

    public var displayName: String {
        switch self {
        case .textOnly: "翻译文字并复制"
        case .fullImage: "全文翻译图片"
        case .bilingualImage: "双语翻译图片"
        }
    }
}

public struct TranslationSourceSegment: Codable, Equatable, Sendable {
    public let id: Int
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

public struct TranslationSegmentResult: Codable, Equatable, Sendable {
    public let id: Int
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}
