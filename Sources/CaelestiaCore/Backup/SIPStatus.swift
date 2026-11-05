import Foundation

/// System Integrity Protection as `csrutil status` reports it (read-only; SkyRose never changes it).
public enum SIPStatus: Equatable, Sendable {
    /// Fully on ("System Integrity Protection status: enabled.").
    case enabled
    /// On, but with some protections turned off (the Enhanced-mode configuration).
    case custom
    case disabled
    /// csrutil could not be run or printed something unexpected.
    case unknown

    /// Parses the output of `csrutil status`. Nil or empty → `.unknown`.
    public static func parse(_ output: String?) -> SIPStatus {
        guard let text = output?.lowercased(), !text.isEmpty else { return .unknown }
        // "status: unknown (Custom Configuration)." or "status: enabled (Custom Configuration)."
        // followed by the protections, some of them "disabled".
        if text.contains("custom configuration") { return .custom }
        if text.contains("status: disabled") { return .disabled }
        if text.contains("status: enabled") { return .enabled }
        return .unknown
    }

    /// Runs `/usr/bin/csrutil status` (no root needed) and returns its raw output, nil on failure.
    public static func readCSRUtil(timeout: TimeInterval = 5) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/csrutil")
        p.arguments = ["status"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning, Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return nil }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.isEmpty ? nil : text
    }
}

/// When the uninstaller shows "Turn System Integrity Protection back on".
///
/// Only when SkyRose's SIP-off (Enhanced) mode was actually used — recorded by
/// ``RestoreManifest/recordModeUsed(_:note:)`` — and SIP is not already fully back on. Never
/// otherwise: a Mac whose SIP was lowered for something else, an unreadable manifest, or a user who
/// never touched Enhanced mode gets no popup.
public enum SIPReminderDecision {
    public static func shouldShow(sipOffModeUsed: Bool, status: SIPStatus) -> Bool {
        guard sipOffModeUsed else { return false }
        return status != .enabled
    }
}

/// Whether this Mac is set up for SIP-off mode (docs/ENHANCED_MODE.md): Debugging Restrictions
/// off (the loader needs the Dock's task port), Filesystem Protections off, and on Apple Silicon
/// the `-arm64e_preview_abi` boot argument. Read-only, like everything about SIP in SkyRose.
public struct SIPOffReadiness: Equatable, Sendable {
    public var filesystemOff = false
    public var debuggingOff = false
    public var nvramOff = false
    public var bootArg = false
    public var appleSilicon = true
    public init() {}

    /// `csrutil status` output + `nvram boot-args` output.
    public static func parse(csrutil: String?, bootArgs: String?, appleSilicon: Bool = true) -> SIPOffReadiness {
        var r = SIPOffReadiness()
        r.appleSilicon = appleSilicon
        let text = (csrutil ?? "").lowercased()
        func off(_ name: String) -> Bool {
            if text.contains("status: disabled") { return true }
            return text.split(separator: "\n").contains { $0.contains(name) && $0.contains("disabled") }
        }
        r.filesystemOff = off("filesystem protections")
        r.debuggingOff = off("debugging restrictions")
        r.nvramOff = off("nvram protections")
        r.bootArg = (bootArgs ?? "").split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).contains("-arm64e_preview_abi")
        return r
    }

    public var ready: Bool { filesystemOff && debuggingOff && (bootArg || !appleSilicon) }

    /// What is still missing, in the order Recovery asks for it.
    public var missing: [String] {
        var m: [String] = []
        if !filesystemOff || !debuggingOff || !nvramOff { m.append("csrutil enable --without fs --without debug --without nvram (in Recovery)") }
        if appleSilicon, !bootArg { m.append("sudo nvram boot-args=-arm64e_preview_abi") }
        return m
    }

    public var summary: String {
        ready ? "ready (filesystem + debugging protections off" + (appleSilicon ? ", -arm64e_preview_abi set)" : ")")
            : "not ready: " + missing.joined(separator: "; ")
    }

    /// `/usr/sbin/nvram boot-args` (no root needed), nil on failure.
    public static func readBootArgs() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/nvram")
        p.arguments = ["boot-args"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    public static func current() -> SIPOffReadiness {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return parse(csrutil: SIPStatus.readCSRUtil(), bootArgs: readBootArgs(), appleSilicon: machine.hasPrefix("arm64"))
    }
}
