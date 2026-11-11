import CoreGraphics
import Darwin
import Foundation

/// What the scripting addition in the Dock can do (its `hello` reply). Each capability is a set
/// of SkyLight symbols the payload found; a macOS update that drops one only drops that entry.
public struct SACapabilities: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let alpha = SACapabilities(rawValue: 1 << 0)
    public static let shadow = SACapabilities(rawValue: 1 << 1)
    public static let level = SACapabilities(rawValue: 1 << 2)
    public static let transform = SACapabilities(rawValue: 1 << 3)
    public static let space = SACapabilities(rawValue: 1 << 4)

    public static let names: [(String, SACapabilities)] = [
        ("alpha", .alpha), ("shadow", .shadow), ("level", .level), ("transform", .transform), ("space", .space),
    ]
    public var names: [String] { Self.names.filter { contains($0.1) }.map(\.0) }
}

/// The text protocol of `Packaging/sa/payload.c`, as pure functions (tests cover them).
public enum SAProtocol {
    /// The protocol version this build speaks; another version is treated as not loaded.
    public static let version = "1"

    public struct Hello: Equatable, Sendable {
        public var version: String
        public var capabilities: SACapabilities
    }

    /// "ok skyrose-sa 1 alpha,shadow,level" → Hello; anything else → nil.
    public static func parseHello(_ line: String) -> Hello? {
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count >= 3, parts[0] == "ok", parts[1] == "skyrose-sa" else { return nil }
        var caps: SACapabilities = []
        if parts.count >= 4 {
            for name in parts[3].split(separator: ",") {
                if let c = SACapabilities.names.first(where: { $0.0 == name })?.1 { caps.insert(c) }
            }
        }
        return Hello(version: parts[2], capabilities: caps)
    }

    /// One window shown in `rect` (global top-left points), optionally at `alpha`.
    public struct Visual: Equatable, Sendable {
        public var id: CGWindowID
        public var rect: CGRect
        public var alpha: Double?
        public init(id: CGWindowID, rect: CGRect, alpha: Double? = nil) {
            self.id = id
            self.rect = rect
            self.alpha = alpha
        }
    }

    public static func visualLine(_ visuals: [Visual]) -> String {
        "visual " + visuals.map { v in
            var s = "\(v.id) \(fmt(v.rect.minX)) \(fmt(v.rect.minY)) \(fmt(v.rect.width)) \(fmt(v.rect.height))"
            if let a = v.alpha { s += " \(fmt(min(1, max(0, a)), digits: 3))" }
            return s
        }.joined(separator: ";")
    }

    static func fmt(_ v: Double, digits: Int = 2) -> String {
        String(format: "%.\(digits)f", v)
    }

    /// The `sudo` line that loads the SA (the loader takes no arguments).
    public static func loadCommand(loader: URL) -> String {
        "sudo " + shellQuote(loader.path)
    }

    public static func shellQuote(_ s: String) -> String {
        s.allSatisfy({ $0.isLetter || $0.isNumber || "/._-+".contains($0) }) ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The window transform that shows a window whose real bounds are `bounds` in `visual`
    /// (window server convention: screen point → window point). Mirrors payload.c.
    public static func transform(bounds: CGRect, visual: CGRect) -> CGAffineTransform {
        let sx = bounds.width / visual.width, sy = bounds.height / visual.height
        return CGAffineTransform(a: sx, b: 0, c: 0, d: sy, tx: -visual.minX * sx, ty: -visual.minY * sy)
    }
}

/// A connection to the scripting addition's socket. Synchronous and short: every call has a
/// 250 ms timeout, and any failure closes the connection (callers then fall back to SIP-on paths).
public final class SAClient: @unchecked Sendable {
    public static func socketPath(uid: uid_t = getuid()) -> String { "/tmp/skyrose-sa-\(uid).socket" }

