import Foundation

/// What macOS will do with the lid closed, from facts any process can read (no root).
///
/// Two ways a Mac keeps running with the lid closed:
/// - **native** clamshell mode: on a power adapter AND with an external display connected;
/// - **sleep disabled** (`pmset disablesleep 1`, `SleepDisabled 1`): on battery and with only the
///   built-in display too. SkyRose sets it through a scoped, passwordless sudo rule ("the helper",
///   see `LidSleep`) while Clamshell or a keep-awake is on, the same way Clamshell Toggle does.
public struct ClamshellFacts: Hashable, Sendable {
    /// The Mac has a lid (IOPMrootDomain publishes `AppleClamshellState`).
    public var hasLid: Bool
    /// `AppleClamshellState`.
    public var lidClosed: Bool
    /// `AppleClamshellCausesSleep` (nil when not published): the kernel's answer to "does closing
    /// the lid sleep now?" for native clamshell. It stays `true` with sleep disabled, so
    /// `sleepDisabled` wins over it.
    public var closingCausesSleep: Bool?
    /// Running on a power adapter.
    public var onAC: Bool
    /// Online displays that are not built in.
    public var externalDisplays: Int
    /// `SleepDisabled 1` (pmset / IOPMrootDomain): the Mac does not sleep at all, lid closed included.
    public var sleepDisabled: Bool

    public init(hasLid: Bool, lidClosed: Bool, closingCausesSleep: Bool? = nil, onAC: Bool, externalDisplays: Int, sleepDisabled: Bool = false) {
        self.hasLid = hasLid
        self.lidClosed = lidClosed
        self.closingCausesSleep = closingCausesSleep
        self.onAC = onAC
        self.externalDisplays = externalDisplays
        self.sleepDisabled = sleepDisabled
    }
}

public enum ClamshellMode: String, Sendable, Hashable, Codable {
    /// No lid (desktop Mac).
    case noLid = "no-lid"
    /// Lid open; closing it puts the Mac to sleep.
    case openWillSleep = "open-will-sleep"
    /// Lid open; closing it keeps the Mac running (native clamshell or sleep disabled).
    case openWillStayAwake = "open-will-stay-awake"
    /// Lid closed and running.
    case closedRunning = "closed-running"
}

/// Why the Mac stays up with the lid closed.
public enum ClamshellVia: String, Sendable, Hashable, Codable {
    /// macOS's own clamshell mode (power adapter + external display).
    case native
    /// `SleepDisabled 1`: works on battery and with only the built-in display.
    case sleepDisabled = "sleep-disabled"
}

/// Whether SkyRose can switch `pmset disablesleep` without a password.
public enum LidSleepHelper: String, Sendable, Hashable, Codable {
    /// Not tried yet.
    case unknown
    /// `sudo -n /usr/bin/pmset disablesleep 0|1` works (an existing /etc/sudoers.d rule).
    case ready
    /// `sudo -n` refused: the scoped sudoers rule is not installed. SkyRose never asks for a password.
    case missing
}

/// What SkyRose wants from `disablesleep` and whether it can get it.
public struct LidSleepStatus: Hashable, Sendable {
    /// `skyrose clamshell on` / the sidebar's Clamshell chip.
    public var clamshellOn: Bool
    /// A keep-awake (timed or not) is running: it survives closing the lid too.
    public var keepAwakeOn: Bool
    public var helper: LidSleepHelper

    public init(clamshellOn: Bool = false, keepAwakeOn: Bool = false, helper: LidSleepHelper = .unknown) {
        self.clamshellOn = clamshellOn
        self.keepAwakeOn = keepAwakeOn
        self.helper = helper
    }

    /// SkyRose wants `SleepDisabled 1`.
    public var wantsSleepDisabled: Bool { clamshellOn || keepAwakeOn }
}

public enum Clamshell {
    /// Native clamshell's own conditions: AC power and at least one external display.
    public static func canRunLidClosedNatively(_ f: ClamshellFacts) -> Bool { f.onAC && f.externalDisplays > 0 }

    public static func mode(_ f: ClamshellFacts) -> ClamshellMode {
        guard f.hasLid else { return .noLid }
        // A process only runs with the lid closed when macOS let it.
        if f.lidClosed { return .closedRunning }
        if f.sleepDisabled { return .openWillStayAwake }
        // The kernel's flag wins when published (it also covers settings SkyRose cannot see);
        // otherwise the documented conditions.
        let sleeps = f.closingCausesSleep ?? !canRunLidClosedNatively(f)
        return sleeps ? .openWillSleep : .openWillStayAwake
    }

