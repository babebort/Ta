import Darwin
import Foundation
import TaAgentContracts

public enum TaBridgeClientError: Error, Equatable, LocalizedError, Sendable {
    case socketPathTooLong(String)
    case socketFailure(operation: String, code: Int32)
    case connectionClosed

    public var errorDescription: String? {
        switch self {
        case .socketPathTooLong(let path):
            "Unix Socket 路径过长：\(path)"
        case .socketFailure(let operation, let code):
            "Bridge \(operation) 失败（errno \(code)：\(String(cString: strerror(code)))）"
        case .connectionClosed:
            "Bridge 在返回完整响应前关闭了连接。"
        }
    }
}

public enum TaUnixSocketIO {
    public static func makeAddress(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else { throw TaBridgeClientError.socketPathTooLong(path) }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            bytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        return address
    }

    public static func readPayload(fileDescriptor: Int32) throws -> Data {
        let header = try readExactly(fileDescriptor: fileDescriptor, count: AgentFrameCodec.headerBytes)
        let length = try AgentFrameCodec.payloadLength(from: header)
        return try readExactly(fileDescriptor: fileDescriptor, count: length)
    }

    public static func writePayload(_ payload: Data, fileDescriptor: Int32) throws {
        let frame = try AgentFrameCodec.frame(payload)
        try writeAll(frame, fileDescriptor: fileDescriptor)
    }

    private static func readExactly(fileDescriptor: Int32, count: Int) throws -> Data {
        if count == 0 { return Data() }
        var result = Data(count: count)
        var offset = 0
        while offset < count {
            let received = result.withUnsafeMutableBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.recv(fileDescriptor, base.advanced(by: offset), count - offset, 0)
            }
            if received > 0 {
                offset += received
            } else if received == 0 {
                throw TaBridgeClientError.connectionClosed
            } else if errno != EINTR {
                throw TaBridgeClientError.socketFailure(operation: "read", code: errno)
            }
        }
        return result
    }

    private static func writeAll(_ data: Data, fileDescriptor: Int32) throws {
        var offset = 0
        while offset < data.count {
            let sent = data.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.send(fileDescriptor, base.advanced(by: offset), data.count - offset, MSG_NOSIGNAL)
            }
            if sent > 0 {
                offset += sent
            } else if sent == 0 {
                throw TaBridgeClientError.connectionClosed
            } else if errno != EINTR {
                throw TaBridgeClientError.socketFailure(operation: "write", code: errno)
            }
        }
    }
}

public struct TaBridgeClient: Sendable {
    public let socketURL: URL
    public let timeout: TimeInterval

    public init(socketURL: URL, timeout: TimeInterval = 5) {
        self.socketURL = socketURL
        self.timeout = timeout
    }

    public func send(_ request: AgentRequestEnvelope) async throws -> AgentResponseEnvelope {
        let operation = TaBridgeRequestOperation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        continuation.resume(returning: try sendSynchronously(request, operation: operation))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            operation.cancel()
        }
    }

    private func sendSynchronously(
        _ request: AgentRequestEnvelope,
        operation: TaBridgeRequestOperation
    ) throws -> AgentResponseEnvelope {
        let descriptor = try connectWithSingleRetry()
        defer { Darwin.close(descriptor) }
        try operation.register(descriptor)
        defer { operation.unregister(descriptor) }

        do {
            let requestData = try AgentJSONCoding.encoder().encode(request)
            try TaUnixSocketIO.writePayload(requestData, fileDescriptor: descriptor)
            let responseData = try TaUnixSocketIO.readPayload(fileDescriptor: descriptor)
            try operation.checkCancellation()
            return try AgentJSONCoding.decoder().decode(AgentResponseEnvelope.self, from: responseData)
        } catch {
            try operation.checkCancellation()
            throw error
        }
    }

    private func connectWithSingleRetry() throws -> Int32 {
        var lastError = Int32(0)
        for attempt in 0...1 {
            let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                throw TaBridgeClientError.socketFailure(operation: "socket", code: errno)
            }
            configureTimeout(descriptor)

            var address = try TaUnixSocketIO.makeAddress(path: socketURL.path)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            if result == 0 { return descriptor }

            lastError = errno
            Darwin.close(descriptor)
            let retryable = lastError == ENOENT || lastError == ECONNREFUSED
            if attempt == 0, retryable {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            break
        }
        throw TaBridgeClientError.socketFailure(operation: "connect", code: lastError)
    }

    private func configureTimeout(_ descriptor: Int32) {
        guard timeout > 0 else { return }
        let seconds = floor(timeout)
        var value = timeval(
            tv_sec: Int(seconds),
            tv_usec: Int32((timeout - seconds) * 1_000_000)
        )
        withUnsafePointer(to: &value) { pointer in
            _ = Darwin.setsockopt(
                descriptor, SOL_SOCKET, SO_RCVTIMEO,
                pointer, socklen_t(MemoryLayout<timeval>.size)
            )
            _ = Darwin.setsockopt(
                descriptor, SOL_SOCKET, SO_SNDTIMEO,
                pointer, socklen_t(MemoryLayout<timeval>.size)
            )
        }
    }
}

private final class TaBridgeRequestOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var cancelled = false

    func register(_ descriptor: Int32) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.descriptor = descriptor
    }

    func unregister(_ descriptor: Int32) {
        lock.lock()
        if self.descriptor == descriptor { self.descriptor = -1 }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let descriptor = self.descriptor
        lock.unlock()
        if descriptor >= 0 {
            _ = Darwin.shutdown(descriptor, SHUT_RDWR)
        }
    }

    func checkCancellation() throws {
        lock.lock()
        let cancelled = self.cancelled
        lock.unlock()
        if cancelled { throw CancellationError() }
    }
}
