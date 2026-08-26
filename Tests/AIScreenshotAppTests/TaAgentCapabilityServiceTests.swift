import CoreGraphics
import Foundation
import Testing
import AIScreenshotCore
@testable import AIScreenshotApp
import TaAgentContracts

@Suite("Ta Agent capability service")
struct TaAgentCapabilityServiceTests {
    @Test("status and permissions never expose provider secrets")
    func statusAndPermissions() async throws {
        let fixture = try CapabilityFixture()

        let status = await fixture.service.handle(request(.systemStatus))
        let permissions = await fixture.service.handle(request(.systemPermissions))
        let encoded = try AgentJSONCoding.encoder().encode([status, permissions])
        let json = String(decoding: encoded, as: UTF8.self)

        #expect(status.ok)
        #expect(permissions.ok)
        #expect(json.contains("screenRecording"))
        #expect(!json.localizedCaseInsensitiveContains("apiKey"))
        #expect(!json.contains("test-secret"))
    }

    @Test("capture creates an artifact used by OCR, analyze, translate, and save")
    func completeCapabilityFlow() async throws {
        let fixture = try CapabilityFixture()

        let capture = await fixture.service.handle(request(.captureFrontmost))
        #expect(capture.ok)
        #expect(capture.meta?.cloudUploaded == false)
        let artifact = try #require(capture.artifacts.first)
        #expect(FileManager.default.fileExists(atPath: artifact.path))

        let ocr = await fixture.service.handle(request(.recognizeOCR))
        #expect(ocr.data?.objectValue?["text"] == .string("hello from OCR"))

        let analyze = await fixture.service.handle(request(.analyzeImage))
        #expect(analyze.data?.objectValue?["text"] == .string("image summary"))
        #expect(analyze.meta?.cloudUploaded == true)

        let translation = await fixture.service.handle(request(
            .translateText,
            params: ["text": .string("hello")]
        ))
        #expect(translation.data?.objectValue?["text"] == .string("你好"))

        let outputURL = fixture.root.appendingPathComponent("saved.png")
        let saved = await fixture.service.handle(request(
            .deliverSave,
            params: ["path": .string(outputURL.path)]
        ))
        #expect(saved.ok)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))
    }

    @Test("capabilities advertise local image transforms")
    func capabilitiesAdvertiseTransform() async throws {
        let fixture = try CapabilityFixture()

        let response = await fixture.service.handle(request(.systemCapabilities))

        #expect(response.ok)
        #expect(response.data?.objectValue?["methods"]?.arrayValue?.contains(.string("transform.image")) == true)
    }

    @Test("transform applies recipes and returns local artifacts with undo and redo")
    func transformApplyUndoRedo() async throws {
        let fixture = try CapabilityFixture()
        _ = await fixture.service.handle(request(.captureFrontmost))
        let recipe = AnnotationRecipe(version: 1, operations: [
            .rectangle(.init(id: "focus", rect: .init(x: 0, y: 0, width: 3, height: 2), lineWidth: 1))
        ])
        let recipeJSON = String(decoding: try AgentJSONCoding.encoder().encode(recipe), as: UTF8.self)

        let applied = await fixture.service.handle(request(
            .transformImage,
            params: ["action": .string("apply"), "recipe": .string(recipeJSON)]
        ))
        #expect(applied.ok)
        #expect(applied.meta?.cloudUploaded == false)
        #expect(applied.artifacts.first?.mimeType == "image/png")
        #expect(applied.data?.objectValue?["elementCount"] == .integer(1))
        #expect(applied.data?.objectValue?["canUndo"] == .bool(true))

        let undone = await fixture.service.handle(request(
            .transformImage,
            params: ["action": .string("undo")]
        ))
        #expect(undone.ok)
        #expect(undone.data?.objectValue?["elementCount"] == .integer(0))
        #expect(undone.data?.objectValue?["canRedo"] == .bool(true))

        let redone = await fixture.service.handle(request(
            .transformImage,
            params: ["action": .string("redo")]
        ))
        #expect(redone.ok)
        #expect(redone.data?.objectValue?["elementCount"] == .integer(1))
    }

