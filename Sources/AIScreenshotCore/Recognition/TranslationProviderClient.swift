@preconcurrency import Foundation

public enum TranslationProviderError: LocalizedError, Equatable {
    case invalidEndpoint(String)
    case missingModel
    case missingAPIKey
    case emptyInput
    case invalidResponse
    case emptyResponse
    case invalidSegmentResponse
    case server(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let message): message
        case .missingModel: "尚未配置翻译模型。"
        case .missingAPIKey: "尚未配置翻译 API Key。"
        case .emptyInput: "截图中没有可翻译的文字。"
        case .invalidResponse: "翻译服务返回了无法解析的响应。"
        case .emptyResponse: "翻译模型没有返回内容。"
        case .invalidSegmentResponse: "翻译模型没有返回完整的分段结果，请重试。"
        case .server(let statusCode, let message): "翻译服务错误（\(statusCode)）：\(message)"
        }
    }
}

public struct TranslationProviderClient: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func translateText(
        baseURL: String,
        model: String,
        apiKey: String,
        text: String,
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationProviderError.emptyInput }
        let prompt = """
        Translate the following content from \(sourceLanguage) to \(targetLanguage).
        Preserve paragraphs, lists, code, numbers, names, and Markdown structure.
        Do not summarize, explain, or add labels. Output only the translation.

        <content>
        \(trimmed)
        </content>
        """
        return try await complete(
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            content: [["type": "text", "text": prompt]],
            jsonMode: false
        )
    }

    public func translateSegments(
        baseURL: String,
        model: String,
        apiKey: String,
        segments: [TranslationSourceSegment],
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> [TranslationSegmentResult] {
        guard !segments.isEmpty else { throw TranslationProviderError.emptyInput }
        let sourceData = try JSONEncoder().encode(segments)
        let sourceJSON = String(data: sourceData, encoding: .utf8) ?? "[]"
        let prompt = """
        Translate every JSON item's text from \(sourceLanguage) to \(targetLanguage).
        Return valid JSON only in this exact shape: {"translations":[{"id":0,"text":"..."}]}.
        Preserve every id exactly once and keep short UI labels concise. Do not add explanations.

        Input JSON:
        \(sourceJSON)
        """
        let response = try await complete(
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            content: [["type": "text", "text": prompt]],
            jsonMode: true
        )
        let decoded = try decodeSegments(response)
        let expectedIDs = Set(segments.map(\.id))
        guard Set(decoded.map(\.id)) == expectedIDs, decoded.count == expectedIDs.count else {
            throw TranslationProviderError.invalidSegmentResponse
        }
        return decoded.sorted { $0.id < $1.id }
    }

    public func translateImage(
        baseURL: String,
        model: String,
        apiKey: String,
        imageData: Data,
        mimeType: String = "image/png",
        sourceLanguage: String,
        targetLanguage: String
    ) async throws -> String {
        let prompt = """
        Read all visible text in this screenshot and translate it from \(sourceLanguage) to \(targetLanguage).
        Preserve reading order, paragraphs, lists, code, numbers, and names.
        Do not describe the image or explain. Output only the translated text.
        """
        let dataURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        return try await complete(
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            content: [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": dataURL]]
            ],
            jsonMode: false
        )
    }

    public func testConnection(
        baseURL: String,
        model: String,
        apiKey: String
    ) async throws -> String {
        try await complete(
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            content: [["type": "text", "text": "Reply with exactly: OK"]],
            jsonMode: false,
            maxTokens: 16
        )
    }

    private func complete(
        baseURL: String,
        model: String,
        apiKey: String,
        content: [[String: Any]],
        jsonMode: Bool,
        maxTokens: Int = 4096
    ) async throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw TranslationProviderError.missingModel }
        guard !trimmedKey.isEmpty else { throw TranslationProviderError.missingAPIKey }
        let endpoint = try endpointURL(from: baseURL)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": trimmedModel,
            "messages": [["role": "user", "content": content]],
            "temperature": 0,
            "stream": false,
            "max_tokens": maxTokens
        ]
        if endpoint.host?.lowercased().hasSuffix("deepseek.com") == true {
            body["thinking"] = ["type": "disabled"]
        }
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationProviderError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationProviderError.server(
                statusCode: http.statusCode,
                message: errorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = responseText(from: message["content"]),
              !text.isEmpty else {
            throw TranslationProviderError.emptyResponse
        }
        return text
    }

    private func endpointURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "，,"))
        guard !trimmed.isEmpty else {
            throw TranslationProviderError.invalidEndpoint("请先配置翻译 API 地址。")
        }
        if let validation = ProviderEndpointValidator().validationMessage(for: trimmed) {
            throw TranslationProviderError.invalidEndpoint(validation)
        }
        guard var components = URLComponents(string: trimmed), components.url != nil else {
            throw TranslationProviderError.invalidEndpoint("翻译 API 地址格式无效。")
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("chat/completions") { return components.url! }
        components.path = "/" + [path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url else {
            throw TranslationProviderError.invalidEndpoint("翻译 API 地址格式无效。")
        }
        return url
    }

    private func responseText(from content: Any?) -> String? {
        if let string = content as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parts = content as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String ?? $0["content"] as? String }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func decodeSegments(_ response: String) throws -> [TranslationSegmentResult] {
        var candidate = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("```") {
            candidate = candidate
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = candidate.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = object["translations"],
              let translationsData = try? JSONSerialization.data(withJSONObject: translations),
              let decoded = try? JSONDecoder().decode([TranslationSegmentResult].self, from: translationsData) else {
            throw TranslationProviderError.invalidSegmentResponse
        }
        return decoded
    }

    private func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? [String: Any] {
            return error["message"] as? String ?? error["detail"] as? String
        }
        return object["message"] as? String ?? object["detail"] as? String
    }
}
