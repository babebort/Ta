import Foundation
import XCTest
@testable import AIScreenshotCore

final class MultimodalProviderClientTests: XCTestCase {
    override func tearDown() {
        ProviderURLProtocol.handler = nil
        super.tearDown()
    }

    func testAnthropicUsesMessagesVisionContract() async throws {
        ProviderURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "secret")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            let body = try XCTUnwrap(Self.jsonBody(request))
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            XCTAssertNotNil(content.first { $0["type"] as? String == "image" })
            return Self.response(request, #"{"content":[{"type":"text","text":"Claude result"}]}"#)
        }

        let result = try await makeClient().recognize(
            provider: .anthropic,
            baseURL: "https://api.anthropic.com",
            model: "claude-vision",
            apiKey: "secret",
            imageData: Data([1, 2]),
            prompt: "read"
        )
        XCTAssertEqual(result, "Claude result")
    }

    func testGeminiUsesGenerateContentInlineDataContract() async throws {
        ProviderURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash:generateContent")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "secret")
            let body = try XCTUnwrap(Self.jsonBody(request))
            XCTAssertNotNil(body["contents"])
            return Self.response(request, #"{"candidates":[{"content":{"parts":[{"text":"Gemini result"}]}}]}"#)
        }

        let result = try await makeClient().recognize(
            provider: .googleGemini,
            baseURL: "https://generativelanguage.googleapis.com",
            model: "gemini-flash",
            apiKey: "secret",
            imageData: Data([1, 2]),
            prompt: "read"
        )
        XCTAssertEqual(result, "Gemini result")
    }

    func testAzureUsesAPIKeyHeaderAndOpenAIV1Path() async throws {
        ProviderURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://resource.openai.azure.com/openai/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "api-key"), "secret")
            return Self.response(request, #"{"choices":[{"message":{"content":"Azure result"}}]}"#)
        }

        let result = try await makeClient().recognize(
            provider: .azureOpenAI,
            baseURL: "https://resource.openai.azure.com",
            model: "gpt-vision",
            apiKey: "secret",
            imageData: Data([1, 2]),
            prompt: "read"
        )
        XCTAssertEqual(result, "Azure result")
    }

    func testTaskTemplatesAreProviderIndependent() {
        XCTAssertTrue(MultimodalTaskTemplate.tableMarkdown.prompt.contains("Markdown"))
        XCTAssertTrue(MultimodalTaskTemplate.formulaLaTeX.prompt.contains("LaTeX"))
        XCTAssertTrue(MultimodalTaskTemplate.translateChinese.prompt.contains("中文"))
    }

    func testGeneralTaskDescribesVisualContentEvenWhenThereIsNoText() {
        let prompt = MultimodalTaskTemplate.general.prompt
        XCTAssertTrue(prompt.contains("视觉理解任务"))
        XCTAssertTrue(prompt.contains("动物"))
        XCTAssertTrue(prompt.contains("即使图片完全没有文字"))
        XCTAssertTrue(prompt.contains("不能只回答“没有文字”"))
    }

    private func makeClient() -> MultimodalProviderClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderURLProtocol.self]
        return MultimodalProviderClient(session: URLSession(configuration: configuration))
    }

    private static func jsonBody(_ request: URLRequest) -> [String: Any]? {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count >= 0 else { return nil }
                if count == 0 { break }
                collected.append(buffer, count: count)
            }
            data = collected
        } else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func response(_ request: URLRequest, _ json: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data(json.utf8))
    }
}

private final class ProviderURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
