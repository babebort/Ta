import AIScreenshotCore
import XCTest
@testable import AIScreenshotApp

final class TranslationModeRoutingTests: XCTestCase {
    func testToolbarTranslationUsesConfiguredDefault() {
        for configuredDefault in ScreenshotTranslationMode.allCases {
            XCTAssertEqual(
                TranslationModeRouting.mode(
                    for: .translate,
                    configuredDefault: configuredDefault
                ),
                configuredDefault
            )
        }
    }

    func testDedicatedTranslationShortcutAlwaysUsesTextOnlyMode() {
        XCTAssertEqual(
            TranslationModeRouting.mode(
                for: .translateText,
                configuredDefault: .fullImage
            ),
            .textOnly
        )
    }

    func testUnrelatedActionDoesNotResolveTranslationMode() {
        XCTAssertNil(
            TranslationModeRouting.mode(
                for: .copyImage,
                configuredDefault: .fullImage
            )
        )
    }
}
