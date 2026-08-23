import AppKit
import XCTest
import AIScreenshotCore
@testable import AIScreenshotApp

final class TranslatedImageRendererTests: XCTestCase {
    func testFullTranslationPreservesOriginalDimensions() throws {
        let image = try makeImage(width: 320, height: 160)
        let output = try TranslatedImageRenderer().render(
            image: image,
            lines: [TranslatedOCRLine(
                sourceText: "Hello",
                translatedText: "你好",
                boundingBox: CGRect(x: 0.1, y: 0.35, width: 0.4, height: 0.24),
                confidence: 0.95
            )],
            mode: .fullImage,
            targetLanguage: "简体中文"
        )
        XCTAssertEqual(output.width, image.width)
        XCTAssertEqual(output.height, image.height)
    }

    func testBilingualTranslationAppendsPanelBelowOriginal() throws {
        let image = try makeImage(width: 360, height: 180)
        let output = try TranslatedImageRenderer().render(
            image: image,
            lines: [TranslatedOCRLine(
                sourceText: "Screenshot translation",
                translatedText: "截图翻译",
                boundingBox: CGRect(x: 0.08, y: 0.35, width: 0.72, height: 0.2),
                confidence: 0.95
            )],
            mode: .bilingualImage,
            targetLanguage: "简体中文"
        )
        XCTAssertEqual(output.width, image.width)
        XCTAssertGreaterThan(output.height, image.height)
        XCTAssertEqual(try pixel(output, x: 4, y: 4), try pixel(image, x: 4, y: 4))
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw RendererTestError.imageCreationFailed }
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw RendererTestError.imageCreationFailed }
        return image
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        guard let crop = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let provider = crop.dataProvider,
              let data = provider.data else { throw RendererTestError.imageCreationFailed }
        return Array((data as Data).prefix(4))
    }
}

private enum RendererTestError: Error {
    case imageCreationFailed
}
