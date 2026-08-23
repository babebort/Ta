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
            let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            let prompt = try XCTUnwrap(content.first?["text"] as? String)
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
