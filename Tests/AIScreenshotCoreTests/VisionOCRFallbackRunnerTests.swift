import XCTest
@testable import AIScreenshotCore

final class VisionOCRFallbackRunnerTests: XCTestCase {
    func testCoreMLFailureFallsBackToLegacyRecognizer() async throws {
        let expected = OCRResult(
            text: "legacy result",
            contentType: .plainText,
            confidence: 0.9,
            languages: ["en-US"]
        )
        let result = try await VisionOCRFallbackRunner().run(
            document: {
                throw NSError(domain: "com.apple.CoreML", code: 0)
            },
            legacy: {
                expected
            }
        )

        XCTAssertEqual(result.text, expected.text)
    }

    func testCancellationDoesNotStartLegacyRecognizer() async {
        var legacyWasCalled = false

        do {
            _ = try await VisionOCRFallbackRunner().run(
                document: {
                    throw CancellationError()
                },
                legacy: {
                    legacyWasCalled = true
                    throw NSError(domain: "test", code: 1)
                }
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(legacyWasCalled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
