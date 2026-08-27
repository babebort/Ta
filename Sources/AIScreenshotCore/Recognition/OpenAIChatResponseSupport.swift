@preconcurrency import Foundation

/// Shared helpers for OpenAI-compatible chat completions returned by
/// reasoning models (GLM-4.x, DeepSeek-R1, ...): their token budget can be
/// consumed entirely by `reasoning_content` before the final `content`, which
/// previously surfaced as a misleading "empty response" error.
enum OpenAIChatResponseSupport {
    /// Hosts documented to accept `thinking: {"type": "disabled"}` on the
    /// chat completions API. Only these get the flag injected automatically;
    /// unknown gateways stay untouched to avoid rejecting unknown fields.
    private static let thinkingControlHostSuffixes = [
        "deepseek.com",
        "bigmodel.cn",
        "zhipuai.cn"
    ]

    static func applyThinkingPreference(to body: inout [String: Any], host: String?) {
        guard let host = host?.lowercased(),
              thinkingControlHostSuffixes.contains(where: host.hasSuffix) else { return }
        body["thinking"] = ["type": "disabled"]
    }

    static func firstMessage(in object: [String: Any]) -> [String: Any]? {
        (object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
    }

    static func text(fromContent content: Any?) -> String? {
        if let string = content as? String {
            return trimmed(string)
        }
        if let parts = content as? [[String: Any]] {
            let joined = parts.compactMap { $0["text"] as? String ?? $0["content"] as? String }
                .joined(separator: "\n")
            return trimmed(joined)
        }
        return nil
    }

    static func contentText(in object: [String: Any]) -> String? {
        text(fromContent: firstMessage(in: object)?["content"])
    }

    static func reasoningText(in object: [String: Any]) -> String? {
        let message = firstMessage(in: object)
        if let value = message?["reasoning_content"] as? String { return trimmed(value) }
        if let value = message?["reasoning"] as? String { return trimmed(value) }
        return nil
    }

    static func isLengthTruncated(_ object: [String: Any]) -> Bool {
        ((object["choices"] as? [[String: Any]])?.first?["finish_reason"] as? String)?
            .lowercased() == "length"
    }

    private static func trimmed(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