    @Test("invalid transform recipes do not mutate the current edit session")
    func invalidTransformIsAtomic() async throws {
        let fixture = try CapabilityFixture()
        _ = await fixture.service.handle(request(.captureFrontmost))
        let valid = AnnotationRecipe(version: 1, operations: [
            .rectangle(.init(id: "focus", rect: .init(x: 0, y: 0, width: 3, height: 2), lineWidth: 1))
        ])
        let validJSON = String(decoding: try AgentJSONCoding.encoder().encode(valid), as: UTF8.self)
        _ = await fixture.service.handle(request(
            .transformImage,
            params: ["action": .string("apply"), "recipe": .string(validJSON)]
        ))

        let invalid = await fixture.service.handle(request(
            .transformImage,
            params: ["action": .string("apply"), "recipe": .string(#"{"version":1,"operations":[{"type":"eraser","targetIds":["missing"]}]}"#)]
        ))
        #expect(invalid.error?.code == .invalidRequest)

        let undone = await fixture.service.handle(request(
            .transformImage,
            params: ["action": .string("undo")]
        ))
        #expect(undone.ok)
        #expect(undone.data?.objectValue?["elementCount"] == .integer(0))
    }

    @Test("privacy denylist blocks capture before pixels are requested")
    func privacyDenylist() async throws {
        let fixture = try CapabilityFixture(
            privacyPolicy: TaAgentPrivacyPolicy(
                isEnabled: true,
                automaticCaptureAllowed: true,
                cloudPolicy: .allow,
                blockedBundleIdentifiers: ["com.apple.Safari"],
                allowCaptureTa: true
            )
        )

        let response = await fixture.service.handle(request(.captureFrontmost))

        #expect(response.error?.code == .targetBlockedByPrivacyPolicy)
        #expect(await fixture.backend.captureCount == 0)
    }

    @Test("display capture is blocked when it intersects a denylisted app")
    func displayCaptureHonorsDenylist() async throws {
        let fixture = try CapabilityFixture(
            privacyPolicy: TaAgentPrivacyPolicy(
                isEnabled: true,
                automaticCaptureAllowed: true,
                cloudPolicy: .allow,
                blockedBundleIdentifiers: ["com.apple.Safari"],
                allowCaptureTa: true
            )
        )

        let response = await fixture.service.handle(request(
            .captureDisplay,
            params: ["displayId": .integer(1)]
        ))

        #expect(response.error?.code == .targetBlockedByPrivacyPolicy)
        #expect(await fixture.backend.captureCount == 0)
    }

    @Test("cloud deny prevents model calls")
    func cloudDeny() async throws {
        let fixture = try CapabilityFixture()
        _ = await fixture.service.handle(request(.captureFrontmost))

        let response = await fixture.service.handle(request(
            .analyzeImage,
            params: ["cloud": .string("deny")]
        ))

        #expect(response.error?.code == .cloudUploadNotAllowed)
        #expect(await fixture.dependenciesProbe.analyzeCount == 0)
    }

    @Test("window list filters by either app name or bundle identifier")
    func windowListAppFilter() async throws {
        let fixture = try CapabilityFixture()

        let byName = await fixture.service.handle(request(
            .targetListWindows,
            params: ["app": .string("saf")]
        ))
        let byBundle = await fixture.service.handle(request(
            .targetListWindows,
            params: ["app": .string("com.apple.Safari")]
        ))
        let missing = await fixture.service.handle(request(
            .targetListWindows,
            params: ["app": .string("Finder")]
        ))

        #expect(byName.data?.objectValue?["windows"]?.arrayValue?.count == 1)
        #expect(byBundle.data?.objectValue?["windows"]?.arrayValue?.count == 1)
        #expect(missing.data?.objectValue?["windows"]?.arrayValue?.isEmpty == true)
    }

    @Test("privacy setting changes apply to the next request without restarting the Bridge")
    func privacyReloadsBetweenRequests() async throws {
        let box = MutablePrivacyPolicy(.testingAllowed)
        let fixture = try CapabilityFixture(
            privacyPolicy: nil,
            privacyPolicyProvider: { box.value }
        )

        #expect(await fixture.service.handle(request(.captureFrontmost)).ok)
        box.value = TaAgentPrivacyPolicy(
            isEnabled: false,
            automaticCaptureAllowed: false,
            cloudPolicy: .deny,
            blockedBundleIdentifiers: [],
            allowCaptureTa: false
        )
        let blocked = await fixture.service.handle(request(.captureFrontmost))

        #expect(blocked.error?.code == .targetBlockedByPrivacyPolicy)
        #expect(await fixture.backend.captureCount == 1)
    }

    private func request(
        _ method: AgentMethod,
        params: [String: JSONValue] = [:]
    ) -> AgentRequestEnvelope {
        AgentRequestEnvelope(
            requestID: "request-\(UUID().uuidString)",
            method: method,
            params: params,
            client: AgentClientInfo(name: "test", version: "1")
        )
    }
}

private struct CapabilityFixture {
    let root: URL
    let backend: CapabilityCaptureBackend
    let dependenciesProbe: CapabilityDependenciesProbe
    let service: TaAgentCapabilityService

    init(
        privacyPolicy: TaAgentPrivacyPolicy? = .testingAllowed,
        privacyPolicyProvider: @escaping @Sendable () -> TaAgentPrivacyPolicy = { .load() }
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ta-capability-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        backend = CapabilityCaptureBackend()
        dependenciesProbe = CapabilityDependenciesProbe()
        let captureService = TaAgentCaptureService(
            backend: backend,
            frontmostProcessID: { 420 }
        )
        let probe = dependenciesProbe
        let dependencies = TaAgentCapabilityDependencies(
            appVersion: { "1.0.0-test" },
            screenPermission: { true },
            accessibilityPermission: { true },
            ocrEngine: { .appleVision },
            visionConfigured: { true },
            translationConfigured: { true },
            recognizeOCR: { _, _, _ in
                OCRResult(
                    text: "hello from OCR",
                    contentType: .plainText,
                    confidence: 0.98
                )
            },
            analyzeImage: { _, _ in
                await probe.recordAnalyze()
                return "image summary"
            },
            translateText: { _ in "你好" },
            translateImage: { _ in "图片译文" },
            copyText: { _ in true },
            copyImage: { _ in true }
        )
        service = TaAgentCapabilityService(
            captureService: captureService,
            artifactStore: TaAgentArtifactStore(rootDirectory: root.appendingPathComponent("artifacts")),
            privacyPolicy: privacyPolicy,
            privacyPolicyProvider: privacyPolicyProvider,
            auditLog: nil,
            dependencies: dependencies
        )
    }
}

private final class MutablePrivacyPolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: TaAgentPrivacyPolicy

    init(_ value: TaAgentPrivacyPolicy) {
        stored = value
    }

    var value: TaAgentPrivacyPolicy {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private actor CapabilityDependenciesProbe {
    private(set) var analyzeCount = 0
    func recordAnalyze() { analyzeCount += 1 }
}

private actor CapabilityCaptureBackend: TaAgentCaptureBackend {
    private(set) var captureCount = 0

    func snapshot(frontmostProcessID: pid_t?) async throws -> TaAgentCaptureSnapshot {
        TaAgentCaptureSnapshot(
            displays: [
                TaAgentDisplayTarget(
                    id: 1,
                    frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                    pixelScale: 1,
                    isMain: true
                )
            ],
            windows: [
                TaAgentWindowTarget(
                    id: 42,
                    ownerProcessID: 420,
                    appName: "Safari",
                    bundleIdentifier: "com.apple.Safari",
                    title: "Example",
                    frame: CGRect(x: 20, y: 20, width: 400, height: 300),
                    zOrder: 0
                )
            ],
            frontmostProcessID: frontmostProcessID
        )
    }

    func capture(_ request: TaAgentResolvedCaptureRequest) async throws -> CGImage {
        captureCount += 1
        return Self.image
    }

    private static let image: CGImage = {
        let context = CGContext(
            data: nil,
            width: 4,
            height: 3,
            bitsPerComponent: 8,
            bytesPerRow: 16,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        return context.makeImage()!
    }()
}

private extension TaAgentPrivacyPolicy {
    static let testingAllowed = TaAgentPrivacyPolicy(
        isEnabled: true,
        automaticCaptureAllowed: true,
        cloudPolicy: .allow,
        blockedBundleIdentifiers: [],
        allowCaptureTa: true
    )
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }


    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}
