import Darwin
import Foundation
import TaAgentClient
import TaAgentContracts

enum TaAgentBridgeConnection {
    static func handle(
        fileDescriptor: Int32,
        expectedUserID: uid_t,
        router: TaAgentRequestRouter
    ) async {
        defer { Darwin.close(fileDescriptor) }

        var peerUserID = uid_t(0)
        var peerGroupID = gid_t(0)
        guard getpeereid(fileDescriptor, &peerUserID, &peerGroupID) == 0,
              peerUserID == expectedUserID else {
            return
        }

        do {
            let requestData = try TaUnixSocketIO.readPayload(fileDescriptor: fileDescriptor)
            let request = try AgentJSONCoding.decoder().decode(AgentRequestEnvelope.self, from: requestData)
            let response = await router.route(request)
            let responseData = try AgentJSONCoding.encoder().encode(response)
            try TaUnixSocketIO.writePayload(responseData, fileDescriptor: fileDescriptor)
        } catch let decodingError as DecodingError {
            let response = AgentResponseEnvelope.failure(
                requestID: "unknown",
                error: AgentErrorPayload(
                    code: .invalidRequest,
                    message: "无法解析 Bridge 请求：\(decodingError)",
                    retryable: false
                )
            )
            if let data = try? AgentJSONCoding.encoder().encode(response) {
                try? TaUnixSocketIO.writePayload(data, fileDescriptor: fileDescriptor)
            }
        } catch {
            return
        }
    }
}

