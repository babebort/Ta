import Foundation

public enum AgentProtocol {
    public static let currentVersion = 1
}

public struct AgentClientInfo: Codable, Equatable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct AgentRequestEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let requestID: String
    public let method: AgentMethod
    public let params: [String: JSONValue]
    public let client: AgentClientInfo

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case requestID = "requestId"
        case method
        case params
        case client
    }

    public init(
        protocolVersion: Int = AgentProtocol.currentVersion,
        requestID: String,
        method: AgentMethod,
        params: [String: JSONValue] = [:],
        client: AgentClientInfo
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.method = method
        self.params = params
        self.client = client
    }

    public func validateProtocolVersion(supported: Int = AgentProtocol.currentVersion) throws {
        guard protocolVersion == supported else {
            throw AgentProtocolError.unsupportedVersion(received: protocolVersion, supported: supported)
        }
    }
}

public struct AgentResponseMetadata: Codable, Equatable, Sendable {
    public let durationMs: Int
    public let cloudUploaded: Bool

    public init(durationMs: Int, cloudUploaded: Bool) {
        self.durationMs = durationMs
        self.cloudUploaded = cloudUploaded
    }
}

public struct AgentResponseEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let requestID: String
    public let ok: Bool
    public let data: JSONValue?
    public let artifacts: [AgentArtifact]
    public let meta: AgentResponseMetadata?
    public let error: AgentErrorPayload?

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case requestID = "requestId"
        case ok
        case data
        case artifacts
        case meta
        case error
    }

    public init(
        protocolVersion: Int = AgentProtocol.currentVersion,
        requestID: String,
        ok: Bool,
        data: JSONValue? = nil,
        artifacts: [AgentArtifact] = [],
        meta: AgentResponseMetadata? = nil,
        error: AgentErrorPayload? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.ok = ok
        self.data = data
        self.artifacts = artifacts
        self.meta = meta
        self.error = error
    }

    public static func success(
        requestID: String,
        data: JSONValue? = nil,
        artifacts: [AgentArtifact] = [],
        meta: AgentResponseMetadata? = nil
    ) -> AgentResponseEnvelope {
        AgentResponseEnvelope(
            requestID: requestID,
            ok: true,
            data: data,
            artifacts: artifacts,
            meta: meta
        )
    }

    public static func failure(
        requestID: String,
        error: AgentErrorPayload
    ) -> AgentResponseEnvelope {
        AgentResponseEnvelope(requestID: requestID, ok: false, error: error)
    }
}

public enum AgentJSONCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

