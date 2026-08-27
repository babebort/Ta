import Foundation
import AIScreenshotCore

struct ProviderConfiguration: Codable, Equatable, Sendable {
    var name = "OpenAI-compatible"
    var baseURL = ""
    var visionModel = ""
    var textModel = ""

    var validationMessage: String? {
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先选择服务商，或在高级设置中填写服务地址。"
        }
        if let endpointError = ProviderEndpointValidator().validationMessage(for: baseURL) {
            return endpointError
        }
        if visionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写一个支持图片输入的视觉模型。"
        }
        return nil
    }
}
