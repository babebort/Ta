@preconcurrency import Foundation

public enum VisionClientError: LocalizedError, Equatable {
    case invalidEndpoint(String)
    case missingModel
    case missingAPIKey
    case invalidResponse
    case emptyResponse
    case reasoningOnlyOutput(truncated: Bool)
    case server(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let message): message
        case .missingModel: "No vision model configured yet."
        case .missingAPIKey: "No API key configured yet."
        case .invalidResponse: "The model service returned an unparsable response."
        case .emptyResponse: "The model returned no recognition content."
        case .reasoningOnlyOutput(let truncated):
            truncated
                ? "Recognition failed: the output budget was consumed by the reasoning process and was truncated before producing any text. Please turn off deep thinking for this model, or raise the output limit and try again."
                : "The model only returned its reasoning process, with no recognized text. Please turn off deep thinking and try again."
        case .server(let statusCode, let message): "Model service error (\(statusCode)): \(message)"
        }
    }
}

public struct OpenAICompatibleVisionClient: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func recognize(
        baseURL: String,
        model: String,
        apiKey: String,
        imageData: Data,
        mimeType: String = "image/jpeg",
        prompt: String
    ) async throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw VisionClientError.missingModel }
        guard !trimmedKey.isEmpty else { throw VisionClientError.missingAPIKey }
        let endpoint = try endpointURL(from: baseURL)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")

        let dataURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        var body: [String: Any] = [
            "model": trimmedModel,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": dataURL]]
                ]
            ]],
            "temperature": 0,
            "max_tokens": 4096
        ]
        OpenAIChatResponseSupport.applyThinkingPreference(to: &body, host: endpoint.host)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VisionClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw VisionClientError.server(
                statusCode: httpResponse.statusCode,
                message: errorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = responseText(from: message["content"]),
              !text.isEmpty else {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               OpenAIChatResponseSupport.reasoningText(in: object)?.isEmpty == false {
                throw VisionClientError.reasoningOnlyOutput(
                    truncated: OpenAIChatResponseSupport.isLengthTruncated(object)
                )
            }
            throw VisionClientError.emptyResponse
        }
        return text
    }

    private func endpointURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VisionClientError.invalidEndpoint("Please configure the Base URL first.")
        }
        if let validation = ProviderEndpointValidator().validationMessage(for: trimmed) {
            throw VisionClientError.invalidEndpoint(validation)
        }
        guard var components = URLComponents(string: trimmed), components.url != nil else {
            throw VisionClientError.invalidEndpoint("Invalid Base URL format.")
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("chat/completions") {
            return components.url!
        }
        components.path = "/" + ([path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/"))
        guard let url = components.url else {
            throw VisionClientError.invalidEndpoint("Invalid Base URL format.")
        }
        return url
    }

    private func responseText(from content: Any?) -> String? {
        if let string = content as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parts = content as? [[String: Any]] {
            let strings = parts.compactMap { part -> String? in
                if let text = part["text"] as? String { return text }
                if let text = part["content"] as? String { return text }
                return nil
            }
            return strings.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String
    }
}
