import CoreGraphics
import Testing
@testable import AIScreenshotApp

@Suite("Ta Agent silent capture")
struct TaAgentCaptureServiceTests {
    @Test("frontmost target is frozen before asynchronous discovery")
    func freezesFrontmostTarget() async throws {
        let backend = FakeAgentCaptureBackend(snapshot: .fixture)
        let service = TaAgentCaptureService(
            backend: backend,
            frontmostProcessID: { 420 }
        )

        let result = try await service.capture(.frontmost)
        let request = await backend.lastRequest

        #expect(result.target.windowID == 42)
        #expect(result.target.ownerProcessID == 420)
        #expect(request?.windowID == 42)
        #expect(request?.showsCursor == false)
    }

    @Test("window capture filters the exact requested window")
    func filtersRequestedWindow() async throws {
        let backend = FakeAgentCaptureBackend(snapshot: .fixture)
        let service = TaAgentCaptureService(backend: backend, frontmostProcessID: { 999 })

        let result = try await service.capture(.window(id: 77))
        let request = await backend.lastRequest

        #expect(result.target.windowID == 77)
        #expect(result.target.bundleIdentifier == "com.apple.finder")
        #expect(request?.windowID == 77)
    }

    @Test("region coordinates are clipped and converted to display-local space")
    func convertsRegionCoordinates() async throws {
        let backend = FakeAgentCaptureBackend(snapshot: .fixture)
        let service = TaAgentCaptureService(backend: backend, frontmostProcessID: { nil })

        _ = try await service.capture(.region(
            displayID: 1,
            globalRect: CGRect(x: 90, y: 180, width: 80, height: 70)
        ))
        let request = await backend.lastRequest

        #expect(request?.sourceRect == CGRect(x: 0, y: 0, width: 70, height: 50))
        #expect(request?.pixelScale == 2)
    }

    @Test("missing and disappearing targets use distinct errors")
    func reportsTargetFailures() async throws {
        let backend = FakeAgentCaptureBackend(snapshot: .fixture)
        let service = TaAgentCaptureService(backend: backend, frontmostProcessID: { 420 })

        await #expect(throws: TaAgentCaptureError.targetNotFound) {
            _ = try await service.capture(.window(id: 9999))
        }

        await backend.setCaptureError(.targetChanged)
        await #expect(throws: TaAgentCaptureError.targetChanged) {
            _ = try await service.capture(.frontmost)
        }
    }
}

private actor FakeAgentCaptureBackend: TaAgentCaptureBackend {
    private let snapshotValue: TaAgentCaptureSnapshot
    private var captureError: TaAgentCaptureError?
    private(set) var lastRequest: TaAgentResolvedCaptureRequest?

    init(snapshot: TaAgentCaptureSnapshot) {
        snapshotValue = snapshot
    }

    func snapshot(frontmostProcessID: pid_t?) async throws -> TaAgentCaptureSnapshot {
        TaAgentCaptureSnapshot(
            displays: snapshotValue.displays,
            windows: snapshotValue.windows,
            frontmostProcessID: frontmostProcessID
        )
    }

    func capture(_ request: TaAgentResolvedCaptureRequest) async throws -> CGImage {
        lastRequest = request
        if let captureError { throw captureError }
        return Self.image
    }

    func setCaptureError(_ error: TaAgentCaptureError?) {
        captureError = error
    }

    private static let image: CGImage = {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }()
}

private extension TaAgentCaptureSnapshot {
    static let fixture = TaAgentCaptureSnapshot(
        displays: [
            TaAgentDisplayTarget(
                id: 1,
                frame: CGRect(x: 100, y: 200, width: 800, height: 600),
                pixelScale: 2,
                isMain: true
            )
        ],
        windows: [
            TaAgentWindowTarget(
                id: 42,
                ownerProcessID: 420,
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                title: "Top",
                frame: CGRect(x: 120, y: 220, width: 600, height: 400),
                zOrder: 0
            ),
            TaAgentWindowTarget(
                id: 77,
                ownerProcessID: 777,
                appName: "Finder",
                bundleIdentifier: "com.apple.finder",
                title: "Files",
                frame: CGRect(x: 200, y: 260, width: 400, height: 300),
                zOrder: 1
            )
        ],
        frontmostProcessID: 420
    )
}
