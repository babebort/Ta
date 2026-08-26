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

    @Test("transform human output includes history and artifact details")
    func transformHumanOutput() throws {
        let response = AgentResponseEnvelope.success(
            requestID: "transform-1",
            data: .object([
                "action": .string("apply"),
                "elementCount": .integer(3),
                "canUndo": .bool(true),
                "canRedo": .bool(false)
            ]),
            artifacts: [AgentArtifact(
                id: "artifact-1",
                path: "/tmp/transformed.png",
                mimeType: "image/png",
                width: 800,
                height: 600,
                bytes: 42,
                sha256: "abc",
                expiresAt: Date(timeIntervalSince1970: 60)
            )]
        )

        let rendered = try CLIOutput.render(response, format: .human)
        #expect(rendered.contains("elementCount: 3"))
        #expect(rendered.contains("canUndo: 是"))
        #expect(rendered.contains("transformed.png"))
        #expect(rendered.contains("800×600"))
    }

    @Test("runner loads recipe contents and removes local path before Bridge send")
    func runnerLoadsRecipe() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ta-cli-recipe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recipeURL = directory.appendingPathComponent("recipe.json")
        let recipe = #"{"version":1,"operations":[{"type":"crop","rect":{"x":0,"y":0,"width":10,"height":10}}]}"#
        try Data(recipe.utf8).write(to: recipeURL)

        let params = try CLIRunner.preparedParameters(
            method: .transformImage,
            params: [
                "action": .string("apply"),
                "recipePath": .string(recipeURL.path)
            ]
        )

        #expect(params["recipe"] == .string(recipe))
        #expect(params["recipePath"] == nil)
    }
}
