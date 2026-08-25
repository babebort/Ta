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
                    message: "Bridge 协议版本不兼容：收到 \(received)，当前支持 \(supported)。",
                    hint: "请升级拓 App 或调用端。",
                    retryable: false
                )
            )
        } catch {
            return .failure(
                requestID: request.requestID,
                error: AgentErrorPayload(code: .invalidRequest, message: "请求协议无效。", retryable: false)
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

