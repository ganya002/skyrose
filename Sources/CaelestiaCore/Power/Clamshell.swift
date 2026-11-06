import Foundation

/// What macOS will do with the lid closed, from facts any process can read (no root).
///
/// macOS keeps running with the lid closed only in native clamshell mode: on a power adapter AND
/// with an external display connected (an external keyboard/mouse helps waking, but is not
/// required on Apple silicon). Everything else (lid closed on battery, or without a display)
/// sleeps; overriding that needs root (`pmset disablesleep`), which SkyRose never does.
public struct ClamshellFacts: Hashable, Sendable {
    /// The Mac has a lid (IOPMrootDomain publishes `AppleClamshellState`).
    public var hasLid: Bool
    /// `AppleClamshellState`.
    public var lidClosed: Bool
    /// `AppleClamshellCausesSleep` (nil when not published): the kernel's own answer to "does
    /// closing the lid sleep now?".
    public var closingCausesSleep: Bool?
    /// Running on a power adapter.
    public var onAC: Bool
    /// Online displays that are not built in.
    public var externalDisplays: Int

    public init(hasLid: Bool, lidClosed: Bool, closingCausesSleep: Bool? = nil, onAC: Bool, externalDisplays: Int) {
        self.hasLid = hasLid
        self.lidClosed = lidClosed
        self.closingCausesSleep = closingCausesSleep
        self.onAC = onAC
        self.externalDisplays = externalDisplays
    }
}

public enum ClamshellMode: String, Sendable, Hashable, Codable {
    /// No lid (desktop Mac).
    case noLid = "no-lid"
    /// Lid open; closing it puts the Mac to sleep.
    case openWillSleep = "open-will-sleep"
    /// Lid open; closing it keeps the Mac running on the external display(s).
    case openWillStayAwake = "open-will-stay-awake"
    /// Lid closed and running: native clamshell mode.
    case closedRunning = "closed-running"
}

public enum Clamshell {
    /// Native clamshell's own conditions: AC power and at least one external display.
    public static func canRunLidClosed(_ f: ClamshellFacts) -> Bool { f.onAC && f.externalDisplays > 0 }

    public static func mode(_ f: ClamshellFacts) -> ClamshellMode {
        guard f.hasLid else { return .noLid }
        // A process only runs with the lid closed when macOS let it (clamshell mode).
        if f.lidClosed { return .closedRunning }
        // The kernel's flag wins when published (it also covers settings SkyRose cannot see);
        // otherwise the documented conditions.
        let sleeps = f.closingCausesSleep ?? !canRunLidClosed(f)
        return sleeps ? .openWillSleep : .openWillStayAwake
    }

    /// What is missing for lid-closed use (empty when nothing is). Order: power, then display.
    public static func missing(_ f: ClamshellFacts) -> [String] {
        var out: [String] = []
        if !f.onAC { out.append("a power adapter") }
        if f.externalDisplays == 0 { out.append("an external display") }
        return out
    }

    /// One line for the sidebar / CLI.
    public static func summary(_ f: ClamshellFacts) -> String {
        switch mode(f) {
        case .noLid: return "No lid"
        case .closedRunning: return "Lid closed · running on the external display"
        case .openWillStayAwake: return "Closing the lid keeps the Mac running"
        case .openWillSleep:
            let m = missing(f)
            if m.isEmpty { return "Closing the lid sleeps the Mac" }
            return "Closing the lid sleeps the Mac · needs \(m.joined(separator: " and "))"
        }
    }

    /// Whether SkyRose holds its clamshell keep-awake assertion (`clamshell.keepAwake`): only while
    /// the lid is closed in clamshell mode, so idle display sleep does not blank the external.
    public static func holdsKeepAwake(_ f: ClamshellFacts, enabled: Bool) -> Bool {
        enabled && mode(f) == .closedRunning
    }
}
