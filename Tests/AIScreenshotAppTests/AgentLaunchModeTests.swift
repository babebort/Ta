import Foundation
import Testing
@testable import AIScreenshotApp
import TaAgentClient

@Suite("Ta Agent launch mode")
struct AgentLaunchModeTests {
    @Test("agent bridge startup never schedules the welcome window")
    func agentBridgeSkipsWelcome() {
        let policy = AppLaunchPolicy(arguments: ["拓", "--agent-bridge"])

        #expect(policy.mode == .agentBridge)
        #expect(!policy.shouldScheduleWelcome)
    }

    @Test("normal startup still schedules the welcome window")
    func normalLaunchShowsWelcome() {
        let policy = AppLaunchPolicy(arguments: ["拓"])

        #expect(policy.mode == .normal)
        #expect(policy.shouldScheduleWelcome)
    }

    @Test("launcher requests a non-activating app open")
    func launcherDoesNotActivateTa() {
        let appURL = URL(fileURLWithPath: "/Applications/拓.app")
        let plan = TaAppLauncher.plan(applicationURL: appURL)

        #expect(plan.applicationURL == appURL)
        #expect(plan.arguments == ["--agent-bridge"])
        #expect(!plan.activatesApplication)
    }
}
