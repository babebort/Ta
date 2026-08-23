import Foundation
import AIScreenshotCore

struct ProviderConfiguration: Codable, Equatable, Sendable {
    var name = "OpenAI-compatible"
    var baseURL = ""
    var visionModel = ""
    var textModel = ""

    var validationMessage: String? {
        ProviderEndpointValidator().validationMessage(for: baseURL)
    }
}
