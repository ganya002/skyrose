import Darwin
import Foundation
import CaelestiaCore

/// Wire-level constants of the Caelestia IPC protocol: one JSON object per line, UTF-8,
/// `\n` terminated, over a Unix domain stream socket (mode 0600).
public enum IPCWire {
    /// Longest accepted line (request or response) in bytes, newline excluded.
    public static let maxLineBytes = 1_048_576
    /// The handshake command every server answers without consulting its handler.
    public static let helloCommand = "hello"
    /// Line terminator.
    public static let newline: UInt8 = 0x0A

    /// Encodes a value as one compact JSON line (newline appended).
    public static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONValue.encoder.encode(value)
        data.append(newline)
        return data
    }

    /// Decodes one line (with or without its trailing newline).
    public static func decodeLine<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        var slice = line
        if slice.last == newline { slice.removeLast() }
        if slice.last == 0x0D { slice.removeLast() }  // tolerate CRLF from hand-typed clients
        return try JSONValue.decoder.decode(T.self, from: slice)
    }
}

/// A request from a client (CLI, Settings app, shell) to the WM.
///
/// `id` is echoed back in the response so a client that pipelines several requests over one
/// connection can correlate them. `args` may be omitted on the wire (`{"command":"hello"}`).
public struct IPCRequest: Codable, Hashable, Sendable {
    public var id: Int
    public var command: String
    public var args: [String: JSONValue]

    public init(id: Int = 0, command: String, args: [String: JSONValue] = [:]) {
        self.id = id
        self.command = command
        self.args = args
    }

    public init(id: Int = 0, _ command: IPCCommand, args: [String: JSONValue] = [:]) {
        self.init(id: id, command: command.rawValue, args: args)
    }

    private enum CodingKeys: String, CodingKey { case id, command, args }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        command = try c.decode(String.self, forKey: .command)
        args = try c.decodeIfPresent([String: JSONValue].self, forKey: .args) ?? [:]
    }

    /// The catalog entry for `command`, if it is a known command.
    public var knownCommand: IPCCommand? { IPCCommand(rawValue: command) }

    // MARK: Typed argument helpers (used by the WM's handler)

    /// Returns the argument as a string; numbers and bools are stringified.
    public func string(_ name: String) -> String? {
        switch args[name] {
        case .string(let s)?: return s
        case .number(let d)?: return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case .bool(let b)?: return String(b)
        default: return nil
        }
    }

    /// Returns the argument as an integer (numbers, or decimal strings).
    public func int(_ name: String) -> Int? { args[name]?.lenientIntValue }

    /// Returns the argument as a bool (bools, 0/1, or "true"/"false" strings).
    public func bool(_ name: String) -> Bool? { args[name]?.lenientBoolValue }

    /// Returns the argument as a double.
    public func double(_ name: String) -> Double? {
        switch args[name] {
        case .number(let d)?: return d
        case .string(let s)?: return Double(s)
        default: return nil
        }
    }

    /// Returns the argument as a `Direction` ("left"/"right"/"up"/"down", also l/r/u/d).
    public func direction(_ name: String) -> Direction? {
        guard let s = string(name)?.lowercased() else { return nil }
        switch s {
        case "l": return .left
        case "r": return .right
        case "u": return .up
        case "d": return .down
        default: return Direction(rawValue: s)
        }
    }

    /// Validates the request against the catalog: unknown commands and missing required
    /// arguments produce a human-readable message, `nil` means the request is well-formed.
    public func validationError() -> String? {
        guard let cmd = knownCommand else {
            return "Unknown command '\(command)'. Run `skyrose help` for the list."
        }
        let missing = cmd.spec.arguments.filter { $0.required && args[$0.name] == nil }.map(\.name)
        if !missing.isEmpty {
            return "Command '\(command)' is missing required argument(s): \(missing.joined(separator: ", "))"
        }
        return nil
    }
}

/// A response from the WM. `ok == false` carries an `error` message; `ok == true` carries an
/// optional `result`. `protocolVersion` lets clients detect a stale WM or CLI.
public struct IPCResponse: Codable, Hashable, Sendable {
    public var id: Int
    public var ok: Bool
    public var result: JSONValue?
    public var error: String?
    public var protocolVersion: Int

    public init(id: Int, ok: Bool, result: JSONValue? = nil, error: String? = nil, protocolVersion: Int = CaelestiaVersion.protocolVersion) {
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
        self.protocolVersion = protocolVersion
    }

    /// A successful response with an optional payload.
    public static func success(id: Int, result: JSONValue? = nil) -> IPCResponse {
        IPCResponse(id: id, ok: true, result: result)
    }

