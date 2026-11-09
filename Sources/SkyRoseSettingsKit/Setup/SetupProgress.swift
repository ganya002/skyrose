import Foundation

/// One line of the `--progress` protocol spoken by `scripts/uninstall.sh` and
/// `scripts/install-release.sh`: `::stage N TOTAL id label`, `::done text`, `::skip text`,
/// `::left text`, `::fail text`, `::dry command`, `::sip`, `::finished`. After `::sip` the engine
/// reads one stdin line and keeps going only when it is `ack` (sent when the reminder is
/// dismissed). Anything else is plain output (kept for the log).
public enum SetupEvent: Equatable, Sendable {
    case stage(index: Int, total: Int, id: String, label: String)
    case item(SetupItem)
    case sip
    case finished
    case other(String)

    public static func parse(_ raw: String) -> SetupEvent {
        let line = raw.trimmingCharacters(in: .newlines)
        guard line.hasPrefix("::") else { return .other(line) }
        let body = line.dropFirst(2)
        let word = body.prefix { $0 != " " }
        let rest = body.dropFirst(word.count).drop { $0 == " " }
        switch word {
        case "stage":
            let parts = rest.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 3, let i = Int(parts[0]), let n = Int(parts[1]) else { return .other(line) }
            return .stage(index: i, total: n, id: parts[2], label: parts.count > 3 ? parts[3] : parts[2])
        case "done": return .item(SetupItem(kind: .done, text: String(rest)))
        case "skip": return .item(SetupItem(kind: .skip, text: String(rest)))
        case "left": return .item(SetupItem(kind: .left, text: String(rest)))
        case "fail": return .item(SetupItem(kind: .fail, text: String(rest)))
        case "dry": return .item(SetupItem(kind: .dry, text: String(rest)))
        case "sip": return .sip
        case "finished": return .finished
        default: return .other(line)
        }
    }
}

/// A result line: done, skipped, left for the user, failed, or (dry run) a command not run.
public struct SetupItem: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case done, skip, left, fail, dry }
    public var kind: Kind
    public var text: String
    public var id: String { kind.rawValue + "|" + text }

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// The engine's own stage (one `::stage` line) and what it reported.
public struct EngineStage: Equatable, Sendable {
    public var index: Int
    public var id: String
    public var label: String
    public var items: [SetupItem] = []
}

/// Everything the window shows comes from here: reduced from the engine's lines, nothing timed.
public struct SetupProgressState: Equatable, Sendable {
    public var total = 0
    public var stages: [EngineStage] = []
    public var finished = false
    public var sipReminder = false
    public var output: [String] = []

    public init() {}

    public mutating func apply(_ e: SetupEvent) {
        switch e {
        case let .stage(i, n, id, label):
            total = max(total, n)
            stages.append(EngineStage(index: i, id: id, label: label))
        case .item(let item):
            if stages.isEmpty { stages.append(EngineStage(index: 0, id: "plan", label: "Getting ready")) }
            stages[stages.count - 1].items.append(item)
        case .sip: sipReminder = true
        case .finished: finished = true
        case .other(let s): if !s.isEmpty { output.append(s) }
        }
    }

    public var current: EngineStage? { stages.last }
    public var items: [SetupItem] { stages.flatMap(\.items) }
    public func items(_ kind: SetupItem.Kind) -> [SetupItem] { items.filter { $0.kind == kind } }

    /// 0…1. A stage counts once the next one starts; inside a stage each reported item moves
    /// the bar a little (never past 90 % of the stage), so long stages still show movement.
    public var fraction: Double {
        if finished { return 1 }
        guard total > 0, let cur = current, cur.index > 0 else { return 0 }
        let inside = min(0.9, Double(cur.items.count) * 0.2 + 0.1)
        return min(0.99, (Double(cur.index - 1) + inside) / Double(total))
    }
}

/// A stage of the window (fewer and plainer than the engine's): the engine stage ids that belong
/// to it decide when it is active and when it is done.
public struct SetupStep: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var icon: String
    public var engineStages: Set<String>

    public init(_ id: String, _ title: String, icon: String, engine: Set<String> = []) {
        self.id = id
        self.title = title
        self.icon = icon
        engineStages = engine
    }
}

public enum SetupStepState: Equatable, Sendable { case pending, active, done, failed }

public enum SetupFlow {
    /// confirm → restore settings → remove profile bits → trash apps → report.
    public static let uninstall: [SetupStep] = [
        SetupStep("confirm", "Confirm", icon: "questionmark.circle"),
        SetupStep("restore", "Restore settings", icon: "arrow.uturn.backward", engine: ["windows", "cursor", "settings", "sleep", "login"]),
        SetupStep("profile", "Remove profile bits", icon: "person.crop.circle.badge.minus", engine: ["profile"]),
        SetupStep("apps", "Trash the apps", icon: "trash", engine: ["sip", "apps", "data"]),
        SetupStep("report", "Report", icon: "checklist"),
    ]

    /// welcome → requirements → download → place → optional bits → done.
    public static let install: [SetupStep] = [
        SetupStep("welcome", "Welcome", icon: "sparkles"),
        SetupStep("check", "This Mac", icon: "checkmark.seal", engine: ["check"]),
        SetupStep("download", "Download", icon: "arrow.down.circle", engine: ["download", "verify"]),
        SetupStep("place", "Install", icon: "square.and.arrow.down", engine: ["place"]),
        SetupStep("optional", "Options", icon: "terminal", engine: ["optional", "permissions"]),
        SetupStep("done", "Done", icon: "checkmark.circle", engine: ["done"]),
    ]

    /// Where `progress` is in `steps`: the first step is the choice screen (before the engine
    /// runs), the last one the report (after `::finished`).
    public static func activeIndex(_ steps: [SetupStep], progress: SetupProgressState, started: Bool) -> Int {
        guard started else { return 0 }
        if progress.finished { return steps.count - 1 }
        guard let cur = progress.current?.id else { return min(1, steps.count - 1) }
        return steps.firstIndex { $0.engineStages.contains(cur) } ?? min(1, steps.count - 1)
    }

    public static func state(of index: Int, active: Int, failed: Bool, finished: Bool) -> SetupStepState {
        if finished && index == active { return failed ? .failed : .done }
        if index < active { return .done }
        if index == active { return failed ? .failed : .active }
        return .pending
    }
}
