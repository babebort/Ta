import Foundation
import XCTest
@testable import AIScreenshotCore

final class TranslationProviderClientTests: XCTestCase {
    override func tearDown() {
        TranslationURLProtocol.handler = nil
        super.tearDown()
    }

    func testDeepSeekTextTranslationUsesFullEndpointAndDisablesThinking() async throws {
        TranslationURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
            let json = try XCTUnwrap(Self.jsonBody(request))
            XCTAssertEqual(json["model"] as? String, "deepseek-v4-flash")
            XCTAssertEqual((json["thinking"] as? [String: Any])?["type"] as? String, "disabled")
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            let prompt = try XCTUnwrap(messages.first?["content"] as? String)
            XCTAssertTrue(prompt.contains("自动检测"))
            XCTAssertTrue(prompt.contains("简体中文"))
            XCTAssertTrue(prompt.contains("Screenshot translation"))
            return Self.response(for: request, content: "截图翻译")
        }

        let result = try await makeClient().translateText(
            baseURL: "https://api.deepseek.com/chat/completions，",
            model: "deepseek-v4-flash",
            apiKey: "secret",
            text: "Screenshot translation",
            sourceLanguage: "自动检测",
            targetLanguage: "简体中文"
        )
        XCTAssertEqual(result, "截图翻译")
    }

    func testSegmentTranslationRequiresEveryStableID() async throws {
        TranslationURLProtocol.handler = { request in
            let json = try XCTUnwrap(Self.jsonBody(request))
            XCTAssertEqual((json["response_format"] as? [String: Any])?["type"] as? String, "json_object")
            return Self.response(
                for: request,
                content: #"{"translations":[{"id":1,"text":"世界"},{"id":0,"text":"你好"}]}"#
            )
        }
        let results = try await makeClient().translateSegments(
            baseURL: "https://api.example.com/v1",
            model: "translator",
            apiKey: "secret",
            segments: [
                TranslationSourceSegment(id: 0, text: "Hello"),
                TranslationSourceSegment(id: 1, text: "World")
            ],
            sourceLanguage: "英文",
            targetLanguage: "简体中文"
        )
        XCTAssertEqual(results, [
            TranslationSegmentResult(id: 0, text: "你好"),
            TranslationSegmentResult(id: 1, text: "世界")
        ])
    }

    func testVisionTranslationEmbedsImageDataURL() async throws {
        TranslationURLProtocol.handler = { request in
            let json = try XCTUnwrap(Self.jsonBody(request))
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            let imagePart = try XCTUnwrap(content.first { ($0["type"] as? String) == "image_url" })
            let imageURL = try XCTUnwrap(imagePart["image_url"] as? [String: Any])
            XCTAssertEqual(imageURL["url"] as? String, "data:image/png;base64,AQID")
            return Self.response(for: request, content: "视觉译文")
        }
        let result = try await makeClient().translateImage(
            baseURL: "https://api.deepseek.com",
            model: "deepseek-v4-flash-vision-exp",
            apiKey: "secret",
            imageData: Data([1, 2, 3]),
            sourceLanguage: "自动检测",
            targetLanguage: "简体中文"
        )
        XCTAssertEqual(result, "视觉译文")
    }

    func testAnthropicTranslationUsesMessagesProtocol() async throws {
        TranslationURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            let json = try XCTUnwrap(Self.jsonBody(request))
            XCTAssertEqual(json["model"] as? String, "claude-sonnet")
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            XCTAssertEqual(content.first?["type"] as? String, "text")
            return Self.anthropicResponse(for: request, content: "你好")
        }
        let result = try await makeClient().translateText(
            baseURL: "https://api.anthropic.com",
            model: "claude-sonnet",
            apiKey: "secret",
            text: "Hello",
            sourceLanguage: "英文",
            targetLanguage: "简体中文",
            provider: .anthropic
        )
        XCTAssertEqual(result, "你好")
    }

    func testGeminiVisionTranslationUsesInlineData() async throws {
        TranslationURLProtocol.handler = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-vision:generateContent"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "secret")
            let json = try XCTUnwrap(Self.jsonBody(request))
            let contents = try XCTUnwrap(json["contents"] as? [[String: Any]])
            let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
            let inlineData = try XCTUnwrap(parts.first?["inlineData"] as? [String: Any])
            XCTAssertEqual(inlineData["data"] as? String, "AQID")
            return Self.geminiResponse(for: request, content: "视觉译文")
        }
        let result = try await makeClient().translateImage(
            baseURL: "https://generativelanguage.googleapis.com",
            model: "gemini-vision",
            apiKey: "secret",
            imageData: Data([1, 2, 3]),
            sourceLanguage: "自动检测",
            targetLanguage: "简体中文",
            provider: .googleGemini
        )
        XCTAssertEqual(result, "视觉译文")
    }

    func testAzureTranslationUsesAPIKeyHeaderAndAzureEndpoint() async throws {
        TranslationURLProtocol.handler = { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://example.openai.azure.com/openai/v1/chat/completions"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "secret")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return Self.response(for: request, content: "OK")
        }
        let result = try await makeClient().testConnection(
            baseURL: "https://example.openai.azure.com",
            model: "deployment-name",
            apiKey: "secret",
            provider: .azureOpenAI
        )
        XCTAssertEqual(result, "OK")
    }

    func testZhipuConnectionTestDisablesThinkingAndRaisesTokenBudget() async throws {
        TranslationURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://open.bigmodel.cn/api/paas/v4/chat/completions")
            let json = try XCTUnwrap(Self.jsonBody(request))
            XCTAssertEqual(json["model"] as? String, "glm-4.6")
            XCTAssertEqual((json["thinking"] as? [String: Any])?["type"] as? String, "disabled")
            let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.first?["content"] as? String, "Reply with exactly: OK")
            let maxTokens = try XCTUnwrap(json["max_tokens"] as? Int)
            XCTAssertGreaterThanOrEqual(maxTokens, 256)
            return Self.response(for: request, content: "OK")
        }
        let result = try await makeClient().testConnection(
            baseURL: "https://open.bigmodel.cn/api/paas/v4",
            model: "glm-4.6",
            apiKey: "secret"
        )
        XCTAssertEqual(result, "OK")
    }

    func testReasoningOnlyLengthTruncatedResponseExplainsGuidance() async throws {
        TranslationURLProtocol.handler = { request in
            let payload: [String: Any] = [
                "choices": [[
                    "message": [
                        "content": "",
                        "reasoning_content": "Breaking the sentence down before translating..."
                    ],
                    "finish_reason": "length"
                ]]
            ]
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try! JSONSerialization.data(withJSONObject: payload)
            )
        }
        do {
            _ = try await makeClient().translateText(
                baseURL: "https://open.bigmodel.cn/api/paas/v4",
                model: "glm-4.6",
                apiKey: "secret",
                text: "Hello",
                sourceLanguage: "英文",
                targetLanguage: "简体中文"
            )
            XCTFail("Expected reasoning-only error")
        } catch let error as TranslationProviderError {
            XCTAssertEqual(error, .reasoningOnlyOutput(truncated: true))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeClient() -> TranslationProviderClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationURLProtocol.self]
        return TranslationProviderClient(session: URLSession(configuration: configuration))
    }

    private static func jsonBody(_ request: URLRequest) -> [String: Any]? {
        guard let data = bodyData(from: request) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func response(for request: URLRequest, content: String) -> (HTTPURLResponse, Data) {
        let escaped = try! JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content]]]
        ])
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            escaped
        )
    }

    private static func anthropicResponse(for request: URLRequest, content: String) -> (HTTPURLResponse, Data) {
        let data = try! JSONSerialization.data(withJSONObject: [
            "content": [["type": "text", "text": content]]
        ])
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            data
        )
    }

    private static func geminiResponse(for request: URLRequest, content: String) -> (HTTPURLResponse, Data) {
        let data = try! JSONSerialization.data(withJSONObject: [
            "candidates": [["content": ["parts": [["text": content]]]]]
        ])
        return (
            HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            data
        )
    }
}

private final class TranslationURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw TranslationURLProtocolError.missingHandler }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum TranslationURLProtocolError: Error {
    case missingHandler
}