    /// A successful response for a request, encoding any `Encodable` payload.
    public static func success<T: Encodable>(for request: IPCRequest, encoding value: T) -> IPCResponse {
        do {
            return IPCResponse(id: request.id, ok: true, result: try JSONValue(encoding: value))
        } catch {
            return failure(id: request.id, error: "Failed to encode result: \(error)")
        }
    }

    /// A successful response for a request.
    public static func success(for request: IPCRequest, result: JSONValue? = nil) -> IPCResponse {
        IPCResponse(id: request.id, ok: true, result: result)
    }

    /// A failed response with a message.
    public static func failure(id: Int, error: String) -> IPCResponse {
        IPCResponse(id: id, ok: false, error: error)
    }

    /// A failed response for a request.
    public static func failure(for request: IPCRequest, error: String) -> IPCResponse {
        IPCResponse(id: request.id, ok: false, error: error)
    }

    private enum CodingKeys: String, CodingKey { case id, ok, result, error, protocolVersion }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        ok = try c.decode(Bool.self, forKey: .ok)
        let r = try c.decodeIfPresent(JSONValue.self, forKey: .result)
        result = (r?.isNull ?? true) ? nil : r
        error = try c.decodeIfPresent(String.self, forKey: .error)
        protocolVersion = try c.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ok, forKey: .ok)
        try c.encodeIfPresent(result, forKey: .result)
        try c.encodeIfPresent(error, forKey: .error)
        try c.encode(protocolVersion, forKey: .protocolVersion)
    }
}

/// The payload of the `hello` handshake.
public struct IPCHello: Codable, Hashable, Sendable {
    public var version: String
    public var protocolVersion: Int
    public var pid: Int

    public init(version: String = CaelestiaVersion.string, protocolVersion: Int = CaelestiaVersion.protocolVersion, pid: Int = Int(ProcessInfo.processInfo.processIdentifier)) {
        self.version = version
        self.protocolVersion = protocolVersion
        self.pid = pid
    }

    public var jsonValue: JSONValue {
        ["version": .string(version), "protocolVersion": .number(Double(protocolVersion)), "pid": .number(Double(pid))]
    }
}

/// Every failure the client, server or CLI can report. Messages are written for the terminal.
public enum IPCError: Error, Equatable, Sendable, LocalizedError {
    /// No WM is listening: the socket is missing (ENOENT) or nothing accepts (ECONNREFUSED).
    case notRunning(path: String)
    /// The WM accepted the connection but did not answer in time.
    case timeout(seconds: TimeInterval)
    /// The WM speaks a different protocol version than this client.
    case protocolMismatch(local: Int, remote: Int)
    /// The WM answered `ok: false` with this message.
    case remote(String)
    /// The WM answered with something that is not a valid response line.
    case malformedResponse(String)
    /// A line exceeded `IPCWire.maxLineBytes`.
    case lineTooLong(limit: Int)
    /// The socket path does not fit in `sockaddr_un.sun_path`.
    case pathTooLong(path: String)
    /// Another live WM already answers on this socket.
    case alreadyRunning(path: String, pid: Int)
    /// A socket system call failed (`errno` text included).
    case socketError(operation: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .notRunning(let path):
            return "SkyRose WM is not running (no listener at \(path)). Start it with `skyrose shell -d`."
        case .timeout(let s):
            return "SkyRose WM did not answer within \(formatSeconds(s))."
        case .protocolMismatch(let local, let remote):
            return "Protocol mismatch: this CLI speaks v\(local) but the running WM speaks v\(remote). Restart the WM (`skyrose shell restart`) or reinstall so both match."
        case .remote(let message):
            return message
        case .malformedResponse(let detail):
            return "Malformed response from the WM: \(detail)"
        case .lineTooLong(let limit):
            return "IPC line exceeds the \(limit / 1024 / 1024) MB limit."
        case .pathTooLong(let path):
            return "Socket path is too long for a Unix socket (max 103 bytes): \(path)"
        case .alreadyRunning(let path, let pid):
            return "Another SkyRose WM (pid \(pid)) is already listening at \(path)."
        case .socketError(let op, let message):
            return "\(op) failed: \(message)"
        }
    }

    /// True for the two conditions that mean "nothing to talk to" (CLI exit code 2).
    public var isNotRunning: Bool {
        if case .notRunning = self { return true }
        return false
    }

    private func formatSeconds(_ s: TimeInterval) -> String {
        s == s.rounded() ? "\(Int(s)) s" : String(format: "%.1f s", s)
    }

    /// Builds a `socketError` from the current `errno`.
    static func errno(_ operation: String, _ code: Int32 = Darwin.errno) -> IPCError {
        .socketError(operation: operation, message: "\(String(cString: strerror(code))) (errno \(code))")
    }
}
