import Darwin
import Foundation
import CaelestiaCore

/// JSON-lines server on a Unix domain socket (section 4.8).
///
/// - Binds to `Paths.ipcSocket` by default (the path is injectable for tests), creating the
///   parent directory and setting the socket node to mode 0600.
/// - A left-over socket file is probed with `hello`; it is unlinked only when nothing answers.
/// - Accepts any number of clients; each connection is line-buffered (1 MB cap) and may send
///   many requests. Responses on one connection are delivered in request order.
/// - `hello` is answered by the server itself; everything else goes to `handler`, which is an
///   async closure and therefore runs on whatever actor it is isolated to (the WM's main actor).
/// - `stop()` closes every connection and unlinks the socket (only if it is still ours).
public final class IPCServer: @unchecked Sendable {
    public typealias Handler = @Sendable (IPCRequest) async -> IPCResponse

    /// `sockaddr_un.sun_path` holds 104 bytes on macOS including the terminator.
    public static let maxPathLength = 103
    public static let listenBacklog: Int32 = 16

    public let path: URL
    /// When true (default), unknown commands and missing required arguments are rejected by the
    /// server before the handler sees them (see `IPCRequest.validationError()`).
    public let validatesRequests: Bool

    private let handler: Handler
    private let queue = DispatchQueue(label: "com.caelestia.mac.ipc.server")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int: Connection] = [:]
    private var nextConnectionID = 0
    private var running = false
    private var boundInode: (dev: dev_t, ino: ino_t)?

    public init(path: URL = Paths.ipcSocket, validatesRequests: Bool = true, handler: @escaping Handler) {
        self.path = path
        self.validatesRequests = validatesRequests
        self.handler = handler
        queue.setSpecific(key: queueKey, value: true)
    }

    deinit {
        stop()
    }

    /// True between a successful `start()` and `stop()`.
    public var isRunning: Bool { onQueue { running } }

    /// Number of client connections currently open.
    public var connectionCount: Int { onQueue { connections.count } }

    /// Creates the socket and starts accepting. Returns once the socket is listening, so a
    /// client may connect immediately after this call.
    public func start() throws {
        try onQueue { try startLocked() }
    }

    /// Stops accepting, closes every client and removes the socket file. Safe to call twice.
    public func stop() {
        onQueue { stopLocked() }
    }

    // MARK: - Queue helpers

    private func onQueue<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            return try body()
        }
        return try queue.sync(execute: body)
    }

    // MARK: - Lifecycle (on queue)

    private func startLocked() throws {
        guard !running else { return }
        let p = path.path
        guard p.utf8.count <= IPCServer.maxPathLength else { throw IPCError.pathTooLong(path: p) }

        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try reclaimStaleSocket(at: p)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.errno("socket") }
        var ok = false
        defer { if !ok { close(fd) } }

        SocketSupport.setCloseOnExec(fd)
        SocketSupport.setNoSigpipe(fd)

        var addr = try SocketSupport.address(for: p)
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, len) }
        }
        guard bound == 0 else { throw IPCError.errno("bind(\(p))") }

        // Restrict before anyone can connect: connect() fails with ECONNREFUSED until listen().
        guard chmod(p, 0o600) == 0 else {
            let e = IPCError.errno("chmod(\(p))")
            unlink(p)
            throw e
        }
        var st = stat()
        if stat(p, &st) == 0 { boundInode = (st.st_dev, st.st_ino) }

        guard Darwin.listen(fd, IPCServer.listenBacklog) == 0 else {
            let e = IPCError.errno("listen")
            unlink(p)
            throw e
        }
        SocketSupport.setNonBlocking(fd)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { close(fd) }
        source.resume()

        listenFD = fd
        acceptSource = source
        running = true
        ok = true
        Log.ipc.info("IPC server listening at \(p, privacy: .public)")
    }

    private func stopLocked() {
        guard running else { return }
        running = false
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1
        for c in connections.values { c.close() }
        connections.removeAll()
        unlinkIfOurs()
        Log.ipc.info("IPC server stopped")
    }

    /// Removes the socket file unless another process has since bound a new socket there.
    private func unlinkIfOurs() {
        let p = path.path
        var st = stat()
        guard stat(p, &st) == 0 else { return }
        if let ours = boundInode, ours.dev != st.st_dev || ours.ino != st.st_ino { return }
        unlink(p)
        boundInode = nil
    }

    /// Probes an existing socket file: a live server makes `start()` fail with
    /// `alreadyRunning`; anything that does not answer `hello` is stale and gets unlinked.
    private func reclaimStaleSocket(at p: String) throws {
        var st = stat()
        guard lstat(p, &st) == 0 else { return }
        guard (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK) else {
            throw IPCError.socketError(operation: "bind", message: "\(p) exists and is not a socket; move it out of the way")
        }
        if let hello = try? IPCClient(path: path).hello(timeout: 1.0) {
            throw IPCError.alreadyRunning(path: p, pid: hello.pid)
        }
        Log.ipc.notice("Replacing stale IPC socket at \(p, privacy: .public)")
        guard unlink(p) == 0 || errno == ENOENT else { throw IPCError.errno("unlink(\(p))") }
    }

    // MARK: - Accepting

    private func acceptPending() {
        while running {
            let fd = Darwin.accept(listenFD, nil, nil)
            if fd < 0 {
                switch errno {
                case EINTR: continue
                case EAGAIN, EWOULDBLOCK: return
                default:
                    Log.ipc.error("accept failed: \(String(cString: strerror(errno)), privacy: .public)")
                    return
                }
            }
            SocketSupport.setCloseOnExec(fd)
            SocketSupport.setNoSigpipe(fd)
            SocketSupport.setNonBlocking(fd)
            nextConnectionID += 1
            let conn = Connection(id: nextConnectionID, fd: fd, queue: queue, validates: validatesRequests, handler: handler)
            conn.onClose = { [weak self] id in self?.connections.removeValue(forKey: id) }
            connections[conn.id] = conn
            conn.start()
        }
    }
}

