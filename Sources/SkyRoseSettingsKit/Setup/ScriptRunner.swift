import Foundation

/// Runs an engine script (`/bin/sh script --progress …`) and turns its stdout into
/// ``SetupProgressState`` on the main thread, line by line, as the lines arrive.
@MainActor
public final class ScriptRunner: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case idle, running
        case ended(exitCode: Int32)
    }

    @Published public private(set) var progress = SetupProgressState()
    @Published public private(set) var phase: Phase = .idle
    /// The last lines the script wrote to stderr (shown when it stops early).
    @Published public private(set) var errorOutput = ""
    public var onEvent: (SetupEvent) -> Void = { _ in }

    private var process: Process?
    private var buffer = Data()
    /// Kept open for the whole run. The uninstaller blocks on a line here after `::sip`.
    private var input: Pipe?

    public init() {}

    public var started: Bool { phase != .idle }
    public var isRunning: Bool { phase == .running }

    /// Exited without `::finished` (crash, refusal, missing script): the window shows an error.
    public var stoppedEarly: Bool {
        if case .ended(let code) = phase { return code != 0 || !progress.finished }
        return false
    }

    public func start(script: URL, arguments: [String], environment: [String: String]? = nil) {
        guard !isRunning else { return }
        progress = SetupProgressState()
        errorOutput = ""
        buffer = Data()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path, "--progress"] + arguments
        if let environment { p.environment = environment }
        let input = Pipe()
        self.input = input
        p.standardInput = input
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let box = WeakRunner(self)
        out.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            DispatchQueue.main.async { MainActor.assumeIsolated { box.runner?.receive(data) } }
        }
        err.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self = box.runner else { return }
                    self.errorOutput = String((self.errorOutput + s).suffix(2000))
                }
            }
        }
        p.terminationHandler = { proc in
            let code = proc.terminationStatus
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            let rest = out.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self = box.runner else { return }
                    self.receive(rest)
                    self.flushPartialLine()
                    self.phase = .ended(exitCode: code)
                    self.process = nil
                }
            }
        }
        do {
            try p.run()
            process = p
            phase = .running
        } catch {
            errorOutput = "Could not start \(script.lastPathComponent): \(error.localizedDescription)"
            phase = .ended(exitCode: 127)
        }
    }

    /// The uninstall window calls this when the SIP reminder is dismissed. The engine is blocked
    /// on stdin and will not trash anything until this line arrives. EOF is not an acknowledgement.
    public func acknowledgeSIP() {
        guard let handle = input?.fileHandleForWriting else { return }
        try? handle.write(contentsOf: Data("ack\n".utf8))
    }

    func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...nl)
            handle(line)
        }
    }

    private func flushPartialLine() {
        guard !buffer.isEmpty else { return }
        handle(String(decoding: buffer, as: UTF8.self))
        buffer = Data()
    }

    private func handle(_ line: String) {
        let e = SetupEvent.parse(line)
        progress.apply(e)
        onEvent(e)
    }
}

/// Lets the pipe and termination handlers (any thread) reach the runner on the main thread.
private final class WeakRunner: @unchecked Sendable {
    weak var runner: ScriptRunner?
    init(_ r: ScriptRunner) { runner = r }
}
