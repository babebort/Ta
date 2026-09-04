@preconcurrency import Foundation

public enum VisionProviderKind: String, CaseIterable, Codable, Sendable {
    case openAICompatible
    case azureOpenAI
    case anthropic
    case googleGemini

    public var displayName: String {
        switch self {
        case .openAICompatible: "OpenAI-compatible"
        case .azureOpenAI: "Azure OpenAI"
        case .anthropic: "Anthropic Claude"
        case .googleGemini: "Google Gemini"
        }
    }
}

public enum MultimodalTaskTemplate: String, CaseIterable, Codable, Sendable {
    case general
    case extractText
    case translateChinese
    case translateEnglish
    case explainCode
    case tableMarkdown
    case tableCSV
    case formulaLaTeX

    public var displayName: String {
        switch self {
        case .general: "General Recognition"
        case .extractText: "Extract Text"
        case .translateChinese: "Translate to Chinese"
        case .translateEnglish: "Translate to English"
        case .explainCode: "Extract & Explain Code"
        case .tableMarkdown: "Table to Markdown"
        case .tableCSV: "Table to CSV"
        case .formulaLaTeX: "Formula to LaTeX"
        }
    }

    public var prompt: String {
        switch self {
        case .general:
            """
            This is a visual-understanding task, not plain text recognition. First describe the actual subjects visible in the image — people or animals, objects, scene, actions, colors, and composition; even if the image has no text at all, you must still describe the visual content and must not just answer "no text". If the image contains text, accurately transcribe it, preserving the original language, paragraphs, lists, code, and table structure. Output the result directly — do not guess at anything that is unclear.
            """
        case .extractText:
            "Extract all visible text in the screenshot verbatim, preserving reading order, paragraphs, and line breaks; do not summarize, translate, or add anything."
        case .translateChinese:
            "Recognize the content in the screenshot and translate it into natural, accurate Chinese; keep code, proper nouns, and numbers as-is. Output only the translation."
        case .translateEnglish:
            "Recognize the content in the screenshot and translate it into natural, accurate English; keep code, proper nouns, and numbers as-is. Output only the translation."
        case .explainCode:
            "Extract the code in the screenshot, first outputting a complete, copyable code block, then briefly explain the language, purpose, and any obvious issues; do not invent code that is obscured."
        case .tableMarkdown:
            "Recognize the table in the screenshot and output it strictly row-by-row, column-by-column as a Markdown table. Represent merged cells using the closest repeated value; do not output any extra explanation."
        case .tableCSV:
            "Recognize the table in the screenshot and output valid CSV. Correctly escape commas, quotes, and line breaks; output only the CSV content."
        case .formulaLaTeX:
            "Recognize the mathematical formula in the screenshot and output copyable LaTeX; use the aligned environment for multi-line formulas. Output only the LaTeX — do not explain or guess at unclear symbols."
        }
    }
}

public struct MultimodalProviderClient: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func recognize(
        provider: VisionProviderKind,
        baseURL: String,
        model: String,
        apiKey: String,
        imageData: Data,
        mimeType: String = "image/jpeg",
        prompt: String
    ) async throws -> String {
        if provider == .openAICompatible {
            return try await OpenAICompatibleVisionClient(session: session).recognize(
                baseURL: baseURL,
                model: model,
                apiKey: apiKey,
                imageData: imageData,
                mimeType: mimeType,
                prompt: prompt
            )
        }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw VisionClientError.missingModel }
        guard !trimmedKey.isEmpty else { throw VisionClientError.missingAPIKey }
        let endpoint = try endpoint(provider: provider, baseURL: baseURL, model: trimmedModel)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let base64 = imageData.base64EncodedString()
        let body: [String: Any]
        switch provider {
        case .azureOpenAI:
            request.setValue(trimmedKey, forHTTPHeaderField: "api-key")
            var azureBody = openAIChatBody(
                model: trimmedModel,
                dataURL: "data:\(mimeType);base64,\(base64)",
                prompt: prompt
            )
            OpenAIChatResponseSupport.applyThinkingPreference(to: &azureBody, host: endpoint.host)
            body = azureBody
        case .anthropic:
            request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": trimmedModel,
                "max_tokens": 2048,
                "messages": [[
                    "role": "user",
                    "content": [
                        ["type": "image", "source": ["type": "base64", "media_type": mimeType, "data": base64]],
                        ["type": "text", "text": prompt]
                    ]
                ]]
            ]
        case .googleGemini:
            request.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
            body = [
                "contents": [[
                    "parts": [
                        ["inlineData": ["mimeType": mimeType, "data": base64]],
                        ["text": prompt]
                    ]
                ]],
                "generationConfig": ["temperature": 0, "maxOutputTokens": 2048]
            ]
        case .openAICompatible:
            preconditionFailure("Handled above")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VisionClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw VisionClientError.server(
                statusCode: http.statusCode,
                message: errorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        let parsedObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let text = parsedObject.flatMap({ responseText(provider: provider, object: $0) }), !text.isEmpty {
            return text
        }
        if let parsedObject, let reasoningError = visionReasoningOutcome(object: parsedObject) {
            throw reasoningError
        }
        throw VisionClientError.emptyResponse
    }

    private func visionReasoningOutcome(object: [String: Any]) -> VisionClientError? {
        guard OpenAIChatResponseSupport.reasoningText(in: object)?.isEmpty == false else { return nil }
        return .reasoningOnlyOutput(truncated: OpenAIChatResponseSupport.isLengthTruncated(object))
    }

    private func endpoint(provider: VisionProviderKind, baseURL: String, model: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VisionClientError.invalidEndpoint("Please configure the Base URL first.") }
        if let validation = ProviderEndpointValidator().validationMessage(for: trimmed) {
            throw VisionClientError.invalidEndpoint(validation)
        }
        guard var components = URLComponents(string: trimmed) else {
            throw VisionClientError.invalidEndpoint("Invalid Base URL format.")
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch provider {
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
        case .openAICompatible:
            break
        }
        guard let url = components.url else { throw VisionClientError.invalidEndpoint("Invalid Base URL format.") }
        return url
    }

    private func openAIChatBody(model: String, dataURL: String, prompt: String) -> [String: Any] {
        [
            "model": model,
            "messages": [["role": "user", "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": dataURL]]
            ]]],
            "temperature": 0,
            "max_tokens": 2048
        ]
    }

    private func responseText(provider: VisionProviderKind, object: [String: Any]) -> String? {
        switch provider {
        case .azureOpenAI:
            return OpenAIChatResponseSupport.contentText(in: object)
        case .anthropic:
            return (object["content"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .googleGemini:
            guard let candidate = (object["candidates"] as? [[String: Any]])?.first,
                  let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .openAICompatible:
            return nil
        }
    }

    private func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? [String: Any] {
            return error["message"] as? String ?? error["status"] as? String
        }
        return object["message"] as? String
    }
}
