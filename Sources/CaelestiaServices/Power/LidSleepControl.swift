import Foundation
import CaelestiaCore

/// Reads and sets `SleepDisabled`. The real one runs `/usr/bin/pmset` and `/usr/bin/sudo -n`.
public protocol SleepSwitch: Sendable {
    /// `SleepDisabled 1` now.
    func read() -> Bool
    /// Sets it; returns nil on success, else sudo's message (helper not installed, …).
    func set(disabled: Bool) -> String?
}

/// Clamshell Toggle's `Power.swift`, ported: `pmset -g` to read, `sudo -n pmset disablesleep 0|1` to
/// set. `-n` means sudo never prompts: without the scoped sudoers rule it fails at once.
/// Processes run on a private serial queue (the caller blocks on it, the main run loop is not spun).
public struct PmsetSleepSwitch: SleepSwitch {
    private static let queue = DispatchQueue(label: "skyrose.lidsleep")

    public init() {}

    public func read() -> Bool {
        let (status, out, _) = Self.run(LidSleep.pmset, ["-g"])
        return status == 0 && LidSleep.parseSleepDisabled(out)
    }

    public func set(disabled: Bool) -> String? {
        let (status, _, err) = Self.run(LidSleep.sudo, LidSleep.sudoArguments(disabled: disabled))
        if status == 0 { return nil }
        let detail = err.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? "sudo -n exited \(status)" : detail
    }

    static func run(_ path: String, _ args: [String]) -> (Int32, String, String) {
        queue.sync {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return (-1, "", error.localizedDescription) }
            let o = out.fileHandleForReading.readDataToEndOfFile()
            let e = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
        }
    }
}

/// Keeps `SleepDisabled` at 1 while Clamshell is on or a keep-awake runs, so the Mac keeps
/// running with the lid closed on battery and with only the built-in display. Back to 0 when
/// both are off, on quit and on panic, but only if SkyRose set it (the marker file), so a value
/// someone else set is not undone at start.
@MainActor
public final class LidSleepControl {
    public private(set) var status = LidSleepStatus()
    /// Last `SleepDisabled` read.
    public private(set) var sleepDisabled = false
    /// sudo's last refusal (helper missing).
    public private(set) var lastError: String?
    public var onChange: (() -> Void)?

    private let sleepSwitch: SleepSwitch
    private let marker: URL

    public init(sleepSwitch: SleepSwitch = PmsetSleepSwitch(),
                marker: URL = Paths.appSupport.appendingPathComponent("sleep-disabled-by-skyrose")) {
        self.sleepSwitch = sleepSwitch
        self.marker = marker
    }

    /// SkyRose set `SleepDisabled 1` and has not put it back yet.
    public var ownsSleepDisabled: Bool { FileManager.default.fileExists(atPath: marker.path) }

    /// The exact command the user runs once when the helper is missing.
    public var installCommand: String { LidSleep.installCommand(user: NSUserName()) }

    /// At WM start (Macs with a lid): put back a `SleepDisabled 1` a crashed SkyRose left, and find
    /// out whether the helper works (re-applies the current value, as Clamshell Toggle's installer does).
    public func start() {
        sleepDisabled = sleepSwitch.read()
        if ownsSleepDisabled, !status.wantsSleepDisabled {
            sync()
        } else {
            probeHelper()
        }
    }

    public func setClamshell(_ on: Bool) {
        guard status.clamshellOn != on else { return sync() }
        status.clamshellOn = on
        sync()
    }

    public func setKeepAwake(_ on: Bool) {
        guard status.keepAwakeOn != on else { return }
        status.keepAwakeOn = on
        sync()
    }

    /// Re-reads `SleepDisabled`; tries the helper again while it is not known to work.
    public func refresh() {
        if status.helper != .ready { probeHelper() } else { sleepDisabled = sleepSwitch.read() }
    }

    /// Makes `SleepDisabled` match what SkyRose wants. No sudo call when it already does.
    public func sync() {
        let current = sleepSwitch.read()
        sleepDisabled = current
        if status.wantsSleepDisabled {
            if !current { apply(true) } else { markOwned(true) }
        } else if ownsSleepDisabled {
            if current { apply(false) } else { markOwned(false) }
        }
        onChange?()
    }

    /// Quit: back to 0 only if SkyRose set it.
    public func releaseForQuit() {
        status.clamshellOn = false
        status.keepAwakeOn = false
        if ownsSleepDisabled, sleepSwitch.read() { apply(false) } else { markOwned(false) }
    }

    /// `wm panic`: back to 0 whoever set it (SkyRose's emergency stop leaves stock power settings).
    public func releaseForPanic() {
        status.clamshellOn = false
        status.keepAwakeOn = false
        if sleepSwitch.read() { apply(false) } else { markOwned(false) }
    }

    private func probeHelper() {
        let current = sleepSwitch.read()
        sleepDisabled = current
        record(sleepSwitch.set(disabled: current))
    }

    private func apply(_ disabled: Bool) {
        let error = sleepSwitch.set(disabled: disabled)
        record(error)
        if error == nil {
            sleepDisabled = disabled
            markOwned(disabled)
        }
    }

    private func record(_ error: String?) {
        lastError = error
        status.helper = error == nil ? .ready : .missing
        if let error { Log.services.error("sudo -n pmset disablesleep refused: \(error, privacy: .public)") }
    }

    private func markOwned(_ owned: Bool) {
        if owned {
            try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !ownsSleepDisabled { FileManager.default.createFile(atPath: marker.path, contents: Data()) }
        } else {
            try? FileManager.default.removeItem(at: marker)
        }
    }
}
