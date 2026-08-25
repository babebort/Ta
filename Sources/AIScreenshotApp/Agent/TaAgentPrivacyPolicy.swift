import Foundation
import TaAgentContracts

struct TaAgentPrivacyPolicy: Equatable, Sendable {
    static let taBundleIdentifier = "com.kangarooking.AIScreenshot"

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
        let enabled = defaults.object(forKey: "agentAccessEnabled") == nil
            ? true
            : defaults.bool(forKey: "agentAccessEnabled")
        let captureAllowed = defaults.object(forKey: "agentAutomaticCaptureAllowed") == nil
            ? true
            : defaults.bool(forKey: "agentAutomaticCaptureAllowed")
        let cloudRaw = defaults.string(forKey: "agentCloudPolicy") ?? AgentCloudPolicy.auto.rawValue
        let denylist = defaults.string(forKey: "agentPrivacyDenylist") ?? ""
        let blocked = Set(denylist
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        let allowTa = defaults.object(forKey: "agentAllowCaptureTa") == nil
            ? true
            : defaults.bool(forKey: "agentAllowCaptureTa")
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
                message: "拓的 Agent 调用已关闭。",
                hint: "打开拓 → 设置 → Agent 与自动化后启用。",
                retryable: false
            )
        }
        guard automaticCaptureAllowed else {
            return AgentErrorPayload(
                code: .targetBlockedByPrivacyPolicy,
                message: "Agent 自动截图已关闭。",
                hint: "可在拓的 Agent 与自动化设置中启用。",
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
                message: "目标 App 已被 Agent 截图隐私策略阻止。",
                hint: "如确有需要，请在拓的隐私 App 黑名单中调整。",
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
                message: "当前请求禁止把图片或文字发送到云端模型。",
                hint: "改用本地能力，或在明确获得用户许可后设置 cloud=allow。",
                retryable: false
            )
        }
        return nil
    }
}
