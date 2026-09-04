import Darwin
import Foundation
import TaAgentClient
import TaAgentContracts

@main
struct TaCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let invocation: CLIInvocation
        do {
            invocation = try CLIParser.parse(arguments)
        } catch let error as CLIParseError {
            write(error.message, to: .standardError)
            Darwin.exit(CLIExitCode.usage.rawValue)
        } catch {
            write(error.localizedDescription, to: .standardError)
            Darwin.exit(CLIExitCode.usage.rawValue)
        }

        signal(SIGINT, SIG_IGN)
        let execution = Task { try await CLIRunner().execute(invocation) }
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        signalSource.setEventHandler { execution.cancel() }
        signalSource.resume()
        defer { signalSource.cancel() }

        do {
            let response = try await execution.value
            let rendered = try CLIOutput.render(response, format: invocation.outputFormat)
            let destination: FileHandle = response.ok ? .standardOutput : .standardError
            write(rendered, to: destination)
            Darwin.exit(CLIExitCode.forResponse(response).rawValue)
        } catch is CancellationError {
            write("CANCELLED: The request was cancelled.", to: .standardError)
            Darwin.exit(CLIExitCode.cancelled.rawValue)
        } catch let error as TaAppLauncherError {
            write("TA_APP_NOT_INSTALLED: \(error.localizedDescription)", to: .standardError)
            Darwin.exit(CLIExitCode.appNotInstalled.rawValue)
        } catch let error as TaBridgeClientError {
            write("BRIDGE_UNAVAILABLE: \(error.localizedDescription)", to: .standardError)
            Darwin.exit(CLIExitCode.bridgeUnavailable.rawValue)
        } catch {
            write("INTERNAL_ERROR: \(error.localizedDescription)", to: .standardError)
            Darwin.exit(CLIExitCode.requestFailed.rawValue)
        }
    }

    private static func write(_ string: String, to handle: FileHandle) {
        if let data = "\(string)\n".data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }
}
