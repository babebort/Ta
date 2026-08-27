import Foundation
import AIScreenshotCore
import XCTest
@testable import AIScreenshotApp

final class TranslationConfigurationTests: XCTestCase {
    func testTranslationPreferencesRemainIndependentFromSharedModelProfiles() throws {
        let suite = "com.kangarooking.AIScreenshot.tests.translation-preferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("日文", forKey: "translationSourceLanguage")
        defaults.set("英文", forKey: "translationTargetLanguage")
        defaults.set(ScreenshotTranslationMode.fullImage.rawValue, forKey: "translationDefaultMode")
        defaults.set(false, forKey: "translationUsesVisionFallback")

        let configuration = TranslationConfiguration.load(defaults: defaults)

        XCTAssertEqual(configuration.sourceLanguage, "日文")
        XCTAssertEqual(configuration.targetLanguage, "英文")
        XCTAssertEqual(configuration.defaultMode, .fullImage)
        XCTAssertFalse(configuration.usesVisionFallback)
        XCTAssertNil(configuration.validationMessage)
    }

    func testOnlyLanguagePreferencesAreValidatedAfterModelUnification() throws {
        let suite = "com.kangarooking.AIScreenshot.tests.translation-validation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("", forKey: "translationTargetLanguage")
        defaults.set("not-used-anymore", forKey: "translationBaseURL")
        defaults.set("", forKey: "translationTextModel")

        XCTAssertEqual(TranslationConfiguration.load(defaults: defaults).validationMessage, "请填写目标语言。")
    }
}
