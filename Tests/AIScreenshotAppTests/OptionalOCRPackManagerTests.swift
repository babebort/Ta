import AIScreenshotCore
import CryptoKit
import Foundation
import XCTest
@testable import AIScreenshotApp

final class OptionalOCRPackManagerTests: XCTestCase {
    func testLegacyPackKeepsUsingOneShotRecognition() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pack = try fixture.makePack(engine: .paddleOCR)
        let manager = fixture.manager()
        _ = try manager.installDirectory(pack, expectedEngine: .paddleOCR)

        let result = try await manager.recognize(image: try makeImage(width: 64, height: 32), engine: .paddleOCR)

        XCTAssertEqual(result.text, "one-shot")
        XCTAssertEqual(result.engine, .paddleOCR)
        try manager.remove(.paddleOCR)
    }

    func testWorkerReusesProcessAcrossRecognitionRequests() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pack = try fixture.makeWorkerPack()
        let manager = fixture.manager()
        _ = try manager.installDirectory(pack, expectedEngine: .paddleOCR)
        let image = try makeImage(width: 64, height: 32)

        let first = try await manager.recognize(image: image, engine: .paddleOCR)
        let second = try await manager.recognize(image: image, engine: .paddleOCR)

        XCTAssertEqual(first.text, "worker-1:64x32")
        XCTAssertEqual(second.text, "worker-2:64x32")
        try manager.remove(.paddleOCR)
    }

    func testWorkerReceivesProportionallyScaledLargeImage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pack = try fixture.makeWorkerPack()
        let manager = fixture.manager()
        _ = try manager.installDirectory(pack, expectedEngine: .paddleOCR)

        let result = try await manager.recognize(
            image: try makeImage(width: 3000, height: 1500),
            engine: .paddleOCR
        )

        XCTAssertEqual(result.text, "worker-1:2560x1280")
        try manager.remove(.paddleOCR)
    }

    func testInstallsValidatedDirectoryAndRemovesIt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pack = try fixture.makePack(engine: .paddleOCR)
        let manager = fixture.manager()

        let info = try manager.installDirectory(pack, expectedEngine: .paddleOCR)

        XCTAssertEqual(info.version, "1.0.0")
        XCTAssertTrue(manager.isInstalled(.paddleOCR))
        XCTAssertEqual(manager.installedInfo(.paddleOCR)?.architecture, "arm64")

        try manager.remove(.paddleOCR)
        XCTAssertFalse(manager.isInstalled(.paddleOCR))
    }

    func testRejectsWrongEngine() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pack = try fixture.makePack(engine: .rapidOCR)

        XCTAssertThrowsError(
            try fixture.manager().installDirectory(pack, expectedEngine: .paddleOCR)
        ) { error in
            guard case OptionalOCRPackError.wrongEngine = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsExecutableChecksumMismatch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pack = try fixture.makePack(engine: .paddleOCR, executableSHA256: String(repeating: "0", count: 64))

        XCTAssertThrowsError(
            try fixture.manager().installDirectory(pack, expectedEngine: .paddleOCR)
        ) { error in
            guard case OptionalOCRPackError.checksumMismatch = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsExecutableOutsidePack() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pack = try fixture.makePack(engine: .paddleOCR, executable: "../outside")

        XCTAssertThrowsError(
            try fixture.manager().installDirectory(pack, expectedEngine: .paddleOCR)
        ) { error in
            guard case OptionalOCRPackError.unsafeExecutablePath = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testOneClickInstallUsesLocalCatalogAndArchive() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pack = try fixture.makePack(engine: .paddleOCR)
        try fixture.makeCatalogArchive(pack: pack)
        let manager = fixture.manager()

        let availability = try await manager.availablePackage(for: .paddleOCR)
        XCTAssertTrue(availability.isLocal)
        XCTAssertEqual(availability.package.version, "1.0.0")

        let info = try await manager.installRecommended(for: .paddleOCR) { _ in }
        XCTAssertEqual(info.version, "1.0.0")
        XCTAssertTrue(manager.isInstalled(.paddleOCR))
    }

    func testOneClickInstallHandlesArchiveListingLargerThanPipeBuffer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pack = try fixture.makePack(engine: .paddleOCR)
        try fixture.addArchiveEntries(to: pack, count: 2_500)
        try fixture.makeCatalogArchive(pack: pack)
        let progress = ProgressRecorder()

        let info = try await fixture.manager().installRecommended(for: .paddleOCR) {
            progress.append($0)
        }

        XCTAssertEqual(info.version, "1.0.0")
        XCTAssertTrue(fixture.manager().isInstalled(.paddleOCR))
        let verificationFractions = progress.snapshot()
            .filter { $0.stage == .verifying }
            .compactMap(\.fraction)
        XCTAssertEqual(verificationFractions.first, 0)
        XCTAssertEqual(verificationFractions.last, 1)
        XCTAssertTrue(verificationFractions.contains { $0 > 0 && $0 < 1 })
    }

    func testCancellingInstallTerminatesRunningHealthCheck() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let pack = try fixture.makePack(engine: .paddleOCR, healthCheckDelaySeconds: 30)
        try fixture.makeCatalogArchive(pack: pack)
        let manager = fixture.manager()
        let installation = Task {
            try await manager.installRecommended(for: .paddleOCR) { _ in }
        }
        try await Task.sleep(for: .seconds(1))

        let cancellationStarted = Date()
        installation.cancel()

        do {
            _ = try await installation.value
            XCTFail("Cancelled installation unexpectedly completed")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(cancellationStarted), 3)
        }
    }

    func testRealReleasePackInstallsWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_REAL_PADDLE_PACK_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_REAL_PADDLE_PACK_TESTS=1 for the real release-pack integration test")
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bundle = repository.appendingPathComponent("artifacts/AI Screenshot.app", isDirectory: true)
        let catalog = repository.appendingPathComponent("artifacts/ocr-packs/catalog.json")
        guard FileManager.default.fileExists(atPath: catalog.path) else {
            throw XCTSkip("Real PaddleOCR release artifact is unavailable")
        }
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("real-paddle-pack-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        let manager = OptionalOCRPackManager(applicationSupportRoot: support, bundleURL: bundle)
        let progress = ProgressRecorder()
        let availability = try await manager.availablePackage(for: .paddleOCR)

        let info = try await manager.installRecommended(for: .paddleOCR) {
            progress.append($0)
        }

        XCTAssertEqual(info.version, availability.package.version)
        XCTAssertTrue(manager.isInstalled(.paddleOCR))
        XCTAssertEqual(
            progress.snapshot().last(where: { $0.stage == .verifying })?.fraction,
            1
        )
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [OCRPackInstallProgress] = []

    func append(_ progress: OCRPackInstallProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }

    func snapshot() -> [OCRPackInstallProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private struct Fixture {
    let root: URL
    let support: URL
    let bundle: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("optional-ocr-pack-tests-\(UUID().uuidString)", isDirectory: true)
        support = root.appendingPathComponent("support", isDirectory: true)
        bundle = root.appendingPathComponent("AI Screenshot.app", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    }

    func manager() -> OptionalOCRPackManager {
        OptionalOCRPackManager(applicationSupportRoot: support, bundleURL: bundle)
    }

    func makePack(
        engine: OCREnginePreference,
        executable: String = "bin/adapter",
        executableSHA256: String? = nil,
        healthCheckDelaySeconds: Int = 0
    ) throws -> URL {
        let pack = root.appendingPathComponent("source-\(UUID().uuidString)", isDirectory: true)
        let bin = pack.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let adapter = bin.appendingPathComponent("adapter")
        let script = """
        #!/bin/zsh
        if [[ "$1" == "--health-check" ]]; then
            sleep \(healthCheckDelaySeconds)
            print -r -- '{"ok":true,"engine":"\(engine.rawValue)","packVersion":"1.0.0","architecture":"arm64","offline":true}'
        else
            print -r -- '{"text":"one-shot","confidence":0.91}'
        fi
        """
        FileManager.default.createFile(atPath: adapter.path, contents: Data(script.utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adapter.path)
        let checksum = executableSHA256 ?? sha256(Data(script.utf8))
        let manifest = OCRPackManifest(
            engine: engine,
            version: "1.0.0",
            executable: executable,
            executableSHA256: checksum,
            architecture: "arm64",
            minimumMacOS: "14.0",
            healthCheckArguments: ["--health-check"]
        )
        let data = try JSONEncoder().encode(manifest)
        FileManager.default.createFile(
            atPath: pack.appendingPathComponent("manifest.json").path,
            contents: data
        )
        return pack
    }

    func makeWorkerPack() throws -> URL {
        let pack = root.appendingPathComponent("worker-source-\(UUID().uuidString)", isDirectory: true)
        let bin = pack.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let adapter = bin.appendingPathComponent("adapter")
        let script = #"""
        #!/usr/bin/python3
        import json
        import struct
        import sys

        if "--health-check" in sys.argv:
            print(json.dumps({"ok": True, "engine": "paddleOCR", "packVersion": "1.1.0", "architecture": "arm64", "offline": True}))
            raise SystemExit(0)
        if "--worker" not in sys.argv:
            print(json.dumps({"text": "one-shot", "confidence": 0.91}))
            raise SystemExit(0)

        print(json.dumps({"event": "ready", "ok": True}), flush=True)
        count = 0
        for line in sys.stdin:
            request = json.loads(line)
            if request.get("command") == "shutdown":
                print(json.dumps({"id": request.get("id"), "ok": True, "event": "stopping"}), flush=True)
                break
            count += 1
            with open(request["input"], "rb") as image:
                header = image.read(24)
            width, height = struct.unpack(">II", header[16:24])
            print(json.dumps({
                "id": request.get("id"),
                "ok": True,
                "text": f"worker-{count}:{width}x{height}",
                "confidence": 0.95,
            }), flush=True)
        """#
        FileManager.default.createFile(atPath: adapter.path, contents: Data(script.utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adapter.path)
        let manifest = OCRPackManifest(
            engine: .paddleOCR,
            version: "1.1.0",
            executable: "bin/adapter",
            executableSHA256: sha256(Data(script.utf8)),
            architecture: "arm64",
            minimumMacOS: "14.0",
            healthCheckArguments: ["--health-check"],
            workerArguments: ["--worker"]
        )
        FileManager.default.createFile(
            atPath: pack.appendingPathComponent("manifest.json").path,
            contents: try JSONEncoder().encode(manifest)
        )
        return pack
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func makeCatalogArchive(pack: URL) throws {
        let releases = root.appendingPathComponent("ocr-packs", isDirectory: true)
        try FileManager.default.createDirectory(at: releases, withIntermediateDirectories: true)
        let archive = releases.appendingPathComponent("PaddleOCR-Pack-arm64-1.0.0.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", pack.path, archive.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let archiveData = try Data(contentsOf: archive)
        let item = OCRPackCatalogPackage(
            engine: .paddleOCR,
            version: "1.0.0",
            architecture: "arm64",
            minimumMacOS: "14.0",
            downloadURL: archive.lastPathComponent,
            archiveSHA256: sha256(archiveData),
            archiveSize: Int64(archiveData.count)
        )
        let catalog = OCRPackCatalog(schemaVersion: 1, packages: [item])
        let data = try JSONEncoder().encode(catalog)
        FileManager.default.createFile(
            atPath: releases.appendingPathComponent("catalog.json").path,
            contents: data
        )
    }

    func addArchiveEntries(to pack: URL, count: Int) throws {
        let payload = pack.appendingPathComponent("large-listing-fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        for index in 0..<count {
            let name = String(format: "entry-%05d-with-a-long-regression-test-name.txt", index)
            FileManager.default.createFile(
                atPath: payload.appendingPathComponent(name).path,
                contents: Data()
            )
        }
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private func makeImage(width: Int, height: Int) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let image = context.makeImage() else {
        throw OptionalOCRPackError.invalidResponse
    }
    return image
}
