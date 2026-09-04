@preconcurrency import Foundation

public enum DeepSeekOCRPromptMode: String, CaseIterable, Codable, Sendable {
    case plainText
    case documentMarkdown

    public var displayName: String {
        switch self {
        case .plainText: "Plain Text (recommended for screenshots)"
        case .documentMarkdown: "Markdown (preserves document structure)"
        }
    }

    public var prompt: String {
        switch self {
        case .plainText: "<image>\nFree OCR."
        case .documentMarkdown: "<image>\n<|grounding|>Convert the document to markdown."
        }
    }
}

public enum DeepSeekOCR2ClientError: LocalizedError, Equatable {
    case invalidEndpoint(String)
    case officialAPIUnsupported
    case missingModel
    case invalidResponse
    case emptyResponse
    case server(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let message): message
        case .officialAPIUnsupported:
            "The official DeepSeek API does not currently offer a DeepSeek-OCR-2 model endpoint; please enter the address of a vLLM, SGLang, or compatible service hosting this model."
        case .missingModel: "No DeepSeek OCR model name configured yet."
        case .invalidResponse: "The DeepSeek OCR service returned an unparsable response."
        case .emptyResponse: "DeepSeek OCR returned no recognition content."
        case .server(let statusCode, let message): "DeepSeek OCR service error (\(statusCode)): \(message)"
        }
    }
}

public struct DeepSeekOCR2Client: @unchecked Sendable {
    public static let latestOfficialModel = "deepseek-ai/DeepSeek-OCR-2"
    public static let recommendedLocalBaseURL = "http://127.0.0.1:8000/v1"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func recognize(
        baseURL: String,
        model: String,
        apiKey: String,
        imageData: Data,
        mimeType: String = "image/png",
        mode: DeepSeekOCRPromptMode
    ) async throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw DeepSeekOCR2ClientError.missingModel }
        let endpoint = try endpointURL(from: baseURL)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }

        let dataURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        let body: [String: Any] = [
            "model": trimmedModel,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": mode.prompt],
                    ["type": "image_url", "image_url": ["url": dataURL]]
                ]
            ]],
            "temperature": 0,
            "max_tokens": 4096
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekOCR2ClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DeepSeekOCR2ClientError.server(
                statusCode: http.statusCode,
                message: errorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = responseText(from: message["content"]),
              !text.isEmpty else {
            throw DeepSeekOCR2ClientError.emptyResponse
        }
        return text
    }

    private func endpointURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DeepSeekOCR2ClientError.invalidEndpoint("Please configure the DeepSeek OCR service address first.")
        }
        if let validation = ProviderEndpointValidator().validationMessage(for: trimmed) {
            throw DeepSeekOCR2ClientError.invalidEndpoint(validation)
        }
        guard var components = URLComponents(string: trimmed), components.url != nil else {
            throw DeepSeekOCR2ClientError.invalidEndpoint("Invalid DeepSeek OCR service address format.")
        }
        if components.host?.lowercased() == "api.deepseek.com" {
            throw DeepSeekOCR2ClientError.officialAPIUnsupported
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("chat/completions") {
            return components.url!
        }
        components.path = "/" + [path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url else {
            throw DeepSeekOCR2ClientError.invalidEndpoint("Invalid DeepSeek OCR service address format.")
        }
        return url
    }

    private func responseText(from content: Any?) -> String? {
        if let string = content as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parts = content as? [[String: Any]] {
            return parts.compactMap { part in
                part["text"] as? String ?? part["content"] as? String
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? [String: Any] {
            return error["message"] as? String ?? error["detail"] as? String
        }
        return object["message"] as? String ?? object["detail"] as? String
    }
}
