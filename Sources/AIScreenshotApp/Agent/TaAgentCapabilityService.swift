import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import AIScreenshotCore
import TaAgentContracts

struct TaAgentCapabilityDependencies: Sendable {
    let appVersion: @Sendable () async -> String
    let screenPermission: @Sendable () async -> Bool
    let accessibilityPermission: @Sendable () async -> Bool
    let ocrEngine: @Sendable () async -> OCREnginePreference
    let visionConfigured: @Sendable () async -> Bool
    let translationConfigured: @Sendable () async -> Bool
    let recognizeOCR: @Sendable (CGImage, [String], Bool) async throws -> OCRResult
    let analyzeImage: @Sendable (CGImage, MultimodalTaskTemplate) async throws -> String
    let translateText: @Sendable (String) async throws -> String
    let translateImage: @Sendable (CGImage) async throws -> String
    let copyText: @Sendable (String) async -> Bool
    let copyImage: @Sendable (CGImage) async -> Bool

    static let live = TaAgentCapabilityDependencies(
        appVersion: {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        },
        screenPermission: { CGPreflightScreenCaptureAccess() },
        accessibilityPermission: { AXIsProcessTrusted() },
        ocrEngine: {
            let raw = UserDefaults.standard.string(forKey: "ocrEngine")
                ?? OCREnginePreference.appleVision.rawValue
            return OCREnginePreference(rawValue: raw) ?? .appleVision
        },
        visionConfigured: {
            await MainActor.run { MultimodalRecognitionService().isConfigured }
        },
        translationConfigured: { ScreenshotTranslationService().isConfigured },
        recognizeOCR: { image, languages, mergeWrappedLines in
            try await ConfiguredOCRService().recognize(
                image: image,
                languages: languages,
                mergeWrappedLines: mergeWrappedLines
            )
        },
        analyzeImage: { image, task in
            try await Task { @MainActor in
                try await MultimodalRecognitionService().recognize(image: image, task: task)
            }.value
        },
        translateText: { text in
            try await ScreenshotTranslationService().translateText(text)
        },
        translateImage: { image in
            try await ScreenshotTranslationService().translateWithVision(image: image)
        },
        copyText: { text in
            await MainActor.run {
                let service = ClipboardService()
                return service.copyText(
                    text,
                    initialChangeCount: service.changeCount,
                    jobIsLatest: true
                )
            }
        },
        copyImage: { image in
            await MainActor.run {
                let service = ClipboardService()
                return service.copyImage(
                    image,
                    initialChangeCount: service.changeCount,
                    jobIsLatest: true
                )
            }
        }
    )
}

