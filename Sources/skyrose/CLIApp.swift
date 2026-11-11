import Foundation
import CaelestiaCore
import CaelestiaIPC

/// Process exit codes (spec 4.8 / README).
enum ExitCode {
    static let ok: Int32 = 0
    static let failed: Int32 = 1
    static let notRunning: Int32 = 2
    static let usage: Int32 = 3
}

/// Terminal output helpers: results on stdout, diagnostics on stderr.
enum Console {
    static func out(_ text: String, terminator: String = "\n") {
        FileHandle.standardOutput.write(Data((text + terminator).utf8))
    }

    static func err(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    /// `skyrose: <message>` on stderr.
    static func error(_ message: String) {
        err("\(CLIParser.programName): \(message)")
    }

    static var stdinIsTerminal: Bool { isatty(STDIN_FILENO) == 1 }
}

/// Parses the arguments and dispatches to IPC or local commands.
struct CLIApp {
    let arguments: [String]

    func run() -> Int32 {
        let invocation: CLIInvocation
        do {
            invocation = try CLIParser.parse(arguments)
        } catch let error as CLIUsageError {
            Console.error(error.localizedDescription)
            Console.err("")
            Console.err(CLIParser.usage(for: error.topic))
            return ExitCode.usage
        } catch {
            Console.error(error.localizedDescription)
            return ExitCode.usage
        }

        let socket = invocation.socketPath.map { URL(fileURLWithPath: CLIParser.absolutePath($0)) } ?? Paths.ipcSocket
        let client = IPCClient(path: socket)

        switch invocation.kind {
        case .help(let topic):
            Console.out(CLIParser.usage(for: topic), terminator: "")
            return ExitCode.ok
        case .version:
            return LocalCommands.version(client: client, json: invocation.json)
        case .local(let command):
            return LocalCommands.run(command, invocation: invocation, client: client)
        case .ipc(let request):
            let code = send(request, invocation: invocation, client: client)
            if request.knownCommand == .wmPanic {
                LocalCommands.neutraliseScriptingAddition()
                // Also when the WM hangs or is gone: no addon content until switched back on.
                let n = AddonStore().disableAll()
                if n > 0 { Console.err("SkyStore: \(n) addon\(n == 1 ? "" : "s") switched off (skyrose store enable <id> turns one back on)") }
            }
            return code
        }
    }

    /// Sends one request and prints its result (table by default, raw JSON with `--json`).
    private func send(_ request: IPCRequest, invocation: CLIInvocation, client: IPCClient) -> Int32 {
        do {
            let response = try client.send(request, timeout: invocation.timeout ?? 5)
            guard response.ok else {
                Console.error(response.error ?? "'\(request.command)' failed")
                return ExitCode.failed
            }
            if invocation.json {
                Console.out(response.result?.prettyJSON ?? "null")
            } else {
                let text = QueryFormatter.render(response.result, command: request.knownCommand)
                if !text.isEmpty { Console.out(text, terminator: "") }
            }
            return ExitCode.ok
        } catch let error as IPCError {
            return report(error)
        } catch {
            Console.error(error.localizedDescription)
            return ExitCode.failed
        }
    }

    /// Prints an IPC error and maps it to the exit code.
    static func report(_ error: IPCError) -> Int32 {
        Console.error(error.localizedDescription)
        return error.isNotRunning ? ExitCode.notRunning : ExitCode.failed
    }

    private func report(_ error: IPCError) -> Int32 { CLIApp.report(error) }
}
