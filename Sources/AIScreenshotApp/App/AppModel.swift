import AppKit
import Combine
import AIScreenshotCore
import TaAgentClient
import TaAgentContracts

enum AppLaunchMode: Equatable {
    case normal
    case agentBridge
}

struct AppLaunchPolicy: Equatable {
    let mode: AppLaunchMode

    init(arguments: [String]) {
        mode = arguments.contains("--agent-bridge") ? .agentBridge : .normal
    }

    var shouldScheduleWelcome: Bool { mode == .normal }
}

@MainActor
final class AppModel: ObservableObject {
    static weak var current: AppModel?

    @Published private(set) var statusText = "Ready for local recognition"
    @Published private(set) var isCapturing = false

    private let hotKeyManager = GlobalHotKeyManager()
    private let captureCoordinator = CaptureCoordinator()
    private let welcomeWindowController = WelcomeWindowController()
    private let settingsWindowController = SettingsWindowController()
    private let launchArguments: [String]
    private let launchPolicy: AppLaunchPolicy
    private var hasStarted = false
    private var hotKeyFailureObserver: NSObjectProtocol?
    private var agentBridgeServer: TaAgentBridgeServer?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        launchArguments = arguments
        launchPolicy = AppLaunchPolicy(arguments: arguments)
        Self.current = self
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        startAgentBridge()

        do {
            try hotKeyManager.registerDefaults(
                interactiveCapture: { [weak self] in self?.startCapture(.interactive) },
                intelligentCapture: { [weak self] in self?.startCapture(.intelligent) },
                translationCapture: { [weak self] in self?.startCapture(.translation) },
                imageCapture: { [weak self] in self?.startCapture(.image) },
                pinCapture: { [weak self] in self?.startCapture(.pin) },
                longCapture: { [weak self] in self?.startCapture(.long) }
            )
        } catch {
            statusText = "Failed to register shortcut"
        }
        hotKeyFailureObserver = NotificationCenter.default.addObserver(
            forName: HotKeyPreferences.registrationFailedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let message = notification.userInfo?[HotKeyPreferences.errorMessageUserInfoKey] as? String
            Task { @MainActor in
                self?.statusText = message ?? "Shortcut conflict, restored the previous configuration"
            }
        }

        ConfiguredOCRService().prewarmIfNeeded()

        let arguments = launchArguments
        if launchPolicy.mode == .agentBridge {
            return
        } else if arguments.contains("--capture-fixed") {
            scheduleFixedCapture()
        } else if arguments.contains("--ui-smoke-capture-toolbar") {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard let self else { return }
                showWelcome()
                try? await Task.sleep(for: .milliseconds(220))
                captureCoordinator.openCaptureToolbarSmokeFixture { [weak self] in
                    self?.statusText = "Ready for local recognition"
                }
            }
        } else if arguments.contains("--ui-smoke-result-bar-success") {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                self?.captureCoordinator.openResultBarSmokeFixture(kind: .success)
            }
        } else if arguments.contains("--ui-smoke-result-bar-failure") {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                self?.captureCoordinator.openResultBarSmokeFixture(kind: .failure)
            }
        } else if arguments.contains("--ui-smoke-editor") {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                self?.captureCoordinator.openEditorSmokeFixture()
            }
        } else if arguments.contains("--ui-smoke-inline-editor") {
            isCapturing = true
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                self?.captureCoordinator.openInlineEditorSmokeFixture { [weak self] in
                    self?.isCapturing = false
                    self?.statusText = "Ready for local recognition"
                }
            }
        } else if arguments.contains("--capture-intelligent") {
            scheduleLaunchCapture(.intelligent)
        } else if arguments.contains("--capture-image") {
            scheduleLaunchCapture(.image)
        } else if arguments.contains("--capture-pin") {
            scheduleLaunchCapture(.pin)
        } else if launchPolicy.shouldScheduleWelcome {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, self?.isCapturing == false else { return }
                self?.showWelcome()
            }
        }
    }

    private func startAgentBridge() {
        let capabilityService = TaAgentCapabilityService()
        let router = TaAgentRequestRouter { request in
            await capabilityService.handle(request)
        }
        let server = TaAgentBridgeServer(
            socketURL: TaBridgeEndpoint.defaultSocketURL,
            router: router
        )
        do {
            try server.start()
            agentBridgeServer = server
        } catch {
            statusText = "Agent Bridge failed to start"
        }
    }

    func showWelcome() {
        guard !isCapturing else { return }
        NotificationCenter.default.post(name: .taMenuBarShouldClose, object: nil)
        welcomeWindowController.show(appModel: self)
    }

    func showSettings() {
        NotificationCenter.default.post(name: .taMenuBarShouldClose, object: nil)
        NSApplication.shared.activate()
        if let settingsItem = NSApplication.shared.mainMenu?.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first(where: {
                $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command)
            }),
           let action = settingsItem.action,
           NSApplication.shared.sendAction(action, to: settingsItem.target, from: settingsItem) {
            return
        }
        settingsWindowController.show()
    }

    func startCapture(_ mode: CaptureMode) {
        guard !isCapturing else { return }
        NotificationCenter.default.post(name: .taMenuBarShouldClose, object: nil)
        isCapturing = true
        statusText = switch mode {
        case .interactive: "Select an area, then choose an action"
        case .intelligent: "Select the area to recognize"
        case .translation: "Select the area to translate"
        case .image: "Select the area to copy"
        case .pin: "Select the area to pin"
        case .long: "Select a starting point to capture to the bottom of the scroll area"
        }

        captureCoordinator.start(mode: mode) { [weak self] outcome in
            guard let self else { return }
            isCapturing = false
            switch outcome {
            case .cancelled:
                statusText = "Ready for local recognition"
            case .completed(let message):
                statusText = message
            case .failed(let message):
                statusText = message
            }
        }
    }

    func pinClipboardContent() {
        statusText = captureCoordinator.pinClipboardContent() ? "Pinned from clipboard" : "Nothing in the clipboard to pin"
    }

    func hideAllPins() {
        captureCoordinator.hideAllPins()
        statusText = "Hid all pinned images"
    }

    func showAllPins() {
        captureCoordinator.showAllPins()
        statusText = "Showed all pinned images"
    }

    func restorePinInteraction() {
        captureCoordinator.enableAllPinInteraction()
        statusText = "Restored mouse interaction for pinned images"
    }

    func restoreLastClosedPin() {
        statusText = captureCoordinator.restoreLastClosedPin() ? "Restored the most recently closed pin" : "No pin to restore"
    }

    private func scheduleLaunchCapture(_ mode: CaptureMode) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.startCapture(mode)
        }
    }

    private func scheduleFixedCapture() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            isCapturing = true
            captureCoordinator.startFixedTestRegion(mode: .intelligent) { [weak self] outcome in
                guard let self else { return }
                isCapturing = false
                switch outcome {
                case .cancelled:
                    statusText = "Ready for local recognition"
                case .completed(let message):
                    statusText = message
                case .failed(let message):
                    statusText = message
                }
            }
        }
    }
}
