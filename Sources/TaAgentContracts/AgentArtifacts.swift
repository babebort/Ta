import Foundation

public struct AgentArtifact: Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let mimeType: String
    public let width: Int?
    public let height: Int?
    public let bytes: Int
    public let sha256: String
    public let expiresAt: Date

    public init(
        id: String,
        path: String,
        mimeType: String,
        width: Int? = nil,
        height: Int? = nil,
        bytes: Int,
        sha256: String,
        expiresAt: Date
    ) {
        self.id = id
        self.path = path
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.bytes = bytes
        self.sha256 = sha256
        self.expiresAt = expiresAt
    }
}

