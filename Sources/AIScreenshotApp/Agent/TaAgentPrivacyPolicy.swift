import Foundation
import TaAgentContracts

enum TaAgentPreferenceKey {
    static let accessEnabled = "agentAccessEnabled"
    static let automaticCaptureAllowed = "agentAutomaticCaptureAllowed"
    static let cloudPolicy = "agentCloudPolicy"
    static let privacyDenylist = "agentPrivacyDenylist"
    static let allowCaptureTa = "agentAllowCaptureTa"
}

struct TaAgentPrivacyPolicy: Equatable, Sendable {
    static let taBundleIdentifier = PersistentConfigurationIdentity.bundleIdentifier

    let isEnabled: Bool
    let automaticCaptureAllowed: Bool
    let cloudPolicy: AgentCloudPolicy
    let blockedBundleIdentifiers: Set<String>
    let allowCaptureTa: Bool

    init(
        isEnabled: Bool,
        automaticCaptureAllowed: Bool,
        cloudPolicy: AgentCloudPolicy,
        blockedBundleIdentifiers: Set<String>,
        allowCaptureTa: Bool
    ) {
        self.isEnabled = isEnabled
        self.automaticCaptureAllowed = automaticCaptureAllowed
        self.cloudPolicy = cloudPolicy
        self.blockedBundleIdentifiers = Set(blockedBundleIdentifiers.map { $0.lowercased() })
        self.allowCaptureTa = allowCaptureTa
    }

    static func load(defaults: UserDefaults = .standard) -> TaAgentPrivacyPolicy {
        let enabled = defaults.object(forKey: TaAgentPreferenceKey.accessEnabled) == nil
            ? true
            : defaults.bool(forKey: TaAgentPreferenceKey.accessEnabled)
        let captureAllowed = defaults.object(forKey: TaAgentPreferenceKey.automaticCaptureAllowed) == nil
            ? true
            : defaults.bool(forKey: TaAgentPreferenceKey.automaticCaptureAllowed)
        let cloudRaw = defaults.string(forKey: TaAgentPreferenceKey.cloudPolicy) ?? AgentCloudPolicy.auto.rawValue
        let denylist = defaults.string(forKey: TaAgentPreferenceKey.privacyDenylist) ?? ""
        let blocked = Set(denylist
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        let allowTa = defaults.object(forKey: TaAgentPreferenceKey.allowCaptureTa) == nil
            ? true
            : defaults.bool(forKey: TaAgentPreferenceKey.allowCaptureTa)
        return TaAgentPrivacyPolicy(
            isEnabled: enabled,
            automaticCaptureAllowed: captureAllowed,
            cloudPolicy: AgentCloudPolicy(rawValue: cloudRaw) ?? .auto,
            blockedBundleIdentifiers: blocked,
            allowCaptureTa: allowTa
        )
    }

    func captureError(
        for target: TaAgentResolvedTarget,
        visibleBundleIdentifiers: Set<String> = []
    ) -> AgentErrorPayload? {
        guard isEnabled else {
            return AgentErrorPayload(
                code: .targetBlockedByPrivacyPolicy,
                message: "Ta's Agent calls are disabled.",
                hint: "Open Ta → Settings → Agent & Automation to enable it.",
                retryable: false
            )
        }
        guard automaticCaptureAllowed else {
            return AgentErrorPayload(
                code: .targetBlockedByPrivacyPolicy,
                message: "Agent automatic screenshots are disabled.",
                hint: "You can enable it in Ta's Agent & Automation settings.",
                retryable: false
            )
        }
        let visible = Set(visibleBundleIdentifiers.map { $0.lowercased() })
        let targetBundle = target.bundleIdentifier?.lowercased()
        let containsBlockedApp = !visible.isDisjoint(with: blockedBundleIdentifiers)
        let containsTa = visible.contains(Self.taBundleIdentifier.lowercased())
            || targetBundle == Self.taBundleIdentifier.lowercased()
        if targetBundle.map(blockedBundleIdentifiers.contains) == true
            || containsBlockedApp
            || (!allowCaptureTa && containsTa) {
            return AgentErrorPayload(
                code: .targetBlockedByPrivacyPolicy,
                message: "The target app is blocked by the Agent screenshot privacy policy.",
                hint: "If needed, adjust it in Ta's Privacy app blocklist.",
                retryable: false
            )
        }
        return nil
    }

    func allowsWindowMetadata(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier = bundleIdentifier?.lowercased() else { return true }
        if blockedBundleIdentifiers.contains(bundleIdentifier) { return false }
        if !allowCaptureTa && bundleIdentifier == Self.taBundleIdentifier.lowercased() { return false }
        return true
    }

    func cloudError(requested: AgentCloudPolicy?) -> AgentErrorPayload? {
        let effective = requested ?? cloudPolicy
        guard effective != .deny else {
            return AgentErrorPayload(
                code: .cloudUploadNotAllowed,
                message: "This request is not allowed to send images or text to a cloud model.",
                hint: "Use a local capability instead, or set cloud=allow after explicit user consent.",
                retryable: false
            )
        }
        return nil
    }
}
