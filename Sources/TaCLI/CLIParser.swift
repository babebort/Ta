import Foundation
import TaAgentClient
import TaAgentContracts

enum CLIOutputFormat: Equatable, Sendable {
    case human
    case json
}

enum CLIAction: Equatable, Sendable {
    case request(AgentMethod, [String: JSONValue])
    case ocrThenTranslate([String: JSONValue])
}

struct CLIInvocation: Equatable, Sendable {
    let action: CLIAction
    let outputFormat: CLIOutputFormat
    let timeout: TimeInterval
    let requestID: String
    let socketURL: URL
    let outputPath: String?
}

struct CLIParseError: Error, Equatable, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

enum CLIParser {
    static let usage = """
    用法：ta <命令> [参数]

      ta status|capabilities|permissions [--json]
      ta screen list [--json]
      ta window list [--app <名称或 Bundle ID>] [--json]
      ta capture screen [--display <ID>] [--output <PNG>] [--json]
      ta capture frontmost [--output <PNG>] [--json]
      ta capture window --window-id <ID> [--output <PNG>] [--json]
      ta capture region --display <ID> --x <N> --y <N> --width <N> --height <N>
      ta ocr [last|图片路径] [--languages zh-Hans,en-US] [--json]
      ta analyze [last|图片路径] [--task general|extractText|explainCode|tableMarkdown|formulaLaTeX]
      ta translate [last|图片路径] --mode text|image [--cloud auto|allow|deny]
      ta translate text --text <内容> [--cloud auto|allow|deny]
      ta copy [last|图片路径] | --text <内容>
      ta save [last|图片路径] --output <PNG>

    通用参数：--json --timeout <秒> --request-id <ID> --socket <路径> --cloud auto|allow|deny
    """

    static func parse(_ rawArguments: [String]) throws -> CLIInvocation {
        var arguments = rawArguments
        guard !arguments.isEmpty else { throw CLIParseError(message: usage) }

        let outputFormat: CLIOutputFormat = removeFlag("--json", from: &arguments) ? .json : .human
        let timeout = try removeDoubleOption("--timeout", from: &arguments) ?? 10
        guard timeout > 0 else { throw CLIParseError(message: "--timeout 必须大于 0。") }
        let requestID = try removeOption("--request-id", from: &arguments)
            ?? "ta_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let socketPath = try removeOption("--socket", from: &arguments)
        let socketURL = socketPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
            ?? TaBridgeEndpoint.defaultSocketURL
        let outputPath = try removeOption("--output", from: &arguments).map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        }
        let cloud = try removeOption("--cloud", from: &arguments)
        if let cloud, AgentCloudPolicy(rawValue: cloud) == nil {
            throw CLIParseError(message: "--cloud 只支持 auto、allow 或 deny。")
        }

