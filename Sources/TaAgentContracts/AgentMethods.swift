import Foundation

public enum AgentMethod: String, Codable, CaseIterable, Sendable {
    case systemHandshake = "system.handshake"
    case systemStatus = "system.status"
    case systemCapabilities = "system.capabilities"
    case systemPermissions = "system.permissions"
    case targetListDisplays = "target.listDisplays"
    case targetListWindows = "target.listWindows"
    case captureDisplay = "capture.display"
    case captureFrontmost = "capture.frontmost"
    case captureWindow = "capture.window"
    case captureRegion = "capture.region"
    case captureInteractive = "capture.interactive"
    case captureScroll = "capture.scroll"
    case recognizeOCR = "recognize.ocr"
    case analyzeImage = "analyze.image"
    case translateText = "translate.text"
    case translateImage = "translate.image"
    case transformImage = "transform.image"
    case deliverCopy = "deliver.copy"
    case deliverSave = "deliver.save"
    case deliverPin = "deliver.pin"
    case jobStatus = "job.status"
    case jobCancel = "job.cancel"
}

public enum AgentCapturePolicy: String, Codable, CaseIterable, Sendable {
    case silent
    case idle
    case interactive
}

public enum AgentCloudPolicy: String, Codable, CaseIterable, Sendable {
    case auto
    case allow
    case deny
}

