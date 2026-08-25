import Darwin
import Foundation
import TaAgentClient

enum TaAgentBridgeServerError: Error, Equatable {
    case alreadyRunning
    case pathOccupied(String)
    case socketFailure(operation: String, code: Int32)
}

final class TaAgentBridgeServer: @unchecked Sendable {
    let socketURL: URL

    private let router: TaAgentRequestRouter
    private let lock = NSLock()
    private let acceptQueue = DispatchQueue(label: "com.ta.agent-bridge.accept", qos: .userInitiated)
    private let connectionQueue = DispatchQueue(
        label: "com.ta.agent-bridge.connections",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private var listeningDescriptor: Int32 = -1

    init(socketURL: URL, router: TaAgentRequestRouter) {
        self.socketURL = socketURL
        self.router = router
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard listeningDescriptor < 0 else { throw TaAgentBridgeServerError.alreadyRunning }

        let fileManager = FileManager.default
        let parent = socketURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        _ = parent.path.withCString { Darwin.chmod($0, S_IRWXU) }

        if fileManager.fileExists(atPath: socketURL.path) {
            var info = stat()
            let status = socketURL.path.withCString { Darwin.lstat($0, &info) }
            guard status == 0, (info.st_mode & S_IFMT) == S_IFSOCK else {
                throw TaAgentBridgeServerError.pathOccupied(socketURL.path)
            }
            try fileManager.removeItem(at: socketURL)
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw TaAgentBridgeServerError.socketFailure(operation: "socket", code: errno)
        }

        do {
            var address = try TaUnixSocketIO.makeAddress(path: socketURL.path)
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bindResult == 0 else {
                throw TaAgentBridgeServerError.socketFailure(operation: "bind", code: errno)
            }
            guard socketURL.path.withCString({ Darwin.chmod($0, S_IRUSR | S_IWUSR) }) == 0 else {
                throw TaAgentBridgeServerError.socketFailure(operation: "chmod", code: errno)
            }
            guard Darwin.listen(descriptor, SOMAXCONN) == 0 else {
                throw TaAgentBridgeServerError.socketFailure(operation: "listen", code: errno)
            }
        } catch {
            Darwin.close(descriptor)
            try? fileManager.removeItem(at: socketURL)
            throw error
        }

        listeningDescriptor = descriptor
        let router = self.router
        let expectedUserID = Darwin.geteuid()
        acceptQueue.async { [weak self] in
            self?.acceptConnections(
                listeningDescriptor: descriptor,
                expectedUserID: expectedUserID,
                router: router
            )
        }
    }

    func stop() {
        lock.lock()
        let descriptor = listeningDescriptor
        listeningDescriptor = -1
        lock.unlock()

        if descriptor >= 0 {
            _ = Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
        try? FileManager.default.removeItem(at: socketURL)
    }

    deinit {
        stop()
    }

    private func acceptConnections(
        listeningDescriptor: Int32,
        expectedUserID: uid_t,
        router: TaAgentRequestRouter
    ) {
        while true {
            let clientDescriptor = Darwin.accept(listeningDescriptor, nil, nil)
            if clientDescriptor >= 0 {
                connectionQueue.async {
                    let semaphore = DispatchSemaphore(value: 0)
                    Task {
                        await TaAgentBridgeConnection.handle(
                            fileDescriptor: clientDescriptor,
                            expectedUserID: expectedUserID,
                            router: router
                        )
                        semaphore.signal()
                    }
                    semaphore.wait()
                }
                continue
            }
            if errno == EINTR { continue }
            break
        }
    }
}
