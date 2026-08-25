import Foundation
import Testing
@testable import AIScreenshotApp
import TaAgentClient
import TaAgentContracts

@Suite("Ta Agent local bridge")
struct TaAgentBridgeServerTests {
    @Test("handshake succeeds over a local Unix socket")
    func handshake() async throws {
        let fixture = try makeFixture()
        defer { fixture.server.stop() }

        let response = try await fixture.client.send(
            AgentRequestEnvelope(
                requestID: "handshake-1",
                method: .systemHandshake,
                client: AgentClientInfo(name: "test", version: "1")
            )
        )

        #expect(response.ok)
        #expect(response.data == .object([
            "protocolVersion": .integer(1),
            "server": .string("Ta")
        ]))
    }

    @Test("unsupported protocol versions return a structured error")
    func rejectsFutureProtocol() async throws {
        let fixture = try makeFixture()
        defer { fixture.server.stop() }

        let response = try await fixture.client.send(
            AgentRequestEnvelope(
                protocolVersion: 99,
                requestID: "future-1",
                method: .systemStatus,
                client: AgentClientInfo(name: "test", version: "1")
            )
        )

        #expect(!response.ok)
        #expect(response.error?.code == .protocolVersionMismatch)
        #expect(response.requestID == "future-1")
    }

    @Test("server accepts concurrent independent requests")
    func concurrentRequests() async throws {
        let fixture = try makeFixture()
        defer { fixture.server.stop() }

        let responses = try await withThrowingTaskGroup(of: AgentResponseEnvelope.self) { group in
            for index in 0..<8 {
                group.addTask {
                    try await fixture.client.send(
                        AgentRequestEnvelope(
                            requestID: "request-\(index)",
                            method: .systemStatus,
                            client: AgentClientInfo(name: "test", version: "1")
                        )
                    )
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(responses.count == 8)
        #expect(responses.allSatisfy { $0.ok })
        #expect(Set(responses.map(\.requestID)).count == 8)
    }

    @Test("client cancellation interrupts a pending response")
    func cancellation() async throws {
        let fixture = try makeFixture { request in
            try? await Task.sleep(for: .seconds(5))
            return .success(requestID: request.requestID)
        }
        defer { fixture.server.stop() }

        let task = Task {
            try await fixture.client.send(
                AgentRequestEnvelope(
                    requestID: "cancel-1",
                    method: .systemStatus,
                    client: AgentClientInfo(name: "test", version: "1")
                )
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Cancelled Bridge request unexpectedly succeeded")
        } catch is CancellationError {
            // Expected: cancelling the caller shuts down the pending socket read.
        }
    }

    @Test("socket is private to the current user")
    func socketPermissions() throws {
        let fixture = try makeFixture()
        defer { fixture.server.stop() }

        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.server.socketURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o600)
    }

    private func makeFixture(
        handler: @escaping TaAgentRequestRouter.Handler = { request in
            .success(
                requestID: request.requestID,
                data: .object(["method": .string(request.method.rawValue)])
            )
        }
    ) throws -> (server: TaAgentBridgeServer, client: TaBridgeClient) {
        let name = "ta-agent-\(UUID().uuidString.prefix(8)).sock"
        let socketURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let router = TaAgentRequestRouter(handler: handler)
        let server = TaAgentBridgeServer(socketURL: socketURL, router: router)
        try server.start()
        return (server, TaBridgeClient(socketURL: socketURL, timeout: 2))
    }
}
