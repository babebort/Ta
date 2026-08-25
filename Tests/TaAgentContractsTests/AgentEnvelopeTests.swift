import Foundation
import Testing
@testable import TaAgentContracts

@Suite("Ta Agent bridge contracts")
struct AgentEnvelopeTests {
    @Test("request JSON round-trips without losing multiline values")
    func requestRoundTrip() throws {
        let request = AgentRequestEnvelope(
            requestID: "ta_request_1",
            method: .analyzeImage,
            params: [
                "prompt": .string("第一行\n第二行"),
                "cloud": .string("deny")
            ],
            client: AgentClientInfo(name: "ta-cli", version: "1.0.0")
        )

        let data = try AgentJSONCoding.encoder().encode(request)
        let decoded = try AgentJSONCoding.decoder().decode(AgentRequestEnvelope.self, from: data)

        #expect(decoded == request)
    }

    @Test("success response carries stable artifact metadata")
    func successResponseRoundTrip() throws {
        let expiresAt = Date(timeIntervalSince1970: 1_787_684_400)
        let artifact = AgentArtifact(
            id: "artifact_1",
            path: "/tmp/Ta Agent/capture.png",
            mimeType: "image/png",
            width: 1512,
            height: 982,
            bytes: 483_921,
            sha256: String(repeating: "a", count: 64),
            expiresAt: expiresAt
        )
        let response = AgentResponseEnvelope.success(
            requestID: "ta_request_1",
            data: .object(["target": .string("frontmost")]),
            artifacts: [artifact],
            meta: AgentResponseMetadata(durationMs: 286, cloudUploaded: false)
        )

        let data = try AgentJSONCoding.encoder().encode(response)
        let decoded = try AgentJSONCoding.decoder().decode(AgentResponseEnvelope.self, from: data)

        #expect(decoded == response)
        #expect(decoded.ok)
        #expect(decoded.artifacts.first?.width == 1512)
    }

    @Test("failure response has actionable structured error")
    func failureResponseRoundTrip() throws {
        let response = AgentResponseEnvelope.failure(
            requestID: "ta_request_2",
            error: AgentErrorPayload(
                code: .screenPermissionRequired,
                message: "拓尚未获得录屏权限。",
                hint: "打开拓 → 设置 → 权限。",
                retryable: false
            )
        )

        let data = try AgentJSONCoding.encoder().encode(response)
        let decoded = try AgentJSONCoding.decoder().decode(AgentResponseEnvelope.self, from: data)

        #expect(decoded == response)
        #expect(!decoded.ok)
        #expect(decoded.error?.code == .screenPermissionRequired)
        #expect(decoded.data == nil)
    }

    @Test("unsupported protocol versions fail before dispatch")
    func unsupportedProtocolVersion() throws {
        let request = AgentRequestEnvelope(
            protocolVersion: 99,
            requestID: "future",
            method: .systemStatus,
            client: AgentClientInfo(name: "test", version: "0")
        )

        #expect(throws: AgentProtocolError.unsupportedVersion(received: 99, supported: 1)) {
            try request.validateProtocolVersion()
        }
    }
}
