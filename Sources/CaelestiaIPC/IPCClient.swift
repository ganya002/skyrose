import Darwin
import Foundation
import CaelestiaCore

/// Synchronous client for the WM socket, usable from the CLI and from tests. Each `send` opens
/// its own connection; use `IPCConnection` directly to pipeline several requests.
public struct IPCClient: Sendable {
    public var path: URL

    public init(path: URL = Paths.ipcSocket) {
        self.path = path
    }

    /// True when a socket node exists at `path` (it may still be stale; see `isRunning`).
    public var socketExists: Bool {
        var st = stat()
        return lstat(path.path, &st) == 0 && (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK)
    }

    /// True when a WM answers `hello`.
    public var isRunning: Bool {
        (try? hello(timeout: 1)) != nil
    }

    /// Sends one request and waits for its response. Throws `IPCError.notRunning` when nothing
    /// listens, `.timeout` when the WM is silent, `.protocolMismatch` when versions differ.
    /// `ok == false` responses are returned, not thrown; see `call` for the throwing variant.
    public func send(_ command: String, args: [String: JSONValue] = [:], timeout: TimeInterval = 5) throws -> IPCResponse {
        try send(IPCRequest(id: 1, command: command, args: args), timeout: timeout)
    }

    public func send(_ command: IPCCommand, args: [String: JSONValue] = [:], timeout: TimeInterval = 5) throws -> IPCResponse {
        try send(command.rawValue, args: args, timeout: timeout)
    }

    public func send(_ request: IPCRequest, timeout: TimeInterval = 5) throws -> IPCResponse {
        let connection = try IPCConnection(path: path, timeout: timeout)
        defer { connection.close() }
        return try connection.send(request)
    }

    /// Like `send`, but turns an `ok == false` response into `IPCError.remote`.
    @discardableResult
    public func call(_ command: String, args: [String: JSONValue] = [:], timeout: TimeInterval = 5) throws -> JSONValue {
        let response = try send(command, args: args, timeout: timeout)
        guard response.ok else { throw IPCError.remote(response.error ?? "Command failed") }
        return response.result ?? .null
    }

    @discardableResult
    public func call(_ command: IPCCommand, args: [String: JSONValue] = [:], timeout: TimeInterval = 5) throws -> JSONValue {
        try call(command.rawValue, args: args, timeout: timeout)
    }

    /// The handshake. Does not throw on protocol mismatch so callers can report both versions.
    public func hello(timeout: TimeInterval = 2) throws -> (version: String, protocolVersion: Int, pid: Int) {
        let connection = try IPCConnection(path: path, timeout: timeout)
        defer { connection.close() }
        let response = try connection.send(IPCRequest(id: 1, command: IPCWire.helloCommand), checkProtocol: false)
        guard response.ok, let result = response.result,
            let version = result["version"]?.stringValue,
            let proto = result["protocolVersion"]?.intValue,
            let pid = result["pid"]?.intValue
        else {
            throw IPCError.malformedResponse("hello returned \(response.result?.compactJSON ?? response.error ?? "nothing")")
        }
        return (version, proto, pid)
    }
}

/// One open connection to the WM. Requests are answered in order; the connection stays open
/// until `close()` (or deinit).
public final class IPCConnection {
    public let path: URL
    public let timeout: TimeInterval
    private var fd: Int32
    private var inbox: [UInt8] = []
    private var nextID = 1

    /// Connects, mapping ENOENT/ECONNREFUSED to `IPCError.notRunning`.
    public init(path: URL, timeout: TimeInterval = 5) throws {
        self.path = path
        self.timeout = timeout
        let p = path.path
        var addr = try SocketSupport.address(for: p)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.errno("socket") }
        SocketSupport.setCloseOnExec(fd)
        SocketSupport.setNoSigpipe(fd)
        SocketSupport.setTimeout(fd, seconds: timeout)
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, len) }
        }
        guard rc == 0 else {
            let code = errno
            Darwin.close(fd)
            switch code {
            case ENOENT, ECONNREFUSED, ENOTSOCK, ECONNRESET: throw IPCError.notRunning(path: p)
            case ETIMEDOUT, EAGAIN, EWOULDBLOCK: throw IPCError.timeout(seconds: timeout)
            default: throw IPCError.errno("connect(\(p))", code)
            }
        }
        self.fd = fd
    }

    deinit {
        close()
    }

    /// Closes the socket. Idempotent.
    public func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    public var isOpen: Bool { fd >= 0 }

    /// Sends a request (assigning a fresh id when the request's id is 0) and reads its response.
    public func send(_ request: IPCRequest, checkProtocol: Bool = true) throws -> IPCResponse {
        var req = request
        if req.id == 0 {
            req.id = nextID
            nextID += 1
        }
        let line = try IPCWire.encodeLine(req)
        let answer = try exchange(line: line)
        let response: IPCResponse
        do {
            response = try IPCWire.decodeLine(IPCResponse.self, from: answer)
        } catch {
            throw IPCError.malformedResponse(String(decoding: answer.prefix(200), as: UTF8.self))
        }
        if checkProtocol, response.protocolVersion != CaelestiaVersion.protocolVersion {
            throw IPCError.protocolMismatch(local: CaelestiaVersion.protocolVersion, remote: response.protocolVersion)
        }
        return response
    }

    /// Sends raw bytes (a newline is appended when missing) and returns the next line from the
    /// socket, newline excluded. Lets tests exercise malformed input.
    public func exchange(line: Data) throws -> Data {
        guard fd >= 0 else { throw IPCError.notRunning(path: path.path) }
        var out = line
        if out.last != IPCWire.newline { out.append(IPCWire.newline) }
        try writeAll(out)
        return try readLine()
    }

    private func writeAll(_ data: Data) throws {
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { raw -> Int in
                Darwin.write(fd, raw.baseAddress!.advanced(by: offset), data.count - offset)
            }
            if n > 0 {
                offset += n
            } else if n < 0 && errno == EINTR {
                continue
            } else if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                throw IPCError.timeout(seconds: timeout)
            } else if n < 0 && (errno == EPIPE || errno == ECONNRESET) {
                throw IPCError.notRunning(path: path.path)
            } else {
                throw IPCError.errno("write")
            }
        }
    }

    private func readLine() throws -> Data {
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            if let nl = inbox.firstIndex(of: IPCWire.newline) {
                let line = Data(inbox[0..<nl])
                inbox.removeFirst(nl + 1)
                return line
            }
            if inbox.count > IPCWire.maxLineBytes { throw IPCError.lineTooLong(limit: IPCWire.maxLineBytes) }
            let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                inbox.append(contentsOf: buf[0..<n])
            } else if n == 0 {
                throw IPCError.malformedResponse("connection closed before a response arrived")
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                throw IPCError.timeout(seconds: timeout)
            } else if errno == ECONNRESET {
                throw IPCError.notRunning(path: path.path)
            } else {
                throw IPCError.errno("read")
            }
        }
    }
}
