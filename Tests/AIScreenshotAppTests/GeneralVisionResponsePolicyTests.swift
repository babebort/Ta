import Testing
@testable import AIScreenshotApp

struct GeneralVisionResponsePolicyTests {
    @Test("纯文字缺失回答会触发一次视觉理解重试")
    func retriesTextOnlyAnswer() {
        #expect(GeneralVisionResponsePolicy.shouldRetry("图片中未包含任何文字内容。"))
        #expect(GeneralVisionResponsePolicy.shouldRetry("No text in the image."))
    }

    @Test("已经描述画面时不重复调用模型")
    func keepsUsefulVisualDescription() {
        #expect(!GeneralVisionResponsePolicy.shouldRetry("图片中没有文字，主体是一只站立的袋鼠，背景为浅色。"))
        #expect(!GeneralVisionResponsePolicy.shouldRetry("画面是一只袋鼠的红色线稿图案。"))
    }

    @Test("恢复提示明确要求描述无文字图片")
    func recoveryPromptIsVisual() {
        #expect(GeneralVisionResponsePolicy.recoveryPrompt.contains("不是 OCR"))
        #expect(GeneralVisionResponsePolicy.recoveryPrompt.contains("动物"))
        #expect(GeneralVisionResponsePolicy.recoveryPrompt.contains("即使没有任何文字"))
    }
}
