import Foundation
import TaAgentContracts

actor TaAgentRequestRouter {
    typealias Handler = @Sendable (AgentRequestEnvelope) async -> AgentResponseEnvelope

    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func route(_ request: AgentRequestEnvelope) async -> AgentResponseEnvelope {
        do {
            try request.validateProtocolVersion()
        } catch AgentProtocolError.unsupportedVersion(let received, let supported) {
            return .failure(
                requestID: request.requestID,
                error: AgentErrorPayload(
                    code: .protocolVersionMismatch,
                    message: "Bridge protocol version mismatch: received \(received), currently supported \(supported).",
                    hint: "Please upgrade the Ta app or the calling client.",
                    retryable: false
                )
            )
        } catch {
            return .failure(
                requestID: request.requestID,
                error: AgentErrorPayload(code: .invalidRequest, message: "The request protocol is invalid.", retryable: false)
            )
        }

        if request.method == .systemHandshake {
            return .success(
                requestID: request.requestID,
                data: .object([
                    "protocolVersion": .integer(Int64(AgentProtocol.currentVersion)),
                    "server": .string("Ta")
                ])
            )
        }
        return await handler(request)
    }
}