        var action = try parseAction(&arguments, cloud: cloud)
        guard arguments.isEmpty else {
            throw CLIParseError(message: "无法识别的参数：\(arguments.joined(separator: " "))")
        }
        if case .request(.deliverSave, var params) = action {
            guard let outputPath else {
                throw CLIParseError(message: "save 需要 --output <PNG>。")
            }
            params["path"] = .string(outputPath)
            action = .request(.deliverSave, params)
        }
        return CLIInvocation(
            action: action,
            outputFormat: outputFormat,
            timeout: timeout,
            requestID: requestID,
            socketURL: socketURL,
            outputPath: outputPath
        )
    }

    private static func parseAction(
        _ arguments: inout [String],
        cloud: String?
    ) throws -> CLIAction {
        let command = arguments.removeFirst()
        var params: [String: JSONValue] = [:]
        if let cloud { params["cloud"] = .string(cloud) }

        switch command {
        case "status": return .request(.systemStatus, params)
        case "capabilities": return .request(.systemCapabilities, params)
        case "permissions": return .request(.systemPermissions, params)
        case "screen":
            try requireSubcommand("list", arguments: &arguments, parent: command)
            return .request(.targetListDisplays, params)
        case "window":
            try requireSubcommand("list", arguments: &arguments, parent: command)
            if let app = try removeOption("--app", from: &arguments) { params["app"] = .string(app) }
            return .request(.targetListWindows, params)
        case "capture":
            return try parseCapture(&arguments, params: params)
        case "ocr":
            try addImageInput(from: &arguments, to: &params)
            if let raw = try removeOption("--languages", from: &arguments) {
                params["languages"] = .array(raw.split(separator: ",").map {
                    .string($0.trimmingCharacters(in: .whitespacesAndNewlines))
                })
            }
            if removeFlag("--merge-wrapped-lines", from: &arguments) {
                params["mergeWrappedLines"] = .bool(true)
            }
            return .request(.recognizeOCR, params)
        case "analyze":
            try addImageInput(from: &arguments, to: &params)
            if let task = try removeOption("--task", from: &arguments) { params["task"] = .string(task) }
            return .request(.analyzeImage, params)
        case "translate":
            return try parseTranslate(&arguments, params: params)
        case "copy":
            if let text = try removeOption("--text", from: &arguments) {
                params["text"] = .string(text)
            } else {
                try addImageInput(from: &arguments, to: &params)
            }
            return .request(.deliverCopy, params)
        case "save":
            try addImageInput(from: &arguments, to: &params)
            return .request(.deliverSave, params)
        case "help", "--help", "-h":
            throw CLIParseError(message: usage)
        default:
            throw CLIParseError(message: "未知命令：\(command)\n\n\(usage)")
        }
    }

    private static func parseCapture(
        _ arguments: inout [String],
        params initialParams: [String: JSONValue]
    ) throws -> CLIAction {
        guard !arguments.isEmpty else { throw CLIParseError(message: "capture 需要目标类型。") }
        let target = arguments.removeFirst()
        var params = initialParams
        switch target {
        case "screen", "display":
            if let id = try removeUInt32Option("--display", from: &arguments) {
                params["displayId"] = .integer(Int64(id))
            }
            return .request(.captureDisplay, params)
        case "frontmost":
            return .request(.captureFrontmost, params)
        case "window":
            guard let id = try removeUInt32Option("--window-id", from: &arguments) else {
                throw CLIParseError(message: "capture window 需要 --window-id <ID>。")
            }
            params["windowId"] = .integer(Int64(id))
            return .request(.captureWindow, params)
        case "region":
            guard let display = try removeUInt32Option("--display", from: &arguments),
                  let x = try removeDoubleOption("--x", from: &arguments),
                  let y = try removeDoubleOption("--y", from: &arguments),
                  let width = try removeDoubleOption("--width", from: &arguments),
                  let height = try removeDoubleOption("--height", from: &arguments),
                  width > 0, height > 0 else {
                throw CLIParseError(
                    message: "capture region 需要有效的 --display、--x、--y、--width 和 --height。"
                )
            }
            params.merge([
                "displayId": .integer(Int64(display)),
                "x": .number(x), "y": .number(y),
                "width": .number(width), "height": .number(height)
            ]) { _, new in new }
            return .request(.captureRegion, params)
        default:
            throw CLIParseError(message: "未知截图目标：\(target)")
        }
    }

    private static func parseTranslate(
        _ arguments: inout [String],
        params initialParams: [String: JSONValue]
    ) throws -> CLIAction {
        var params = initialParams
        if arguments.first == "text", arguments.contains("--text") {
            arguments.removeFirst()
            guard let text = try removeOption("--text", from: &arguments), !text.isEmpty else {
                throw CLIParseError(message: "translate text 需要 --text <内容>。")
            }
            params["text"] = .string(text)
            return .request(.translateText, params)
        }

        try addImageInput(from: &arguments, to: &params)
        let mode = try removeOption("--mode", from: &arguments) ?? "text"
        switch mode {
        case "text": return .ocrThenTranslate(params)
        case "image": return .request(.translateImage, params)
        default: throw CLIParseError(message: "--mode 只支持 text 或 image。")
        }
    }

    private static func addImageInput(
        from arguments: inout [String],
        to params: inout [String: JSONValue]
    ) throws {
        guard let first = arguments.first, !first.hasPrefix("--") else { return }
        arguments.removeFirst()
        guard first != "last" else { return }
        params["inputPath"] = .string(URL(fileURLWithPath: first).standardizedFileURL.path)
    }

    private static func requireSubcommand(
        _ expected: String,
        arguments: inout [String],
        parent: String
    ) throws {
        guard arguments.first == expected else {
            throw CLIParseError(message: "\(parent) 目前只支持子命令 \(expected)。")
        }
        arguments.removeFirst()
    }

    private static func removeFlag(_ flag: String, from arguments: inout [String]) -> Bool {
        guard let index = arguments.firstIndex(of: flag) else { return false }
        arguments.remove(at: index)
        return true
    }

    private static func removeOption(_ name: String, from arguments: inout [String]) throws -> String? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
            throw CLIParseError(message: "\(name) 缺少参数值。")
        }
        let value = arguments[index + 1]
        arguments.removeSubrange(index...index + 1)
        return value
    }

    private static func removeDoubleOption(
        _ name: String,
        from arguments: inout [String]
    ) throws -> Double? {
        guard let raw = try removeOption(name, from: &arguments) else { return nil }
        guard let value = Double(raw), value.isFinite else {
            throw CLIParseError(message: "\(name) 需要有效数字。")
        }
        return value
    }

    private static func removeUInt32Option(
        _ name: String,
        from arguments: inout [String]
    ) throws -> UInt32? {
        guard let raw = try removeOption(name, from: &arguments) else { return nil }
        guard let value = UInt32(raw) else {
            throw CLIParseError(message: "\(name) 需要 0 到 \(UInt32.max) 的整数。")
        }
        return value
    }
}
