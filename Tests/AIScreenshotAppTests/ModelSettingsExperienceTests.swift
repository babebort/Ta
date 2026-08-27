import AIScreenshotCore
import XCTest
@testable import AIScreenshotApp

final class ModelSettingsExperienceTests: XCTestCase {
    func testDeepSeekPresetProvidesACompleteEndpointAndVisionModel() {
        XCTAssertEqual(ModelProviderPreset.deepSeek.providerKind, .openAICompatible)
        XCTAssertEqual(ModelProviderPreset.deepSeek.baseURL, "https://api.deepseek.com")
        XCTAssertEqual(
            ModelProviderPreset.deepSeek.suggestedVisionModel,
            TranslationConfiguration.defaultVisionModel
        )
        XCTAssertEqual(ModelProviderPreset.deepSeek.suggestedTextModel, TranslationConfiguration.defaultTextModel)
    }

    func testZhipuPresetsUseCurrentOfficialChannels() {
        XCTAssertEqual(ModelProviderPreset.zhipuAPI.providerKind, .openAICompatible)
        XCTAssertEqual(ModelProviderPreset.zhipuAPI.baseURL, "https://open.bigmodel.cn/api/paas/v4")
        XCTAssertEqual(ModelProviderPreset.zhipuAPI.suggestedVisionModel, "glm-5v-turbo")
        XCTAssertEqual(ModelProviderPreset.zhipuAPI.suggestedTextModel, "glm-5.2")
        XCTAssertTrue(ModelProviderPreset.zhipuAPI.supportsVisionDirectly)

        XCTAssertEqual(ModelProviderPreset.zhipuCodingPlan.providerKind, .openAICompatible)
        XCTAssertEqual(ModelProviderPreset.zhipuCodingPlan.baseURL, "https://open.bigmodel.cn/api/coding/paas/v4")
        XCTAssertNil(ModelProviderPreset.zhipuCodingPlan.suggestedVisionModel)
        XCTAssertEqual(ModelProviderPreset.zhipuCodingPlan.suggestedTextModel, "glm-5.2")
        XCTAssertFalse(ModelProviderPreset.zhipuCodingPlan.supportsVisionDirectly)
    }

    func testProviderBrandAssetsMatchTheSuppliedIcons() {
        XCTAssertEqual(ModelProviderPreset.deepSeek.brandAssetName, "deepseek")
        XCTAssertEqual(ModelProviderPreset.openAI.brandAssetName, "openai")
        XCTAssertEqual(ModelProviderPreset.anthropic.brandAssetName, "claude")
        XCTAssertEqual(ModelProviderPreset.gemini.brandAssetName, "gemini")
        XCTAssertEqual(ModelProviderPreset.openRouter.brandAssetName, "openrouter")
        XCTAssertEqual(ModelProviderPreset.zhipuAPI.brandAssetName, "zhipu")
        XCTAssertEqual(ModelProviderPreset.zhipuCodingPlan.brandAssetName, "zhipu")
        XCTAssertNil(ModelProviderPreset.custom.brandAssetName)
    }

    func testExistingProviderConfigurationMapsBackToFriendlyPreset() {
        XCTAssertEqual(
            ModelProviderPreset.matching(
                providerKind: VisionProviderKind.openAICompatible.rawValue,
                baseURL: "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions"
            ),
            .zhipuCodingPlan
        )
        XCTAssertEqual(
            ModelProviderPreset.matching(
                providerKind: VisionProviderKind.openAICompatible.rawValue,
                baseURL: "https://open.bigmodel.cn/api/paas/v4/chat/completions"
            ),
            .zhipuAPI
        )
        XCTAssertEqual(
            ModelProviderPreset.matching(
                providerKind: VisionProviderKind.openAICompatible.rawValue,
                baseURL: "https://openrouter.ai/api/v1/chat/completions"
            ),
            .openRouter
        )
        XCTAssertEqual(
            ModelProviderPreset.matching(
                providerKind: VisionProviderKind.azureOpenAI.rawValue,
                baseURL: "https://example.openai.azure.com"
            ),
            .azure
        )
    }

