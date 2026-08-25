import Foundation
import XCTest
@testable import AIScreenshotApp

final class PersistentConfigurationIdentityTests: XCTestCase {
    func testProductionPersistenceIdentifiersStayCompatibleWithExistingInstalls() {
        XCTAssertEqual(PersistentConfigurationIdentity.bundleIdentifier, "com.kangarooking.AIScreenshot")
        XCTAssertEqual(PersistentConfigurationIdentity.keychainService, "com.kangarooking.AIScreenshot.providers")
        XCTAssertEqual(PersistentConfigurationIdentity.multimodalProviderAccount, "openai-compatible-default")
        XCTAssertEqual(PersistentConfigurationIdentity.translationProviderAccount, "deepseek-translation-default")
        XCTAssertEqual(PersistentConfigurationIdentity.deepSeekOCRAccount, "deepseek-ocr-2")
    }

    func testPackagedBundleIdentifierMatchesPersistenceContract() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = projectRoot.appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(
            plist["CFBundleIdentifier"] as? String,
            PersistentConfigurationIdentity.bundleIdentifier
        )
    }

    func testNewStoreInstanceCanReadExistingKeychainItem() throws {
        let service = "com.kangarooking.AIScreenshot.tests.persistence.\(UUID().uuidString)"
        let account = "upgrade-compatible-account"
        let originalStore = KeychainSecretStore(service: service)
        let upgradedStore = KeychainSecretStore(service: service)
        defer { try? upgradedStore.delete(account: account) }

        try originalStore.save("preserved-secret", account: account)

        XCTAssertEqual(try upgradedStore.read(account: account), "preserved-secret")
    }

    func testNewDefaultsInstanceCanReadExistingModelConfiguration() throws {
        let suiteName = "com.kangarooking.AIScreenshot.tests.defaults.\(UUID().uuidString)"
        let currentVersion = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { currentVersion.removePersistentDomain(forName: suiteName) }

        currentVersion.set("https://api.example.com/v1", forKey: "providerBaseURL")
        currentVersion.set("vision-model", forKey: "providerVisionModel")
        currentVersion.set("全文翻译", forKey: "translationDefaultMode")

        let upgradedVersion = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertEqual(upgradedVersion.string(forKey: "providerBaseURL"), "https://api.example.com/v1")
        XCTAssertEqual(upgradedVersion.string(forKey: "providerVisionModel"), "vision-model")
        XCTAssertEqual(upgradedVersion.string(forKey: "translationDefaultMode"), "全文翻译")
    }
}