// MARK: - Connection

extension IPCServer {
    /// One accepted client. All state is touched on the server queue; the handler runs in a
    /// task chain so responses go out in request order.
    final class Connection: @unchecked Sendable {
        let id: Int
        private let fd: Int32
        private let queue: DispatchQueue
        private let validates: Bool
        private let handler: Handler
        private var readSource: DispatchSourceRead?
        private var writeSource: DispatchSourceWrite?
        private var inbox: [UInt8] = []
        private var outbox: [UInt8] = []
        private var chain: Task<Void, Never>?
        private var closed = false
        private var closeWhenFlushed = false
        private var liveSources = 0
        var onClose: ((Int) -> Void)?

        init(id: Int, fd: Int32, queue: DispatchQueue, validates: Bool, handler: @escaping Handler) {
            self.id = id
            self.fd = fd
            self.queue = queue
            self.validates = validates
            self.handler = handler
        }

        func start() {
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.readable() }
            // Strong capture on purpose: the connection must outlive its sources so the fd is
            // closed exactly once, after Dispatch has stopped using it.
            source.setCancelHandler { self.sourceDidCancel() }
            liveSources += 1
            readSource = source
            source.resume()
        }

        /// Closes immediately (pending output is dropped).
        func close() {
            guard !closed else { return }
            closed = true
            chain?.cancel()
            chain = nil
            writeSource?.cancel()
            readSource?.cancel()
            if liveSources == 0 { Darwin.close(fd) }
            onClose?(id)
            onClose = nil
        }

        private func sourceDidCancel() {
            liveSources -= 1
            if liveSources == 0 { Darwin.close(fd) }
        }

        // MARK: Reading

