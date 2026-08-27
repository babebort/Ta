import XCTest
@testable import AIScreenshotApp

final class ScreenshotTranslationServiceErrorTests: XCTestCase {
    func testLocalOCRFailureUsesActionableMessageInsteadOfRawCoreMLError() {
        let message = ScreenshotTranslationServiceError.localOCRUnavailableForImage.errorDescription

        XCTAssertEqual(
            message,
            "本地文字识别暂时无法定位图片中的文字，因此不能生成全文翻译图片。请重试，或在翻译设置中改用“翻译文字并复制”。"
        )
        XCTAssertFalse(message?.contains("com.apple.CoreML") == true)
    }
}
