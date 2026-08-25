import Foundation
import Testing
@testable import AIScreenshotApp
import TaAgentContracts

@Suite("Ta Agent privacy settings and audit")
struct AgentSettingsTests {
    @Test("privacy defaults allow silent local automation without weakening cloud policy")
    func privacyDefaults() throws {
        let suite = "ta-agent-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let policy = TaAgentPrivacyPolicy.load(defaults: defaults)

        #expect(policy.isEnabled)
        #expect(policy.automaticCaptureAllowed)
        #expect(policy.cloudPolicy == .auto)
        #expect(policy.blockedBundleIdentifiers.isEmpty)
        #expect(policy.allowCaptureTa)
    }

    @Test("privacy settings persist and normalize blocked bundle identifiers")
    func privacyPersistence() throws {
        let suite = "ta-agent-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: TaAgentPreferenceKey.accessEnabled)
        defaults.set(false, forKey: TaAgentPreferenceKey.automaticCaptureAllowed)
        defaults.set(AgentCloudPolicy.deny.rawValue, forKey: TaAgentPreferenceKey.cloudPolicy)
        defaults.set(" com.apple.Safari\nCOM.1PASSWORD.1PASSWORD ", forKey: TaAgentPreferenceKey.privacyDenylist)
        defaults.set(false, forKey: TaAgentPreferenceKey.allowCaptureTa)

        let policy = TaAgentPrivacyPolicy.load(defaults: defaults)

        #expect(!policy.isEnabled)
        #expect(!policy.automaticCaptureAllowed)
        #expect(policy.cloudPolicy == .deny)
        #expect(policy.blockedBundleIdentifiers == ["com.apple.safari", "com.1password.1password"])
        #expect(!policy.allowCaptureTa)
    }

    @Test("audit entries never persist request parameters or response content")
    func auditRedaction() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("audit.json")
        let log = TaAgentAuditLog(fileURL: file, maximumEntries: 20)
        let request = AgentRequestEnvelope(
            requestID: "request-safe-id",
            method: .recognizeOCR,
            params: [
                "apiKey": .string("sk-super-secret"),
                "text": .string("private OCR paragraph")
            ],
            client: AgentClientInfo(name: "test-agent", version: "1.2.3")
        )
        let response = AgentResponseEnvelope.success(
            requestID: request.requestID,
            data: .object(["text": .string("private OCR paragraph")]),
            meta: AgentResponseMetadata(durationMs: 37, cloudUploaded: false)
        )

        try await log.record(request: request, response: response, occurredAt: Date(timeIntervalSince1970: 1_787_684_400))

        let raw = try String(contentsOf: file, encoding: .utf8)
        let recent = try await log.recent(limit: 10)
        let entry = try #require(recent.first)
        #expect(!raw.contains("sk-super-secret"))
        #expect(!raw.contains("private OCR paragraph"))
        #expect(!raw.contains("request-safe-id"))
        #expect(!raw.localizedCaseInsensitiveContains("apiKey"))
        #expect(entry.method == .recognizeOCR)
        #expect(entry.clientName == "test-agent")
        #expect(entry.durationMs == 37)
        #expect(!entry.cloudUploaded)
        #expect(entry.succeeded)
    }

    @Test("audit log stays bounded and can be cleared")
    func auditRetentionAndClear() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = TaAgentAuditLog(fileURL: root.appendingPathComponent("audit.json"), maximumEntries: 2)

        for index in 0..<3 {
            let request = AgentRequestEnvelope(
                requestID: "request-\(index)",
                method: .systemStatus,
                client: AgentClientInfo(name: "agent", version: "1")
            )
            try await log.record(
                request: request,
                response: .success(requestID: request.requestID),
                occurredAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let recent = try await log.recent(limit: 10)
        #expect(recent.count == 2)
        #expect(recent.map(\.occurredAt) == [
            Date(timeIntervalSince1970: 2),
            Date(timeIntervalSince1970: 1)
        ])
        try await log.clear()
        #expect(try await log.recent(limit: 10).isEmpty)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ta-agent-settings-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