    /// How the Mac stays up lid-closed (nil when it would sleep, or has no lid).
    public static func via(_ f: ClamshellFacts) -> ClamshellVia? {
        switch mode(f) {
        case .noLid, .openWillSleep: return nil
        case .openWillStayAwake, .closedRunning: return f.sleepDisabled ? .sleepDisabled : .native
        }
    }

    /// One line for the sidebar / CLI.
    public static func summary(_ f: ClamshellFacts, lid: LidSleepStatus = LidSleepStatus()) -> String {
        switch mode(f) {
        case .noLid:
            return "No lid"
        case .closedRunning:
            if f.externalDisplays > 0 { return "Lid closed · running on the external display" }
            return "Lid closed · running" + (f.onAC ? "" : " on battery")
        case .openWillStayAwake:
            guard f.sleepDisabled else { return "Closing the lid keeps the Mac running" }
            if lid.clamshellOn { return "Closing the lid keeps the Mac running · Clamshell on" }
            if lid.keepAwakeOn { return "Closing the lid keeps the Mac running · Keep awake on" }
            return "Closing the lid keeps the Mac running · sleep turned off outside SkyRose"
        case .openWillSleep:
            if lid.wantsSleepDisabled, lid.helper == .missing {
                return "Closing the lid sleeps the Mac · Clamshell needs its helper (skyrose clamshell helper)"
            }
            return "Closing the lid sleeps the Mac · turn on Clamshell to keep it running"
        }
    }

    /// Whether SkyRose holds its clamshell keep-awake assertion (`clamshell.keepAwake`): only while
    /// the lid is closed, so idle display sleep does not blank the external.
    public static func holdsKeepAwake(_ f: ClamshellFacts, enabled: Bool) -> Bool {
        enabled && mode(f) == .closedRunning
    }
}

/// The `pmset disablesleep` switch, ported from Clamshell Toggle's `Power.swift`: read
/// `SleepDisabled` from `pmset -g`, set it with `sudo -n /usr/bin/pmset disablesleep 0|1` (never an
/// interactive sudo), allowed by a scoped sudoers rule the user installs once.
public enum LidSleep {
    public static let pmset = "/usr/bin/pmset"
    public static let sudo = "/usr/bin/sudo"
    /// Rule files that grant the two commands: Clamshell Toggle's, then SkyRose's own copy.
    public static let existingRuleFile = "/etc/sudoers.d/clamshell"
    public static let ruleFile = "/etc/sudoers.d/skyrose"

    /// `sudo` arguments for one switch.
    public static func sudoArguments(disabled: Bool) -> [String] {
        ["-n", pmset, "disablesleep", disabled ? "1" : "0"]
    }

    /// `SleepDisabled 1` in `pmset -g` output.
    public static func parseSleepDisabled(_ pmsetOutput: String) -> Bool {
        pmsetOutput.range(of: "SleepDisabled[[:space:]]+1", options: .regularExpression) != nil
    }

    /// The sudoers line: only these two exact commands, as root, without a password.
    public static func rule(user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: \(pmset) disablesleep 0, \(pmset) disablesleep 1"
    }

    /// What the user runs once in a terminal to install the helper (SkyRose never does).
    /// Writes the rule to a temp file, validates it with `visudo -cf`, installs it root:wheel 0440.
    public static func installCommand(user: String) -> String {
        let safe = user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
        let line = safe ? "'\(rule(user: user))'" : "\"$(id -un) ALL=(root) NOPASSWD: \(pmset) disablesleep 0, \(pmset) disablesleep 1\""
        let tmp = "/tmp/skyrose-sudoers"
        return "printf '%s\\n' \(line) > \(tmp) && /usr/sbin/visudo -cf \(tmp) && sudo install -o root -g wheel -m 0440 \(tmp) \(ruleFile) && sudo /usr/sbin/visudo -cf \(ruleFile) && rm \(tmp)"
    }

    /// Removing SkyRose's copy (not Clamshell Toggle's) after restoring sleep.
    public static let uninstallCommand = "sudo \(pmset) disablesleep 0 && sudo rm -f \(ruleFile)"
}
