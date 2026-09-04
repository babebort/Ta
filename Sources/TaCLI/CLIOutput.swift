import Foundation
import TaAgentContracts

enum CLIExitCode: Int32, Equatable, Sendable {
    case success = 0
    case usage = 2
    case appNotInstalled = 3
    case bridgeUnavailable = 4
    case permissionDenied = 5
    case privacyBlocked = 6
    case requestFailed = 7
    case cancelled = 130

    static func forResponse(_ response: AgentResponseEnvelope) -> CLIExitCode {
        guard !response.ok else { return .success }
        switch response.error?.code {
        case .taAppNotInstalled: return .appNotInstalled
        case .bridgeUnavailable: return .bridgeUnavailable
        case .screenPermissionRequired, .accessibilityPermissionRequired: return .permissionDenied
        case .targetBlockedByPrivacyPolicy, .cloudUploadNotAllowed: return .privacyBlocked
        case .cancelled: return .cancelled
        default: return .requestFailed
        }
    }
}

enum CLIOutput {
    static func render(
        _ response: AgentResponseEnvelope,
        format: CLIOutputFormat
    ) throws -> String {
        switch format {
        case .json:
            return String(decoding: try AgentJSONCoding.encoder().encode(response), as: UTF8.self)
        case .human:
            return human(response)
        }
    }

    private static func human(_ response: AgentResponseEnvelope) -> String {
        if let error = response.error {
            var lines = ["\(error.code.rawValue): \(error.message)"]
            if let hint = error.hint, !hint.isEmpty { lines.append("Hint: \(hint)") }
            return lines.joined(separator: "\n")
        }
        if case .object(let object) = response.data,
           case .string(let text) = object["text"] {
            return text
        }
        var lines: [String] = []
        if case .object(let object) = response.data {
            for key in object.keys.sorted() {
                lines.append("\(key): \(display(object[key] ?? .null))")
            }
        }
        lines.append(contentsOf: response.artifacts.map { "Image: \($0.path) (\($0.width ?? 0)×\($0.height ?? 0))" })
        return lines.isEmpty ? "Done" : lines.joined(separator: "\n")
    }

    private static func display(_ value: JSONValue) -> String {
        switch value {
        case .null: "-"
        case .bool(let value): value ? "Yes" : "No"
        case .integer(let value): String(value)
        case .number(let value): String(value)
        case .string(let value): value
        case .array(let values): values.map(display).joined(separator: ", ")
        case .object:
            (try? String(decoding: AgentJSONCoding.encoder().encode(value), as: UTF8.self)) ?? "{}"
        }
    }
}
