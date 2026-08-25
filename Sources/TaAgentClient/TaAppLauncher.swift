import AppKit
import Foundation

public enum TaBridgeEndpoint {
    public static var defaultSocketURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Ta", isDirectory: true)
            .appendingPathComponent("agent-v1.sock", isDirectory: false)
    }
}

public struct TaAppLaunchPlan: Equatable, Sendable {
    public let applicationURL: URL
    public let arguments: [String]
    public let activatesApplication: Bool

    public init(applicationURL: URL, arguments: [String], activatesApplication: Bool) {
        self.applicationURL = applicationURL
        self.arguments = arguments
        self.activatesApplication = activatesApplication
    }
}

public enum TaAppLauncherError: Error, LocalizedError, Sendable {
    case appNotInstalled(String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .appNotInstalled(let path):
            "找不到拓 App：\(path)"
        case .launchFailed(let message):
            "无法在后台启动拓：\(message)"
        }
    }
}

public struct TaAppLauncher: Sendable {
    public static let defaultApplicationURL = URL(fileURLWithPath: "/Applications/拓.app", isDirectory: true)

    public static func plan(
        applicationURL: URL = defaultApplicationURL
    ) -> TaAppLaunchPlan {
        TaAppLaunchPlan(
            applicationURL: applicationURL,
            arguments: ["--agent-bridge"],
            activatesApplication: false
        )
    }

    private let launchPlan: TaAppLaunchPlan

    public init(applicationURL: URL = defaultApplicationURL) {
        launchPlan = Self.plan(applicationURL: applicationURL)
    }

    @MainActor
    public func launch() async throws {
        guard FileManager.default.fileExists(atPath: launchPlan.applicationURL.path) else {
            throw TaAppLauncherError.appNotInstalled(launchPlan.applicationURL.path)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = launchPlan.arguments
        configuration.activates = launchPlan.activatesApplication
        configuration.addsToRecentItems = false

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(
                at: launchPlan.applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: TaAppLauncherError.launchFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