        private func readable() {
            guard !closed else { return }
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = buf.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                if n > 0 {
                    inbox.append(contentsOf: buf[0..<n])
                    if n < buf.count { break }
                } else if n == 0 {
                    close()
                    return
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    break
                } else {
                    close()
                    return
                }
            }
            processLines()
        }

        private func processLines() {
            while let nl = inbox.firstIndex(of: IPCWire.newline) {
                let line = Array(inbox[0..<nl])
                inbox.removeFirst(nl + 1)
                if line.count > IPCWire.maxLineBytes {
                    rejectOversized()
                    return
                }
                handle(line: line)
            }
            if inbox.count > IPCWire.maxLineBytes { rejectOversized() }
        }

        private func rejectOversized() {
            inbox.removeAll()
            send(.failure(id: 0, error: IPCError.lineTooLong(limit: IPCWire.maxLineBytes).localizedDescription))
            closeWhenFlushed = true
            flush()
        }

        private func handle(line: [UInt8]) {
            if line.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) { return }
            let request: IPCRequest
            do {
                request = try IPCWire.decodeLine(IPCRequest.self, from: Data(line))
            } catch {
                send(.failure(id: 0, error: "Malformed request: \(describe(error))"))
                return
            }
            if request.command == IPCWire.helloCommand {
                enqueue(request) { req in .success(for: req, result: IPCHello().jsonValue) }
                return
            }
            if validates, let problem = request.validationError() {
                send(.failure(for: request, error: problem))
                return
            }
            enqueue(request, handler)
        }

        private func describe(_ error: Error) -> String {
            if let d = error as? DecodingError {
                switch d {
                case .keyNotFound(let k, _): return "missing key '\(k.stringValue)'"
                case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx), .dataCorrupted(let ctx): return ctx.debugDescription
                @unknown default: return String(describing: d)
                }
            }
            return String(describing: error)
        }

        private func enqueue(_ request: IPCRequest, _ run: @escaping Handler) {
            let previous = chain
            chain = Task { [weak self] in
                await previous?.value
                if Task.isCancelled { return }
                let response = await run(request)
                guard let self else { return }
                self.queue.async { self.send(response) }
            }
        }

        // MARK: Writing

        private func send(_ response: IPCResponse) {
            guard !closed else { return }
            do {
                outbox.append(contentsOf: try IPCWire.encodeLine(response))
            } catch {
                let fallback = "{\"id\":\(response.id),\"ok\":false,\"error\":\"Failed to encode response\",\"protocolVersion\":\(CaelestiaVersion.protocolVersion)}\n"
                outbox.append(contentsOf: Array(fallback.utf8))
            }
            flush()
        }

        private func flush() {
            while !outbox.isEmpty {
                let n = outbox.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
                if n > 0 {
                    outbox.removeFirst(n)
                } else if n < 0 && errno == EINTR {
                    continue
                } else if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    armWriteSource()
                    return
                } else {
                    close()
                    return
                }
            }
            disarmWriteSource()
            if closeWhenFlushed { close() }
        }

        private func armWriteSource() {
            if writeSource != nil { return }
            let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.flush() }
            source.setCancelHandler { self.sourceDidCancel() }
            liveSources += 1
            writeSource = source
            source.resume()
        }

        private func disarmWriteSource() {
            guard let s = writeSource else { return }
            writeSource = nil
            s.cancel()
        }
    }
}

// MARK: - Socket helpers shared by server and client

enum SocketSupport {
    static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
    }

    static func setCloseOnExec(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    static func setNoSigpipe(_ fd: Int32) {
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    }

    static func setTimeout(_ fd: Int32, seconds: TimeInterval) {
        let clamped = max(0.001, seconds)
        var tv = timeval(tv_sec: Int(clamped), tv_usec: Int32((clamped - floor(clamped)) * 1_000_000))
        let len = socklen_t(MemoryLayout<timeval>.size)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, len)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, len)
    }

    /// Builds a `sockaddr_un` for a filesystem path.
    static func address(for path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { throw IPCError.pathTooLong(path: path) }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return addr
    }
}