    func testSetupProgressExplainsTheNextMissingStep() {
        XCTAssertEqual(
            ModelSetupProgress(hasEndpoint: false, hasAPIKey: false, hasVisionModel: false, hasTextModel: false).nextStep,
            "先选择服务商"
        )
        XCTAssertEqual(
            ModelSetupProgress(hasEndpoint: true, hasAPIKey: false, hasVisionModel: true, hasTextModel: true).nextStep,
            "接下来填写 API Key"
        )
        XCTAssertEqual(
            ModelSetupProgress(hasEndpoint: true, hasAPIKey: true, hasVisionModel: false, hasTextModel: true).nextStep,
            "填写视觉模型"
        )
        XCTAssertEqual(
            ModelSetupProgress(hasEndpoint: true, hasAPIKey: true, hasVisionModel: true, hasTextModel: false).nextStep,
            "最后填写文字模型"
        )
        let complete = ModelSetupProgress(hasEndpoint: true, hasAPIKey: true, hasVisionModel: true, hasTextModel: true)
        XCTAssertTrue(complete.isComplete)
        XCTAssertEqual(complete.completedSteps, 4)
        XCTAssertEqual(complete.nextStep, "可以保存并测试连接")
    }

    func testProviderValidationUsesBeginnerFriendlyMissingFieldMessages() {
        XCTAssertEqual(
            ProviderConfiguration().validationMessage,
            "请先选择服务商，或在高级设置中填写服务地址。"
        )
        XCTAssertEqual(
            ProviderConfiguration(baseURL: "https://api.example.com", visionModel: "").validationMessage,
            "请填写一个支持图片输入的视觉模型。"
        )
    }

    func testGuidedSetupKeepsTheApprovedThreeStepJourney() {
        XCTAssertEqual(ModelSetupStep.allCases.map(\.title), [
            "选择服务商",
            "填写 API Key",
            "测试并保存",
        ])
    }

    func testGuidedSetupChoosesTheFirstIncompleteStep() {
        XCTAssertEqual(
            ModelSetupStep.recommended(
                for: ModelSetupProgress(
                    hasEndpoint: false,
                    hasAPIKey: false,
                    hasVisionModel: false,
                    hasTextModel: false
                )
            ),
            .provider
        )
        XCTAssertEqual(
            ModelSetupStep.recommended(
                for: ModelSetupProgress(
                    hasEndpoint: true,
                    hasAPIKey: false,
                    hasVisionModel: true,
                    hasTextModel: true
                )
            ),
            .credentials
        )
        XCTAssertEqual(
            ModelSetupStep.recommended(
                for: ModelSetupProgress(
                    hasEndpoint: true,
                    hasAPIKey: true,
                    hasVisionModel: true,
                    hasTextModel: true
                )
            ),
            .complete
        )
    }

    func testGuidedProviderOrderMatchesTheApprovedDesign() {
        XCTAssertEqual(
            ModelProviderPreset.guidedCases,
            [
                .zhipuAPI,
                .zhipuCodingPlan,
                .deepSeek,
                .openAI,
                .gemini,
                .anthropic,
                .openRouter,
                .azure,
                .custom,
            ]
        )
    }

    func testZhipuChannelsAreRecommendedAlongsideDeepSeek() {
        XCTAssertTrue(ModelProviderPreset.zhipuAPI.isRecommended)
        XCTAssertTrue(ModelProviderPreset.zhipuCodingPlan.isRecommended)
        XCTAssertTrue(ModelProviderPreset.deepSeek.isRecommended)
        XCTAssertFalse(ModelProviderPreset.openAI.isRecommended)
    }

    func testPresetSuggestedNamesDoNotLeakIntoCustomConfiguration() {
        XCTAssertEqual(ModelProviderPreset.zhipuAPI.suggestedConfigurationName, "智谱 API 日常")
        XCTAssertEqual(ModelProviderPreset.zhipuCodingPlan.suggestedConfigurationName, "智谱 Coding Plan 日常")
        XCTAssertEqual(ModelProviderPreset.custom.suggestedConfigurationName, "自定义模型")
    }
}
