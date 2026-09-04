import Foundation

public enum ScreenshotTranslationMode: String, CaseIterable, Codable, Sendable {
    case textOnly
    case fullImage
    case bilingualImage

    public var displayName: String {
        switch self {
        case .textOnly: "Translate Text and Copy"
        case .fullImage: "Translate Full Image"
        case .bilingualImage: "Bilingual Translated Image"
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
