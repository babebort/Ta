import Foundation
import AIScreenshotCore
import XCTest
@testable import AIScreenshotApp

final class AIProviderProfileStoreTests: XCTestCase {
    func testPersistsMultipleProfilesAndIndependentSelections() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let first = AIProviderProfile(
            name: "DeepSeek",
            baseURL: "https://api.deepseek.com",
            visionModel: "vision",
            textModel: "text"
        )
        let second = AIProviderProfile(
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            visionModel: "gpt-vision",
            textModel: "gpt-text"
        )

        _ = try fixture.store.saveProfile(first, apiKey: "first-key")
        _ = try fixture.store.saveProfile(second, apiKey: "second-key")
        _ = try fixture.store.setActiveProfile(id: first.id)
        _ = try fixture.store.setTranslationProfile(id: second.id)

        let reloaded = try fixture.store.loadState()
        XCTAssertEqual(reloaded.profiles, [first, second])
        XCTAssertEqual(reloaded.activeProfileID, first.id)
        XCTAssertEqual(reloaded.translationProfileID, second.id)
        XCTAssertEqual(try fixture.store.apiKey(for: second.id), "second-key")
    }

    func testTranslationEligibilityRequiresTextVisionEndpointAndKey() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        var profile = AIProviderProfile(name: "Incomplete", baseURL: "https://api.example.com")
        _ = try fixture.store.saveProfile(profile, apiKey: "secret")
        XCTAssertNotNil(fixture.store.translationEligibility(of: profile))

        profile.visionModel = "vision"
        profile.textModel = "text"
        _ = try fixture.store.saveProfile(profile)
        XCTAssertNil(fixture.store.translationEligibility(of: profile))
    }

    func testTextOnlyCodingPlanProfileDoesNotBecomeScreenshotDefault() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let profile = AIProviderProfile(
            name: "智谱 Coding Plan",
            baseURL: "https://open.bigmodel.cn/api/coding/paas/v4",
            visionModel: "",
            textModel: "glm-5.2"
        )

        let state = try fixture.store.saveProfile(profile, apiKey: "coding-plan-key")

        XCTAssertEqual(state.profiles, [profile])
        XCTAssertNil(state.activeProfileID)
        XCTAssertNil(state.translationProfileID)
        XCTAssertNotNil(fixture.store.translationEligibility(of: profile))
    }

    func testMigratesLegacyAIAndTranslationConfigurationsOnlyOnce() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set("https://api.example.com/v1", forKey: "providerBaseURL")
        fixture.defaults.set("legacy-vision", forKey: "providerVisionModel")
        fixture.defaults.set("legacy-text", forKey: "providerTextModel")
        fixture.defaults.set(VisionProviderKind.openAICompatible.rawValue, forKey: "providerKind")
        fixture.defaults.set("https://api.deepseek.com", forKey: "translationBaseURL")
        fixture.defaults.set("translate-text", forKey: "translationTextModel")
        fixture.defaults.set("translate-vision", forKey: "translationVisionModel")
        try fixture.secretStore.save("ai-secret", account: PersistentConfigurationIdentity.multimodalProviderAccount)
        try fixture.secretStore.save("translation-secret", account: PersistentConfigurationIdentity.translationProviderAccount)

        let firstLoad = try fixture.store.loadState()
        let secondLoad = try fixture.store.loadState()

        XCTAssertEqual(firstLoad, secondLoad)
        XCTAssertEqual(firstLoad.profiles.count, 2)
        XCTAssertEqual(try fixture.store.apiKey(for: try XCTUnwrap(firstLoad.activeProfileID)), "ai-secret")
        XCTAssertEqual(try fixture.store.apiKey(for: try XCTUnwrap(firstLoad.translationProfileID)), "translation-secret")
    }

    func testLegacyTranslationMergesWithMatchingAIProfile() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        fixture.defaults.set("https://api.deepseek.com", forKey: "providerBaseURL")
        fixture.defaults.set("same-vision", forKey: "providerVisionModel")
        fixture.defaults.set("same-text", forKey: "providerTextModel")
        fixture.defaults.set("https://api.deepseek.com/chat/completions", forKey: "translationBaseURL")
        fixture.defaults.set("same-text", forKey: "translationTextModel")
        fixture.defaults.set("same-vision", forKey: "translationVisionModel")
        try fixture.secretStore.save("shared-secret", account: PersistentConfigurationIdentity.translationProviderAccount)

        let state = try fixture.store.loadState()

        XCTAssertEqual(state.profiles.count, 1)
        XCTAssertEqual(state.activeProfileID, state.translationProfileID)
        XCTAssertEqual(try fixture.store.apiKey(for: try XCTUnwrap(state.translationProfileID)), "shared-secret")
    }

    private func makeFixture() throws -> Fixture {
        let suite = "com.kangarooking.AIScreenshot.tests.profiles.\(UUID().uuidString)"
        let service = "com.kangarooking.AIScreenshot.tests.profiles.keychain.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let secretStore = KeychainSecretStore(service: service)
        return Fixture(
            suite: suite,
            service: service,
            defaults: defaults,
            secretStore: secretStore,
            store: AIProviderProfileStore(defaults: defaults, secretStore: secretStore)
        )
    }

    private struct Fixture {
        let suite: String
        let service: String
        let defaults: UserDefaults
        let secretStore: KeychainSecretStore
        let store: AIProviderProfileStore

        func cleanup() {
            if let state = try? store.loadState() {
                for profile in state.profiles { try? secretStore.delete(account: store.keychainAccount(for: profile.id)) }
            }
            try? secretStore.delete(account: PersistentConfigurationIdentity.multimodalProviderAccount)
            try? secretStore.delete(account: PersistentConfigurationIdentity.translationProviderAccount)
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
