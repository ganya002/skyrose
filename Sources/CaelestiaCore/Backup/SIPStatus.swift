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
