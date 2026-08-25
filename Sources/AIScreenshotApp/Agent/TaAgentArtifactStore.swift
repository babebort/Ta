import CryptoKit
import Foundation
import TaAgentContracts

enum TaAgentArtifactStoreError: Error, Equatable {
    case unsafePathComponent(String)
}

actor TaAgentArtifactStore {
    static let defaultRetention: TimeInterval = 24 * 60 * 60

    let rootDirectory: URL
    let retention: TimeInterval

    init(
        rootDirectory: URL = TaAgentArtifactStore.defaultRootDirectory(),
        retention: TimeInterval = TaAgentArtifactStore.defaultRetention
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.retention = retention
    }

    func save(
        data: Data,
        requestID: String,
        filename: String,
        mimeType: String,
        width: Int?,
        height: Int?,
        now: Date = Date()
    ) throws -> AgentArtifact {
        try Self.validatePathComponent(requestID)
        try Self.validatePathComponent(filename)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let requestDirectory = rootDirectory.appendingPathComponent(requestID, isDirectory: true)
        try fileManager.createDirectory(at: requestDirectory, withIntermediateDirectories: true)

        let outputURL = requestDirectory.appendingPathComponent(filename, isDirectory: false)
        guard outputURL.deletingLastPathComponent().standardizedFileURL == requestDirectory.standardizedFileURL else {
            throw TaAgentArtifactStoreError.unsafePathComponent(filename)
        }

        try data.write(to: outputURL, options: [.atomic])
        try fileManager.setAttributes([.modificationDate: now], ofItemAtPath: requestDirectory.path)

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return AgentArtifact(
            id: "artifact_\(UUID().uuidString.lowercased())",
            path: outputURL.path,
            mimeType: mimeType,
            width: width,
            height: height,
            bytes: data.count,
            sha256: digest,
            expiresAt: now.addingTimeInterval(retention)
        )
    }

    func cleanupExpired(now: Date = Date()) throws -> Int {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return 0 }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        let children = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        let cutoff = now.addingTimeInterval(-retention)
        var removed = 0

        for child in children {
            let values = try child.resourceValues(forKeys: keys)
            guard values.isDirectory == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt <= cutoff else { continue }
            try fileManager.removeItem(at: child)
            removed += 1
        }
        return removed
    }

    private static func validatePathComponent(_ value: String) throws {
        let pattern = "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
        guard value.range(of: pattern, options: .regularExpression) != nil,
              value != ".", value != ".." else {
            throw TaAgentArtifactStoreError.unsafePathComponent(value)
        }
    }

    private static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Ta", isDirectory: true)
            .appendingPathComponent("AgentRuns", isDirectory: true)
    }
}

