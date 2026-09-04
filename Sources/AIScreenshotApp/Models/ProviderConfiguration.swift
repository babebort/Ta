import Foundation
import AIScreenshotCore

struct ProviderConfiguration: Codable, Equatable, Sendable {
    var name = "OpenAI-compatible"
    var baseURL = ""
    var visionModel = ""
    var textModel = ""

    var validationMessage: String? {
        if baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please select a provider, or enter a service URL in Advanced Settings."
        }
        if let endpointError = ProviderEndpointValidator().validationMessage(for: baseURL) {
            return endpointError
        }
        if visionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please enter a vision model that supports image input."
        }
        return nil
    }
}
