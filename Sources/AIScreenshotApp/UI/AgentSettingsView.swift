import AppKit
import SwiftUI
import TaAgentContracts

enum TaAgentInstallationGuide {
  static let installCommand =
    "curl -fsSL --retry 3 --retry-all-errors --retry-delay 1 https://github.com/kangarooking/Ta/releases/latest/download/install.sh | bash"
  static let verificationCommand = "ta status --json"
  static let agentPrompt = """
    Please help me install the Ta CLI and Agent Skill on this Mac. Run the following command:
    curl -fsSL --retry 3 --retry-all-errors --retry-delay 1 https://github.com/kangarooking/Ta/releases/latest/download/install.sh | bash

    After installation, run ~/.local/bin/ta status --json to verify. Confirm the top-level JSON "ok" is true and "data.bridge" is "ready"; if it's only that permissions aren't granted yet, tell me to go to "Ta → Settings → Permissions / Agent" to authorize. Do not ask for, read, or output any API key, and do not change my cloud model configuration on my behalf.
    """
}

struct TaAgentToolInstallationStatus: Equatable {
  let cliInstalled: Bool
  let installedSkillLocations: [String]

  var skillInstalled: Bool { !installedSkillLocations.isEmpty }

  static func detect(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    codexHomeDirectory: URL? = nil,
    fileManager: FileManager = .default
  ) -> TaAgentToolInstallationStatus {
    let cli = homeDirectory.appendingPathComponent(".local/bin/ta").path
    let codexRoot = codexHomeDirectory ?? homeDirectory.appendingPathComponent(".codex")
    let candidates = [
      codexRoot.appendingPathComponent("skills/ta"),
      homeDirectory.appendingPathComponent(".agents/skills/ta"),
      homeDirectory.appendingPathComponent(".claude/skills/ta"),
    ]
    let installedSkills = candidates.filter {
      fileManager.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path)
    }
    return TaAgentToolInstallationStatus(
      cliInstalled: fileManager.isExecutableFile(atPath: cli),
      installedSkillLocations: installedSkills.map(\.path)
    )
  }
}

struct AgentSettingsView: View {
  @AppStorage(TaAgentPreferenceKey.accessEnabled) private var accessEnabled = true
  @AppStorage(TaAgentPreferenceKey.automaticCaptureAllowed) private var automaticCaptureAllowed =
    true
  @AppStorage(TaAgentPreferenceKey.cloudPolicy) private var cloudPolicy = AgentCloudPolicy.auto
    .rawValue
  @AppStorage(TaAgentPreferenceKey.privacyDenylist) private var privacyDenylist = ""
  @AppStorage(TaAgentPreferenceKey.allowCaptureTa) private var allowCaptureTa = true

  @State private var recentCalls: [TaAgentAuditEntry] = []
  @State private var operationMessage: String?
  @State private var installationStatus = TaAgentToolInstallationStatus.detect()
  private let auditLog = TaAgentAuditLog()
  private let artifactStore = TaAgentArtifactStore()

