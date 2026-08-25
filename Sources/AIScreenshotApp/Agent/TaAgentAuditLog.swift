import CryptoKit
import Foundation
import TaAgentContracts

struct TaAgentAuditEntry: Codable, Equatable, Identifiable, Sendable {
    let requestID: String
    let occurredAt: Date
    let clientName: String
    let clientVersion: String
    let method: AgentMethod
    let succeeded: Bool
    let durationMs: Int
    let cloudUploaded: Bool
    let errorCode: AgentErrorCode?

    var id: String { "\(requestID)-\(occurredAt.timeIntervalSince1970)" }
}

actor TaAgentAuditLog {
    static let defaultMaximumEntries = 100

    let fileURL: URL
    let maximumEntries: Int

    init(
        fileURL: URL = TaAgentAuditLog.defaultFileURL(),
        maximumEntries: Int = TaAgentAuditLog.defaultMaximumEntries
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.maximumEntries = max(1, maximumEntries)
    }

    func record(
        request: AgentRequestEnvelope,
        response: AgentResponseEnvelope,
        occurredAt: Date = Date()
    ) throws {
        var entries = try readEntries()
        entries.append(TaAgentAuditEntry(
            requestID: Self.requestFingerprint(request.requestID),
            occurredAt: occurredAt,
            clientName: Self.sanitizedClientField(request.client.name),
            clientVersion: Self.sanitizedClientField(request.client.version),
            method: request.method,
            succeeded: response.ok,
            durationMs: max(0, response.meta?.durationMs ?? 0),
            cloudUploaded: response.meta?.cloudUploaded ?? false,
            errorCode: response.error?.code
        ))
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        try write(entries)
    }

    func recent(limit: Int = 20) throws -> [TaAgentAuditEntry] {
        guard limit > 0 else { return [] }
        return Array(try readEntries().suffix(limit).reversed())
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func readEntries() throws -> [TaAgentAuditEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try AgentJSONCoding.decoder().decode(
            [TaAgentAuditEntry].self,
            from: Data(contentsOf: fileURL)
        )
    }

    private func write(_ entries: [TaAgentAuditEntry]) throws {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try AgentJSONCoding.encoder().encode(entries).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private static func sanitizedClientField(_ value: String) -> String {
        String(value
            .unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .prefix(80))
    }

    private static func requestFingerprint(_ requestID: String) -> String {
        let digest = SHA256.hash(data: Data(requestID.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        return "sha256:\(digest)"
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Ta", isDirectory: true)
            .appendingPathComponent("Agent", isDirectory: true)
            .appendingPathComponent("audit-v1.json", isDirectory: false)
    }
}
