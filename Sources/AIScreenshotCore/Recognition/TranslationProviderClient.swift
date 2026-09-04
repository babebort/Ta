@preconcurrency import Foundation

public enum TranslationProviderError: LocalizedError, Equatable {
    case invalidEndpoint(String)
    case missingModel
    case missingAPIKey
    case emptyInput
    case invalidResponse
    case emptyResponse
    case invalidSegmentResponse
    case reasoningOnlyOutput(truncated: Bool)
    case server(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let message): message
        case .missingModel: "No translation model configured yet."
        case .missingAPIKey: "No translation API key configured yet."
        case .emptyInput: "There is no translatable text in the screenshot."
        case .invalidResponse: "The translation service returned an unparsable response."
        case .emptyResponse: "The translation model returned no content."
        case .invalidSegmentResponse: "The translation model did not return a complete segmented result. Please try again."
        case .reasoningOnlyOutput(let truncated):
            truncated
                ? "The model spent its entire output budget on its reasoning process and was truncated before producing any text. Please turn off deep thinking for this model, or raise the output limit and try again."
                : "The model only returned its reasoning process, with no body text. Please turn off deep thinking for this configuration and try again."
        case .server(let statusCode, let message): "Translation service error (\(statusCode)): \(message)"
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
        targetLanguage: String,
        provider: VisionProviderKind = .openAICompatible
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
            provider: provider,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            prompt: prompt,
            jsonMode: false
        )
    }

    public func translateSegments(
        baseURL: String,
        model: String,
        apiKey: String,
        segments: [TranslationSourceSegment],
        sourceLanguage: String,
        targetLanguage: String,
        provider: VisionProviderKind = .openAICompatible
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
            provider: provider,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            prompt: prompt,
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
        targetLanguage: String,
        provider: VisionProviderKind = .openAICompatible
    ) async throws -> String {
        let prompt = """
        Read all visible text in this screenshot and translate it from \(sourceLanguage) to \(targetLanguage).
        Preserve reading order, paragraphs, lists, code, numbers, and names.
        Do not describe the image or explain. Output only the translated text.
        """
        return try await complete(
            provider: provider,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            prompt: prompt,
            imageData: imageData,
            mimeType: mimeType,
            jsonMode: false
        )
    }

    public func testConnection(
        baseURL: String,
        model: String,
        apiKey: String,
        provider: VisionProviderKind = .openAICompatible
    ) async throws -> String {
        try await complete(
            provider: provider,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            prompt: "Reply with exactly: OK",
            jsonMode: false,
            maxTokens: 512
        )
    }

    private func complete(
        provider: VisionProviderKind,
        baseURL: String,
        model: String,
        apiKey: String,
        prompt: String,
        imageData: Data? = nil,
        mimeType: String = "image/png",
        jsonMode: Bool,
        maxTokens: Int = 4096
    ) async throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw TranslationProviderError.missingModel }
        guard !trimmedKey.isEmpty else { throw TranslationProviderError.missingAPIKey }
        let endpoint = try endpointURL(provider: provider, from: baseURL, model: trimmedModel)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any]
        switch provider {
        case .openAICompatible, .azureOpenAI:
            if provider == .azureOpenAI {
                request.setValue(trimmedKey, forHTTPHeaderField: "api-key")
            } else {
                request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            }
            let messageContent: Any
            if let imageData {
                var content: [[String: Any]] = [["type": "text", "text": prompt]]
                let dataURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
                content.append(["type": "image_url", "image_url": ["url": dataURL]])
                messageContent = content
            } else {
                // Text-only OpenAI-compatible models (notably GLM text models)
                // expect the canonical string form. A multimodal parts array is
                // reserved for requests that actually contain an image.
                messageContent = prompt
            }
            var openAIBody: [String: Any] = [
                "model": trimmedModel,
                "messages": [["role": "user", "content": messageContent]],
                "temperature": 0,
                "stream": false,
                "max_tokens": maxTokens
            ]
            OpenAIChatResponseSupport.applyThinkingPreference(to: &openAIBody, host: endpoint.host)
            if jsonMode { openAIBody["response_format"] = ["type": "json_object"] }
            body = openAIBody
        case .anthropic:
            request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var content: [[String: Any]] = []
            if let imageData {
                content.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": mimeType,
                        "data": imageData.base64EncodedString()
                    ]
                ])
            }
            content.append(["type": "text", "text": prompt])
            body = [
                "model": trimmedModel,
                "max_tokens": maxTokens,
                "temperature": 0,
                "messages": [["role": "user", "content": content]]
            ]
        case .googleGemini:
            request.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
            var parts: [[String: Any]] = []
            if let imageData {
                parts.append(["inlineData": [
                    "mimeType": mimeType,
                    "data": imageData.base64EncodedString()
                ]])
            }
            parts.append(["text": prompt])
            body = [
                "contents": [["parts": parts]],
                "generationConfig": ["temperature": 0, "maxOutputTokens": maxTokens]
            ]
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
        let parsedObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let text = parsedObject.flatMap({ responseText(provider: provider, object: $0) }), !text.isEmpty {
            return text
        }
        if let parsedObject, let detailedError = reasoningOutcome(provider: provider, object: parsedObject) {
            throw detailedError
        }
        throw TranslationProviderError.emptyResponse
    }

    private func reasoningOutcome(
        provider: VisionProviderKind,
        object: [String: Any]
    ) -> TranslationProviderError? {
        guard provider == .openAICompatible || provider == .azureOpenAI,
              OpenAIChatResponseSupport.reasoningText(in: object)?.isEmpty == false else {
            return nil
        }
        return .reasoningOnlyOutput(truncated: OpenAIChatResponseSupport.isLengthTruncated(object))
    }

    private func endpointURL(
        provider: VisionProviderKind,
        from rawValue: String,
        model: String
    ) throws -> URL {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "，,"))
        guard !trimmed.isEmpty else {
            throw TranslationProviderError.invalidEndpoint("Please configure the translation API address first.")
        }
        if let validation = ProviderEndpointValidator().validationMessage(for: trimmed) {
            throw TranslationProviderError.invalidEndpoint(validation)
        }
        guard var components = URLComponents(string: trimmed), components.url != nil else {
            throw TranslationProviderError.invalidEndpoint("Invalid translation API address format.")
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch provider {
        case .openAICompatible:
            if !path.hasSuffix("chat/completions") {
                components.path = "/" + [path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/")
            }
        case .azureOpenAI:
            if !path.hasSuffix("chat/completions") {
                components.path = "/" + [path, "openai/v1/chat/completions"].filter { !$0.isEmpty }.joined(separator: "/")
            }
        case .anthropic:
            if !path.hasSuffix("v1/messages") {
                components.path = "/" + [path, "v1/messages"].filter { !$0.isEmpty }.joined(separator: "/")
            }
        case .googleGemini:
            if !path.contains(":generateContent") {
                components.path = "/" + [path, "v1beta/models/\(model):generateContent"].filter { !$0.isEmpty }.joined(separator: "/")
            }
        }
        guard let url = components.url else {
            throw TranslationProviderError.invalidEndpoint("Invalid translation API address format.")
        }
        return url
    }

    private func responseText(provider: VisionProviderKind, object: [String: Any]) -> String? {
        switch provider {
        case .openAICompatible, .azureOpenAI:
            let choices = object["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            return responseText(from: message?["content"])
        case .anthropic:
            return (object["content"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .googleGemini:
            guard let candidate = (object["candidates"] as? [[String: Any]])?.first,
                  let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            return parts.compactMap { $0["text"] as? String }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
