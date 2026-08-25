import Foundation
import Testing
@testable import TaAgentClient
import TaAgentContracts

@Suite("Ta Bridge client framing")
struct TaBridgeClientTests {
    @Test("length-prefixed frames preserve multiline JSON")
    func frameRoundTrip() throws {
        let request = AgentRequestEnvelope(
            requestID: "frame-1",
            method: .analyzeImage,
            params: ["prompt": .string("line one\nline two")],
            client: AgentClientInfo(name: "test", version: "1")
        )
        let payload = try AgentJSONCoding.encoder().encode(request)
        let frame = try AgentFrameCodec.frame(payload)

        let decodedPayload = try AgentFrameCodec.payload(from: frame)
        let decoded = try AgentJSONCoding.decoder().decode(AgentRequestEnvelope.self, from: decodedPayload)

        #expect(decoded == request)
    }

    @Test("truncated and oversized frames are rejected")
    func invalidFrames() throws {
        #expect(throws: AgentFrameError.truncatedHeader) {
            try AgentFrameCodec.payload(from: Data([0, 0, 0]))
        }

        let declaredLength = UInt32(12).bigEndian
        var frame = withUnsafeBytes(of: declaredLength) { Data($0) }
        frame.append(Data([1, 2]))
        #expect(throws: AgentFrameError.truncatedPayload(expected: 12, actual: 2)) {
            try AgentFrameCodec.payload(from: frame)
        }

        #expect(throws: AgentFrameError.frameTooLarge(AgentFrameCodec.maximumPayloadBytes + 1)) {
            try AgentFrameCodec.frame(Data(count: AgentFrameCodec.maximumPayloadBytes + 1))
        }
    }
}

