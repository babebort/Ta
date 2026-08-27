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
        case .general: "通用识图"
        case .extractText: "精确取字"
        case .translateChinese: "翻译成中文"
        case .translateEnglish: "翻译成英文"
        case .explainCode: "提取并解释代码"
        case .tableMarkdown: "表格转 Markdown"
        case .tableCSV: "表格转 CSV"
        case .formulaLaTeX: "公式转 LaTeX"
        }
    }

    public var prompt: String {
        switch self {
        case .general:
            """
            这是视觉理解任务，不是单纯的文字识别。请先描述图片中实际可见的主体、人物或动物、物体、场景、动作、颜色与构图；即使图片完全没有文字，也必须说明画面内容，不能只回答“没有文字”。如果图片包含文字，再准确整理文字，并保留原语言、段落、列表、代码和表格结构。直接输出结果，不要猜测看不清的内容。
            """
        case .extractText:
            "逐字提取截图中的全部可见文字，保持阅读顺序、段落和换行；不要总结、翻译或补写。"
        case .translateChinese:
            "识别截图中的内容并翻译成自然、准确的中文；代码、专有名词和数字保持原意。只输出译文。"
        case .translateEnglish:
            "识别截图中的内容并翻译成自然、准确的英文；代码、专有名词和数字保持原意。只输出译文。"
        case .explainCode:
            "提取截图中的代码，先输出可复制的完整代码块，再用简洁中文说明语言、用途和明显问题；不要虚构被遮挡的代码。"
        case .tableMarkdown:
            "识别截图中的表格，严格按行列输出为 Markdown 表格。合并单元格用最接近的重复值表达，不要输出额外说明。"
        case .tableCSV:
            "识别截图中的表格并输出合法 CSV。正确转义逗号、引号和换行，只输出 CSV 内容。"
        case .formulaLaTeX:
            "识别截图中的数学公式并输出可复制的 LaTeX；多行公式使用 aligned 环境。只输出 LaTeX，不要解释或猜测模糊符号。"
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
        guard !trimmed.isEmpty else { throw VisionClientError.invalidEndpoint("请先配置 Base URL。") }
        if let validation = ProviderEndpointValidator().validationMessage(for: trimmed) {
            throw VisionClientError.invalidEndpoint(validation)
        }
        guard var components = URLComponents(string: trimmed) else {
            throw VisionClientError.invalidEndpoint("Base URL 格式无效。")
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
        guard let url = components.url else { throw VisionClientError.invalidEndpoint("Base URL 格式无效。") }
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
