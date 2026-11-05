import CaelestiaCore
import CaelestiaIPC
import Foundation

/// Talks to the running SkyRose WM over its IPC socket, off the main thread. Every call has a
/// short timeout; "not running" is a normal answer, never an error dialog.
public final class WMConnection: @unchecked Sendable {
    public let socket: URL
    private let queue = DispatchQueue(label: "com.skyrose.mac.settings.ipc", qos: .userInitiated)

    public init(socket: URL = Paths.ipcSocket) {
        self.socket = socket
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notRunning
        /// The socket is there but no answer in time: SkyRose is running and busy (for example
        /// tiling every window right after Accessibility was granted).
        case busy
        case refused(String)
        public var description: String {
            switch self {
            case .notRunning: return "SkyRose is not running"
            case .busy: return "SkyRose is busy; try again in a moment"
            case .refused(let m): return m
            }
        }
    }

    /// One request; the completion runs on the main queue.
    public func call(_ command: IPCCommand, args: [String: JSONValue] = [:], timeout: TimeInterval = 2,
                     completion: @escaping @MainActor @Sendable (Result<JSONValue, Failure>) -> Void) {
        let socket = socket
        queue.async {
            let result: Result<JSONValue, Failure>
            do {
                let response = try IPCClient(path: socket).send(IPCRequest(command, args: args), timeout: timeout)
                result = response.ok ? .success(response.result ?? .null) : .failure(.refused(response.error ?? "\(command.rawValue) failed"))
            } catch let e as IPCError {
                switch e {
                case .notRunning: result = .failure(.notRunning)
                case .timeout: result = .failure(.busy)
                case .remote(let m): result = .failure(.refused(m))
                default: result = .failure(.refused(e.localizedDescription))
                }
            } catch {
                result = .failure(.refused(error.localizedDescription))
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(result) } }
        }
    }

    /// Synchronous variant for tests and the command line (never on the main thread in the app).
    public func callSync(_ command: IPCCommand, args: [String: JSONValue] = [:], timeout: TimeInterval = 2) -> Result<JSONValue, Failure> {
        do {
            let response = try IPCClient(path: socket).send(IPCRequest(command, args: args), timeout: timeout)
            return response.ok ? .success(response.result ?? .null) : .failure(.refused(response.error ?? "failed"))
        } catch let e as IPCError {
            if case .timeout = e { return .failure(.busy) }
            return .failure(.notRunning)
        } catch {
            return .failure(.notRunning)
        }
    }
}

/// `rules.apps` rows (same fields as the WM's `AppRuleEntry`).
public struct AppRuleRow: Codable, Equatable, Identifiable, Sendable {
    public var bundleID: String
    public var name: String
    public var rule: String
    public var mode: String
    public var source: String
    public var running: Bool
    public var windows: Int
    public var floatingWindows: Int
    public var id: String { bundleID }

    public init(bundleID: String, name: String, rule: String, mode: String = "auto", source: String = "user",
                running: Bool = false, windows: Int = 0, floatingWindows: Int = 0) {
        self.bundleID = bundleID
        self.name = name
        self.rule = rule
        self.mode = mode
        self.source = source
        self.running = running
        self.windows = windows
        self.floatingWindows = floatingWindows
    }

    public static func decode(_ v: JSONValue) -> [AppRuleRow] {
        guard let data = try? JSONEncoder().encode(v) else { return [] }
        return (try? JSONDecoder().decode([AppRuleRow].self, from: data)) ?? []
    }
}
