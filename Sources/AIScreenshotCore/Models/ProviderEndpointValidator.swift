import Foundation

public struct ProviderEndpointValidator: Sendable {
    public init() {}

    public func validationMessage(for rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            return "Invalid Base URL format"
        }

        let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if scheme != "https", !(isLocal && scheme == "http") {
            return "Remote services must use HTTPS"
        }
        return nil
    }
}