    /// While this file exists the boot daemon leaves the Dock alone. /tmp is emptied at boot, so a
    /// panic lasts for this session only.
    public static func pausePath(uid: uid_t = getuid()) -> String { "/tmp/skyrose-sa-paused-\(uid)" }
    public static let daemonPlist = "/Library/LaunchDaemons/com.skyrose.sa-loader.plist"
    /// The root-owned copy the boot daemon runs.
    public static let daemonLoader = URL(fileURLWithPath: "/Library/Application Support/SkyRose/skyrose-sa-loader")
    public static var daemonInstalled: Bool { FileManager.default.fileExists(atPath: daemonPlist) }

    /// The sudo line that installs or removes the boot daemon, next to `loader`.
    public static func daemonCommand(_ script: String, loader: URL) -> String {
        "sudo " + SAProtocol.shellQuote(loader.deletingLastPathComponent().appendingPathComponent(script).path)
    }

    /// The loader and payload inside SkyRose.app (`Contents/Resources/sa/`).
    public static func bundledLoader(appBundle: URL? = nil) -> URL? {
        let candidates: [URL] = [
            appBundle, Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL : nil,
        ].compactMap { $0 }.map { $0.appendingPathComponent("Contents/Resources/sa/skyrose-sa-loader") }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private let path: String
    private var fd: Int32 = -1
    private var buffer = Data()
    public private(set) var hello: SAProtocol.Hello?

    public init(path: String = SAClient.socketPath()) {
        self.path = path
    }

    deinit { close() }

    public var isConnected: Bool { fd >= 0 }

    /// Connects and says hello. Nil when the SA is not loaded, speaks another version or does
    /// not answer.
    @discardableResult
    public func connect() -> SAProtocol.Hello? {
        close()
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { Darwin.close(s); return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { Darwin.close(s); return nil }
        fd = s
        guard let reply = send("hello"), let h = SAProtocol.parseHello(reply), h.version == SAProtocol.version else {
            close()
            return nil
        }
        hello = h
        return h
    }

    public func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
        buffer.removeAll()
        hello = nil
    }

    /// Sends one command line and returns the reply line (nil on any failure; then disconnected).
    @discardableResult
    public func send(_ line: String) -> String? {
        guard fd >= 0 else { return nil }
        let data = Array((line + "\n").utf8)
        var off = 0
        while off < data.count {
            let n = data[off...].withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n <= 0 { close(); return nil }
            off += n
        }
        var chunk = [UInt8](repeating: 0, count: 1024)
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let reply = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...nl)
                return reply
            }
            let n = chunk.withUnsafeMutableBufferPointer { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n <= 0 { close(); return nil }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }

    /// True when the reply starts with "ok".
    @discardableResult
    public func command(_ line: String) -> Bool { send(line)?.hasPrefix("ok") == true }

    public func setAlpha(_ id: CGWindowID, _ alpha: Double) -> Bool { command("alpha \(id) \(SAProtocol.fmt(alpha, digits: 3))") }
    public func setShadow(_ id: CGWindowID, _ on: Bool) -> Bool { command("shadow \(id) \(on ? 1 : 0)") }
    public func setLevel(_ id: CGWindowID, _ level: Int) -> Bool { command("level \(id) \(level)") }
    public func resetLevel(_ id: CGWindowID) -> Bool { command("level-reset \(id)") }
    public func visual(_ visuals: [SAProtocol.Visual]) -> Bool { visuals.isEmpty || command(SAProtocol.visualLine(visuals)) }
    public func visualReset(_ ids: [CGWindowID]) -> Bool { ids.isEmpty || command("visual-reset " + ids.map(String.init).joined(separator: " ")) }
    public func moveToSpace(_ id: CGWindowID, space: String = "current") -> Bool { command("space \(id) \(space)") }
    public func info(_ id: CGWindowID) -> String? { send("info \(id)") }
    /// Undoes every change the SA made (any client).
    public func reset() -> Bool { command("reset") }
    /// Reset + the SA closes its socket (it stays loaded but idle until the next load).
    public func stop() -> Bool { command("stop") }
}