  var body: some View {
    VStack(spacing: 0) {
      installationPanel

      Divider()
        .overlay(TaPalette.hairline)

      Form {
        Section("Agent & Automation") {
          Toggle("Allow local Agents to call Ta", isOn: $accessEnabled)
          Text(
            accessEnabled
              ? "The CLI, Agent Skill, and DeepSeek Harness can call Ta through a local, current-user-only bridge."
              : "All Agent capabilities are denied except status and permission checks."
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          Toggle("Allow unattended auto-capture", isOn: $automaticCaptureAllowed)
            .disabled(!accessEnabled)
          Label("Normal captures never pop up Ta, steal foreground focus, move the mouse, or send keyboard events.", systemImage: "cursorarrow.rays")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Cloud & Models") {
          Picker("Default Cloud Policy", selection: $cloudPolicy) {
            Text("Decide by capability (recommended)").tag(AgentCloudPolicy.auto.rawValue)
            Text("Allow configured cloud models").tag(AgentCloudPolicy.allow.rawValue)
            Text("Always deny uploads").tag(AgentCloudPolicy.deny.rawValue)
          }
          .disabled(!accessEnabled)
          Text(cloudPolicyDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
          Label("Agents can only ask Ta to run a model task; they can't read API keys from the Keychain.", systemImage: "key.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Privacy App Denylist") {
          TextEditor(text: $privacyDenylist)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 68)
            .padding(6)
            .scrollContentBackground(.hidden)
            .background(TaPalette.elevatedPaper.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TaPalette.hairline, lineWidth: 1)
            }
            .disabled(!accessEnabled)
          Text("One Bundle ID per line, e.g. com.1password.1password. A capture is refused whenever the screen contains a denylisted app.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("Allow Agents to capture Ta itself", isOn: $allowCaptureTa)
            .disabled(!accessEnabled)
        }

        Section("Cache & Call History") {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text("Temporary Screenshot Cache")
              Text("Images are stored in a local cache and cleared automatically after 24 hours by default.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear Now") { clearArtifacts() }
          }

          HStack {
            Text("Recent Calls")
            Spacer()
            Button("Refresh") { refreshAudit() }
              .buttonStyle(.link)
            Button("Clear History") { clearAudit() }
              .buttonStyle(.link)
              .disabled(recentCalls.isEmpty)
          }

          if recentCalls.isEmpty {
            Text("No call history yet. The audit log never stores API keys, OCR/translation text, or image data.")
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            ForEach(recentCalls.prefix(8)) { entry in
              auditRow(entry)
            }
            Text("Only the last 100 calls are kept; request parameters and recognized content are never logged.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let operationMessage {
            Text(operationMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .background(Color.clear)
    }
    .onAppear {
      refreshAudit()
      refreshInstallationStatus()
    }
  }

  private var installationPanel: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 8) {
        Text("Install CLI & Skill")
          .font(.headline)
        installationBadge(
          title: "ta CLI",
          installed: installationStatus.cliInstalled
        )
        installationBadge(
          title: installationStatus.skillInstalled
            ? "Ta Skill · \(installationStatus.installedSkillLocations.count) location(s)"
            : "Ta Skill",
          installed: installationStatus.skillInstalled
        )
        Spacer()
        Button("Recheck", systemImage: "arrow.clockwise") {
          refreshInstallationStatus()
        }
        .buttonStyle(.borderless)
      }

      Text("One command installs or updates both the CLI and the Skill; it verifies the download and adapts to the Codex and general Agent Skills directories.")
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(alignment: .top, spacing: 10) {
        installationBlock(
          title: "Option 1 · Terminal",
          subtitle: "Copy the command and run it",
          symbol: "terminal",
          content: TaAgentInstallationGuide.installCommand,
          maximumLines: 2,
          copiedMessage: "Terminal install command copied."
        )
        installationBlock(
          title: "Option 2 · Hand to an Agent",
          subtitle: "Copy the full install prompt",
          symbol: "sparkles",
          content: TaAgentInstallationGuide.agentPrompt,
          maximumLines: 2,
          copiedMessage: "Agent install prompt copied."
        )
      }

      Label(
        "After installing, restart your Agent, then run \(TaAgentInstallationGuide.verificationCommand) to verify the connection.",
        systemImage: "checkmark.shield"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 20)
    .padding(.top, 13)
    .padding(.bottom, 11)
    .background(TaPalette.paper.opacity(0.55))
  }

  private var cloudPolicyDescription: String {
    switch AgentCloudPolicy(rawValue: cloudPolicy) ?? .auto {
    case .auto:
      "Local capture and OCR stay on-device; capabilities like vision, translation, or DeepSeek OCR use the cloud per task. Callers can still force local-only with cloud=deny."
    case .allow:
      "Allows Agents to use the cloud models you've already configured in Ta. Every call still logs whether it went to the cloud."
    case .deny:
      "Every Agent call that needs to upload an image or text is denied; only local capture and local OCR remain available."
    }
  }

  private func installationBadge(title: String, installed: Bool) -> some View {
    Label(title, systemImage: installed ? "checkmark.circle.fill" : "circle.dashed")
      .font(.caption.weight(.semibold))
      .foregroundStyle(installed ? Color.green : TaPalette.mutedInk)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(
        Capsule(style: .continuous)
          .fill(installed ? Color.green.opacity(0.10) : TaPalette.ink.opacity(0.06))
      )
  }

  private func installationBlock(
    title: String,
    subtitle: String,
    symbol: String,
    content: String,
    maximumLines: Int,
    copiedMessage: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: symbol)
          .foregroundStyle(TaPalette.cinnabar)
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
            .font(.subheadline.weight(.semibold))
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("Copy", systemImage: "doc.on.doc") {
          copyInstallationText(content, message: copiedMessage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }

      Text(content)
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(TaPalette.ink.opacity(0.82))
        .textSelection(.enabled)
        .lineLimit(maximumLines)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(TaPalette.ink.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .padding(11)
    .background(TaPalette.elevatedPaper.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .stroke(TaPalette.hairline, lineWidth: 1)
    }
  }

  @ViewBuilder
  private func auditRow(_ entry: TaAgentAuditEntry) -> some View {
    HStack(spacing: 10) {
      Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(entry.succeeded ? Color.green : Color.red)
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.method.rawValue)
          .font(.system(.caption, design: .monospaced).weight(.semibold))
        Text(
          "\(entry.clientName) · \(entry.occurredAt.formatted(date: .omitted, time: .shortened))"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
      }
      Spacer()
      if entry.cloudUploaded {
        Label("Cloud", systemImage: "icloud.and.arrow.up")
          .font(.caption2)
          .foregroundStyle(.orange)
      } else {
        Text("Local")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Text("\(entry.durationMs) ms")
        .font(.system(.caption2, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 68, alignment: .trailing)
    }
  }

  private func refreshAudit() {
    Task {
      do {
        recentCalls = try await auditLog.recent(limit: 20)
        operationMessage = nil
      } catch {
        operationMessage = "Unable to read call history: \(error.localizedDescription)"
      }
    }
  }

  private func refreshInstallationStatus() {
    installationStatus = TaAgentToolInstallationStatus.detect()
  }

  private func copyInstallationText(_ text: String, message: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    if pasteboard.setString(text, forType: .string) {
      operationMessage = message
    } else {
      operationMessage = "Copy failed; please select and copy it manually."
    }
  }

  private func clearAudit() {
    Task {
      do {
        try await auditLog.clear()
        recentCalls = []
        operationMessage = "Call history cleared."
      } catch {
        operationMessage = "Clear failed: \(error.localizedDescription)"
      }
    }
  }

  private func clearArtifacts() {
    Task {
      do {
        let count = try await artifactStore.clearAll()
        operationMessage = count == 0 ? "There's no temporary screenshot cache right now." : "Cleared \(count) temporary screenshot set(s)."
      } catch {
        operationMessage = "Cache cleanup failed: \(error.localizedDescription)"
      }
    }
  }
}