actor TaAgentCapabilityService {
    private static let supportedMethods: [AgentMethod] = [
        .systemStatus, .systemCapabilities, .systemPermissions,
        .targetListDisplays, .targetListWindows,
        .captureDisplay, .captureFrontmost, .captureWindow, .captureRegion,
        .recognizeOCR, .analyzeImage, .translateText, .translateImage,
        .deliverCopy, .deliverSave
    ]

    private let captureService: TaAgentCaptureService
    private let artifactStore: TaAgentArtifactStore
    private let fixedPrivacyPolicy: TaAgentPrivacyPolicy?
    private let privacyPolicyProvider: @Sendable () -> TaAgentPrivacyPolicy
    private let auditLog: TaAgentAuditLog?
    private let dependencies: TaAgentCapabilityDependencies
    private var lastImage: CGImage?
    private var lastArtifact: AgentArtifact?

    init(
        captureService: TaAgentCaptureService = TaAgentCaptureService(),
        artifactStore: TaAgentArtifactStore = TaAgentArtifactStore(),
        privacyPolicy: TaAgentPrivacyPolicy? = nil,
        privacyPolicyProvider: @escaping @Sendable () -> TaAgentPrivacyPolicy = { .load() },
        auditLog: TaAgentAuditLog? = TaAgentAuditLog(),
        dependencies: TaAgentCapabilityDependencies = .live
    ) {
        self.captureService = captureService
        self.artifactStore = artifactStore
        fixedPrivacyPolicy = privacyPolicy
        self.privacyPolicyProvider = privacyPolicyProvider
        self.auditLog = auditLog
        self.dependencies = dependencies
    }

    func handle(_ request: AgentRequestEnvelope) async -> AgentResponseEnvelope {
        let startedAt = Date()
        let response: AgentResponseEnvelope
        do {
            response = try await dispatch(request)
        } catch let failure as CapabilityFailure {
            response = .failure(requestID: request.requestID, error: failure.payload)
        } catch is CancellationError {
            response = .failure(
                requestID: request.requestID,
                error: AgentErrorPayload(code: .cancelled, message: "Agent 请求已取消。", retryable: false)
            )
        } catch {
            response = .failure(
                requestID: request.requestID,
                error: AgentErrorPayload(
                    code: .internalError,
                    message: error.localizedDescription,
                    retryable: false
                )
            )
        }
        let completed = await withMetadata(response, request: request, startedAt: startedAt)
        if let auditLog {
            try? await auditLog.record(request: request, response: completed, occurredAt: startedAt)
        }
        return completed
    }

    private var privacyPolicy: TaAgentPrivacyPolicy {
        fixedPrivacyPolicy ?? privacyPolicyProvider()
    }

    private func dispatch(_ request: AgentRequestEnvelope) async throws -> AgentResponseEnvelope {
        if !privacyPolicy.isEnabled,
           ![AgentMethod.systemHandshake, .systemStatus, .systemCapabilities, .systemPermissions].contains(request.method) {
            throw CapabilityFailure(AgentErrorPayload(
                code: .targetBlockedByPrivacyPolicy,
                message: "拓的 Agent 调用已关闭。",
                hint: "打开拓 → 设置 → Agent 与自动化后启用。",
                retryable: false
            ))
        }
        switch request.method {
        case .systemHandshake:
            return .success(requestID: request.requestID)
        case .systemStatus:
            return await status(request)
        case .systemCapabilities:
            return capabilities(request)
        case .systemPermissions:
            return await permissions(request)
        case .targetListDisplays:
            return try await listDisplays(request)
        case .targetListWindows:
            return try await listWindows(request)
        case .captureDisplay, .captureFrontmost, .captureWindow, .captureRegion:
            return try await capture(request)
        case .recognizeOCR:
            return try await recognizeOCR(request)
        case .analyzeImage:
            return try await analyze(request)
        case .translateText:
            return try await translateText(request)
        case .translateImage:
            return try await translateImage(request)
        case .deliverCopy:
            return try await copy(request)
        case .deliverSave:
            return try await save(request)
        default:
            throw invalid("该 Agent 方法尚未支持：\(request.method.rawValue)")
        }
    }

    private func status(_ request: AgentRequestEnvelope) async -> AgentResponseEnvelope {
        .success(
            requestID: request.requestID,
            data: .object([
                "app": .string("Ta"),
                "version": .string(await dependencies.appVersion()),
                "protocolVersion": .integer(Int64(AgentProtocol.currentVersion)),
                "agentEnabled": .bool(privacyPolicy.isEnabled),
                "bridge": .string("ready")
            ])
        )
    }

    private func capabilities(_ request: AgentRequestEnvelope) -> AgentResponseEnvelope {
        .success(
            requestID: request.requestID,
            data: .object([
                "methods": .array(Self.supportedMethods.map { .string($0.rawValue) }),
                "capturePolicies": .array(AgentCapturePolicy.allCases.map { .string($0.rawValue) }),
                "cloudPolicies": .array(AgentCloudPolicy.allCases.map { .string($0.rawValue) })
            ])
        )
    }

    private func permissions(_ request: AgentRequestEnvelope) async -> AgentResponseEnvelope {
        .success(
            requestID: request.requestID,
            data: .object([
                "screenRecording": .bool(await dependencies.screenPermission()),
                "accessibility": .bool(await dependencies.accessibilityPermission()),
                "visionModelConfigured": .bool(await dependencies.visionConfigured()),
                "translationModelConfigured": .bool(await dependencies.translationConfigured())
            ])
        )
    }

    private func listDisplays(_ request: AgentRequestEnvelope) async throws -> AgentResponseEnvelope {
        let snapshot = try await captureService.snapshot()
        return .success(
            requestID: request.requestID,
            data: .object([
                "displays": .array(snapshot.displays.map { display in
                    .object([
                        "id": .integer(Int64(display.id)),
                        "frame": rectJSON(display.frame),
                        "pixelScale": .number(Double(display.pixelScale)),
                        "isMain": .bool(display.isMain)
                    ])
                })
            ])
        )
    }

    private func listWindows(_ request: AgentRequestEnvelope) async throws -> AgentResponseEnvelope {
        let snapshot = try await captureService.snapshot()
        let appFilter = (request.params.string("app")
            ?? request.params.string("bundleIdentifier"))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let windows = snapshot.windows.filter { window in
            privacyPolicy.allowsWindowMetadata(bundleIdentifier: window.bundleIdentifier)
                && (appFilter == nil
                    || window.bundleIdentifier?.lowercased() == appFilter
                    || window.appName.lowercased().contains(appFilter ?? ""))
        }
        return .success(
            requestID: request.requestID,
            data: .object([
                "frontmostProcessId": snapshot.frontmostProcessID.map { .integer(Int64($0)) } ?? .null,
                "windows": .array(windows.map(windowJSON))
            ])
        )
    }

    private func capture(_ request: AgentRequestEnvelope) async throws -> AgentResponseEnvelope {
        guard await dependencies.screenPermission() else {
            throw CapabilityFailure(AgentErrorPayload(
                code: .screenPermissionRequired,
                message: "拓尚未获得屏幕录制权限。",
                hint: "打开拓 → 设置 → 权限并启用屏幕录制。",
                retryable: false
            ))
        }
        let target = try captureTarget(for: request)
        let prepared: TaAgentPreparedCapture
        do {
            prepared = try await captureService.prepare(target)
        } catch {
            throw captureFailure(error)
        }
        if let error = privacyPolicy.captureError(
            for: prepared.target,
            visibleBundleIdentifiers: prepared.visibleBundleIdentifiers
        ) {
            throw CapabilityFailure(error)
        }
        let result: TaAgentCaptureResult
        do {
            result = try await captureService.capture(prepared)
        } catch {
            throw captureFailure(error)
        }
        let png = try Self.pngData(result.image)
        let artifact = try await artifactStore.save(
            data: png,
            requestID: request.requestID,
            filename: "capture.png",
            mimeType: "image/png",
            width: result.image.width,
            height: result.image.height
        )
        lastImage = result.image
        lastArtifact = artifact
        return .success(
            requestID: request.requestID,
            data: .object(["target": targetJSON(result.target)]),
            artifacts: [artifact]
        )
    }

    private func recognizeOCR(_ request: AgentRequestEnvelope) async throws -> AgentResponseEnvelope {
        let image = try loadImage(request)
        let engine = await dependencies.ocrEngine()
        if engine == .deepSeekOCR2,
           let error = privacyPolicy.cloudError(requested: request.params.cloudPolicy) {
            throw CapabilityFailure(error)
        }
        let languages = request.params.stringArray("languages") ?? defaultLanguages()
        let merge = request.params.bool("mergeWrappedLines")
            ?? UserDefaults.standard.bool(forKey: "mergeWrappedLines")
        let result = try await dependencies.recognizeOCR(image, languages, merge)
        return .success(
            requestID: request.requestID,
            data: .object([
                "text": .string(result.text),
                "confidence": .number(Double(result.confidence)),
                "contentType": .string(result.contentType.rawValue),
                "engine": .string(result.engine.rawValue),
                "languages": .array(result.languages.map { .string($0) })
            ])
        )
    }

    private func analyze(_ request: AgentRequestEnvelope) async throws -> AgentResponseEnvelope {
        if let error = privacyPolicy.cloudError(requested: request.params.cloudPolicy) {
            throw CapabilityFailure(error)
        }
        guard await dependencies.visionConfigured() else {
            throw CapabilityFailure(AgentErrorPayload(
                code: .modelProfileNotConfigured,
                message: "尚未配置可用的视觉模型。",
                hint: "打开拓 → 设置 → 模型与 API。",
                retryable: false
            ))
        }
        let image = try loadImage(request)
        let taskRaw = request.params.string("task") ?? MultimodalTaskTemplate.general.rawValue
        guard let task = MultimodalTaskTemplate(rawValue: taskRaw) else {
            throw invalid("未知的识图任务模板：\(taskRaw)")
        }
        let text = try await dependencies.analyzeImage(image, task)
        return .success(requestID: request.requestID, data: .object(["text": .string(text)]))
    }

    private func translateText(_ request: AgentRequestEnvelope) async throws -> AgentResponseEnvelope {
        try await ensureTranslationAllowed(request)
        guard let text = request.params.string("text"), !text.isEmpty else {
            throw invalid("translate.text 需要非空 text 参数。")
        }
        let translated = try await dependencies.translateText(text)
        return .success(requestID: request.requestID, data: .object(["text": .string(translated)]))
    }

    private func translateImage(_ request: AgentRequestEnvelope) async throws -> AgentResponseEnvelope {
        try await ensureTranslationAllowed(request)
        let translated = try await dependencies.translateImage(try loadImage(request))
        return .success(requestID: request.requestID, data: .object(["text": .string(translated)]))
    }

    private func copy(_ request: AgentRequestEnvelope) async throws -> AgentResponseEnvelope {
        let copied: Bool
        if let text = request.params.string("text") {
            copied = await dependencies.copyText(text)
        } else {
            copied = await dependencies.copyImage(try loadImage(request))
        }
        guard copied else { throw invalid("未能写入剪贴板。") }
        return .success(requestID: request.requestID, data: .object(["copied": .bool(true)]))
    }

    private func save(_ request: AgentRequestEnvelope) async throws -> AgentResponseEnvelope {
        guard let path = request.params.string("path"), path.hasPrefix("/") else {
            throw invalid("deliver.save 需要绝对路径 path。")
        }
        let image = try loadImage(request)
        let outputURL = URL(fileURLWithPath: path).standardizedFileURL
        let data = try Self.pngData(image)
        try data.write(to: outputURL, options: .atomic)
        return .success(
            requestID: request.requestID,
            data: .object([
                "path": .string(outputURL.path),
                "bytes": .integer(Int64(data.count))
            ])
        )
    }

    private func ensureTranslationAllowed(_ request: AgentRequestEnvelope) async throws {
        if let error = privacyPolicy.cloudError(requested: request.params.cloudPolicy) {
            throw CapabilityFailure(error)
        }
        guard await dependencies.translationConfigured() else {
            throw CapabilityFailure(AgentErrorPayload(
                code: .modelProfileNotConfigured,
                message: "尚未配置可用的翻译模型。",
                hint: "打开拓 → 设置 → 翻译。",
                retryable: false
            ))
        }
    }

    private func loadImage(_ request: AgentRequestEnvelope) throws -> CGImage {
        if let path = request.params.string("inputPath") {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw invalid("无法读取图片：\(url.path)")
            }
            return image
        }
        guard let lastImage else { throw invalid("没有可用的最近图片，请先截图或传入 inputPath。") }
        return lastImage
    }

    private func captureTarget(for request: AgentRequestEnvelope) throws -> TaAgentCaptureTarget {
        switch request.method {
        case .captureDisplay:
            return .display(id: request.params.uint32("displayId"))
        case .captureFrontmost:
            return .frontmost
        case .captureWindow:
            guard let id = request.params.uint32("windowId") else {
                throw invalid("capture.window 需要 windowId。")
            }
            return .window(id: id)
        case .captureRegion:
            guard let displayID = request.params.uint32("displayId"),
                  let x = request.params.number("x"),
                  let y = request.params.number("y"),
                  let width = request.params.number("width"),
                  let height = request.params.number("height") else {
                throw invalid("capture.region 需要 displayId、x、y、width、height。")
            }
            return .region(
                displayID: displayID,
                globalRect: CGRect(x: x, y: y, width: width, height: height)
            )
        default:
            throw invalid("不是截图方法。")
        }
    }

    private func captureFailure(_ error: Error) -> CapabilityFailure {
        let code: AgentErrorCode
        let message: String
        switch error {
        case TaAgentCaptureError.targetNotFound:
            code = .targetNotFound; message = "找不到指定截图目标。"
        case TaAgentCaptureError.targetChanged:
            code = .targetChanged; message = "截图前目标窗口已发生变化。"
        case TaAgentCaptureError.invalidRegion:
            code = .invalidRequest; message = "截图区域无效。"
        case TaAgentCaptureError.screenPermissionRequired:
            code = .screenPermissionRequired; message = "拓尚未获得屏幕录制权限。"
        default:
            code = .internalError; message = error.localizedDescription
        }
        return CapabilityFailure(AgentErrorPayload(code: code, message: message, retryable: code == .targetChanged))
    }

    private func defaultLanguages() -> [String] {
        let raw = UserDefaults.standard.string(forKey: "recognitionLanguages") ?? "zh-Hans,en-US"
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func withMetadata(
        _ response: AgentResponseEnvelope,
        request: AgentRequestEnvelope,
        startedAt: Date
    ) async -> AgentResponseEnvelope {
        let usedCloud: Bool
        switch request.method {
        case .analyzeImage, .translateText, .translateImage:
            usedCloud = response.ok
        case .recognizeOCR:
            let engine = await dependencies.ocrEngine()
            usedCloud = response.ok && engine == .deepSeekOCR2
        default:
            usedCloud = false
        }
        return AgentResponseEnvelope(
            requestID: response.requestID,
            ok: response.ok,
            data: response.data,
            artifacts: response.artifacts,
            meta: AgentResponseMetadata(
                durationMs: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000)),
                cloudUploaded: usedCloud
            ),
            error: response.error
        )
    }

    private func invalid(_ message: String) -> CapabilityFailure {
        CapabilityFailure(AgentErrorPayload(code: .invalidRequest, message: message, retryable: false))
    }

    private func rectJSON(_ rect: CGRect) -> JSONValue {
        .object([
            "x": .number(Double(rect.minX)), "y": .number(Double(rect.minY)),
            "width": .number(Double(rect.width)), "height": .number(Double(rect.height))
        ])
    }

    private func windowJSON(_ window: TaAgentWindowTarget) -> JSONValue {
        .object([
            "windowId": .integer(Int64(window.id)),
            "processId": .integer(Int64(window.ownerProcessID)),
            "appName": .string(window.appName),
            "bundleIdentifier": window.bundleIdentifier.map(JSONValue.string) ?? .null,
            "title": window.title.map(JSONValue.string) ?? .null,
            "frame": rectJSON(window.frame),
            "zOrder": .integer(Int64(window.zOrder))
        ])
    }

    private func targetJSON(_ target: TaAgentResolvedTarget) -> JSONValue {
        .object([
            "kind": .string(target.kind.rawValue),
            "displayId": target.displayID.map { .integer(Int64($0)) } ?? .null,
            "windowId": target.windowID.map { .integer(Int64($0)) } ?? .null,
            "processId": target.ownerProcessID.map { .integer(Int64($0)) } ?? .null,
            "appName": target.appName.map(JSONValue.string) ?? .null,
            "bundleIdentifier": target.bundleIdentifier.map(JSONValue.string) ?? .null,
            "title": target.title.map(JSONValue.string) ?? .null,
            "frame": rectJSON(target.frame)
        ])
    }

    private static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw CapabilityFailure.encodingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CapabilityFailure.encodingFailed }
        return data as Data
    }
}

private struct CapabilityFailure: Error {
    let payload: AgentErrorPayload

    init(_ payload: AgentErrorPayload) { self.payload = payload }

    static let encodingFailed = CapabilityFailure(AgentErrorPayload(
        code: .internalError,
        message: "无法编码 Agent 图片。",
        retryable: false
    ))
}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        guard case .string(let value) = self[key] else { return nil }
        return value
    }

    func bool(_ key: String) -> Bool? {
        guard case .bool(let value) = self[key] else { return nil }
        return value
    }

    func number(_ key: String) -> Double? {
        switch self[key] {
        case .number(let value): value
        case .integer(let value): Double(value)
        default: nil
        }
    }

    func uint32(_ key: String) -> UInt32? {
        guard let value = number(key), value >= 0, value <= Double(UInt32.max) else { return nil }
        return UInt32(value)
    }

    func stringArray(_ key: String) -> [String]? {
        guard case .array(let values) = self[key] else { return nil }
        return values.compactMap {
            guard case .string(let value) = $0 else { return nil }
            return value
        }
    }

    var cloudPolicy: AgentCloudPolicy? {
        string("cloud").flatMap(AgentCloudPolicy.init(rawValue:))
    }
}
