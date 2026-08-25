import Foundation
import Testing
@testable import TaCLI
import TaAgentContracts

@Suite("ta CLI parser")
struct CLIParserTests {
    @Test("parses status with global JSON output")
    func status() throws {
        let invocation = try CLIParser.parse(["status", "--json"])

        #expect(invocation.action == .request(.systemStatus, [:]))
        #expect(invocation.outputFormat == .json)
        #expect(invocation.timeout == 10)
    }

    @Test("parses a region capture and requested output path")
    func regionCapture() throws {
        let invocation = try CLIParser.parse([
            "capture", "region",
            "--display", "2",
            "--x", "100", "--y", "120",
            "--width", "800", "--height", "600",
            "--output", "/tmp/ta-region.png",
            "--cloud", "deny"
        ])

        #expect(invocation.action == .request(.captureRegion, [
            "displayId": .integer(2),
            "x": .number(100), "y": .number(120),
            "width": .number(800), "height": .number(600),
            "cloud": .string("deny")
        ]))
        #expect(invocation.outputPath == "/tmp/ta-region.png")
    }

    @Test("image input paths use inputPath and never API key arguments")
    func ocrPath() throws {
        let invocation = try CLIParser.parse(["ocr", "./shot.png", "--json"])
        let expectedPath = URL(fileURLWithPath: "./shot.png").standardizedFileURL.path

        #expect(invocation.action == .request(.recognizeOCR, ["inputPath": .string(expectedPath)]))
        #expect(!CLIParser.usage.localizedCaseInsensitiveContains("api-key"))
    }

    @Test("missing required window ID is actionable")
    func missingWindowID() {
        #expect(throws: CLIParseError.self) {
            _ = try CLIParser.parse(["capture", "window"])
        }
    }

    @Test("save forwards the required destination path")
    func savePath() throws {
        let invocation = try CLIParser.parse(["save", "last", "--output", "/tmp/ta-save.png"])

        #expect(invocation.action == .request(.deliverSave, [
            "path": .string("/tmp/ta-save.png")
        ]))
        #expect(invocation.outputPath == "/tmp/ta-save.png")
    }

    @Test("save rejects a missing destination")
    func saveRequiresOutput() {
        #expect(throws: CLIParseError.self) {
            _ = try CLIParser.parse(["save", "last"])
        }
    }
}
