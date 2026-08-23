import AppKit
import XCTest
@testable import AIScreenshotCore

final class DeepSeekTranslationIntegrationTests: XCTestCase {
    private let endpoint = "https://api.deepseek.com/chat/completions"

    func testRealDeepSeekTranslationContracts() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RUN_REAL_DEEPSEEK_TRANSLATION_TESTS"] == "1",
              let apiKey = environment["TRANSLATION_TEST_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("Set RUN_REAL_DEEPSEEK_TRANSLATION_TESTS=1 and TRANSLATION_TEST_KEY for the live API test")
        }

        let client = TranslationProviderClient()
        let text = try await client.translateText(
            baseURL: endpoint,
            model: "deepseek-v4-flash",
            apiKey: apiKey,
            text: "Screenshot translation is ready.",
            sourceLanguage: "English",
            targetLanguage: "Simplified Chinese"
        )
        XCTAssertFalse(text.isEmpty)

        let segments = try await client.translateSegments(
            baseURL: endpoint,
            model: "deepseek-v4-flash",
            apiKey: apiKey,
            segments: [
                TranslationSourceSegment(id: 0, text: "Open settings"),
                TranslationSourceSegment(id: 1, text: "Copy result")
            ],
            sourceLanguage: "English",
            targetLanguage: "Simplified Chinese"
        )
        XCTAssertEqual(segments.map(\.id), [0, 1])
        XCTAssertTrue(segments.allSatisfy { !$0.text.isEmpty })

        let visionText = try await client.translateImage(
            baseURL: endpoint,
            model: "deepseek-v4-flash-vision-exp",
            apiKey: apiKey,
            imageData: try makePNG(text: "Hello screenshot"),
            sourceLanguage: "English",
            targetLanguage: "Simplified Chinese"
        )
        XCTAssertFalse(visionText.isEmpty)
    }

    private func makePNG(text: String) throws -> Data {
        let size = NSSize(width: 640, height: 180)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        text.draw(
            at: NSPoint(x: 32, y: 64),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "DeepSeekTranslationIntegrationTests", code: 1)
        }
        return data
    }
}
