import Foundation
import Testing
@testable import TaCLI
import TaAgentContracts

@Suite("ta CLI output")
struct CLIGoldenOutputTests {
    @Test("JSON output is stable and contains no prose")
    func jsonGolden() throws {
        let response = AgentResponseEnvelope.success(
            requestID: "req-1",
            data: .object(["bridge": .string("ready")]),
            meta: AgentResponseMetadata(durationMs: 7, cloudUploaded: false)
        )

        #expect(try CLIOutput.render(response, format: .json) ==
            #"{"artifacts":[],"data":{"bridge":"ready"},"meta":{"cloudUploaded":false,"durationMs":7},"ok":true,"protocolVersion":1,"requestId":"req-1"}"#
        )
    }

    @Test("human errors include code, message, and hint")
    func humanError() throws {
        let response = AgentResponseEnvelope.failure(
            requestID: "req-2",
            error: AgentErrorPayload(
                code: .screenPermissionRequired,
                message: "拓尚未获得屏幕录制权限。",
                hint: "打开拓的权限设置。",
                retryable: false
            )
        )

        let rendered = try CLIOutput.render(response, format: .human)
        #expect(rendered.contains("SCREEN_PERMISSION_REQUIRED"))
        #expect(rendered.contains("拓尚未获得屏幕录制权限"))
        #expect(rendered.contains("打开拓的权限设置"))
        #expect(CLIExitCode.forResponse(response) == .permissionDenied)
    }
}
