import Foundation
import CaelestiaCore

/// Reference to a workspace inside window and monitor entries (`hyprctl` `workspace` object).
public struct WorkspaceRef: Codable, Hashable, Sendable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    /// Hyprland convention: special workspaces have negative ids.
    public var isSpecial: Bool { id < 0 }
}

/// Reference to the special workspace shown on a monitor; `name` is empty when none is open.
public struct SpecialWorkspaceRef: Codable, Hashable, Sendable {
    public var name: String

    public init(name: String = "") { self.name = name }

    public var isOpen: Bool { !name.isEmpty }
    public static let none = SpecialWorkspaceRef()
}

/// Decodes a JSON value that may be a string or a number into a string (`"0"` for `0`), because
/// Hyprland emits numeric monitor ids where the Mac uses display-id strings.
enum LenientString {
    static func decode<K: CodingKey>(from c: KeyedDecodingContainer<K>, key: K) throws -> String {
        if let s = try? c.decode(String.self, forKey: key) { return s }
        if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
        if let d = try? c.decode(Double.self, forKey: key) { return String(d) }
        throw DecodingError.typeMismatch(String.self, .init(codingPath: c.codingPath + [key], debugDescription: "Expected string or number"))
    }

    static func decodeIfPresent<K: CodingKey>(from c: KeyedDecodingContainer<K>, key: K) throws -> String? {
        guard c.contains(key), !(try c.decodeNil(forKey: key)) else { return nil }
        return try decode(from: c, key: key)
    }
}

/// One managed window as reported by `query.windows` (hyprctl `clients -j` compatible).
///
/// Shared with `clients.json`: `address`, `at`, `size`, `workspace{id,name}`, `floating`,
/// `pinned`, `fullscreen`, `class`, `title`, `pid`, `focusHistoryID`, `monitor`, `mapped`,
/// `hidden`, `initialClass`, `initialTitle`. Mac-only extras are optional.
public struct WindowQueryEntry: Codable, Hashable, Sendable {
    /// Window id as `0x` + lowercase hex (CGWindowID on the Mac, wlr address on Linux).
    public var address: String
    /// Top-left corner in global CG points, `[x, y]`.
    public var at: [Int]
    /// `[width, height]` in points.
    public var size: [Int]
    public var workspace: WorkspaceRef
    public var floating: Bool
    public var pinned: Bool
    /// Fullscreen mode as in Hyprland ≥ 0.42 `clients.json`: 0 = none, 1 = maximized, 2 = fullscreen.
    public var fullscreen: Int
    /// Bundle identifier (Hyprland `class`).
    public var `class`: String
    public var title: String
    public var pid: Int
    /// 0 = most recently focused, 1 = the one before, ...
    public var focusHistoryID: Int
    /// The display this window is on, as `MonitorQueryEntry.id` (string). Hyprland emits an int.
    public var monitor: String
    /// Visible to the WM (not minimized/hidden). Optional so older dumps decode.
    public var mapped: Bool?
    /// Hidden by the app (`NSApp.hide`) or minimized to the Dock.
    public var hidden: Bool?
    public var initialClass: String?
    public var initialTitle: String?
    /// Mac extras.
    public var appName: String?
    public var role: String?
    public var subrole: String?
    public var minimized: Bool?

    public init(
        address: String, at: [Int], size: [Int], workspace: WorkspaceRef, floating: Bool = false, pinned: Bool = false,
        fullscreen: Int = 0, class bundleID: String, title: String, pid: Int, focusHistoryID: Int, monitor: String,
        mapped: Bool? = true, hidden: Bool? = false, initialClass: String? = nil, initialTitle: String? = nil,
        appName: String? = nil, role: String? = nil, subrole: String? = nil, minimized: Bool? = nil
    ) {
        self.address = address
        self.at = at
        self.size = size
        self.workspace = workspace
        self.floating = floating
        self.pinned = pinned
        self.fullscreen = fullscreen
        self.class = bundleID
        self.title = title
        self.pid = pid
        self.focusHistoryID = focusHistoryID
        self.monitor = monitor
        self.mapped = mapped
        self.hidden = hidden
        self.initialClass = initialClass
        self.initialTitle = initialTitle
        self.appName = appName
        self.role = role
        self.subrole = subrole
        self.minimized = minimized
    }

    /// Formats a window id the way `address` expects.
    public static func address(for windowID: UInt32) -> String {
        "0x" + String(windowID, radix: 16)
    }

    /// Parses an `address` back into a window id (accepts `0x` prefix and decimal).
    public static func windowID(from address: String) -> UInt32? {
        let lower = address.lowercased()
        if lower.hasPrefix("0x") { return UInt32(lower.dropFirst(2), radix: 16) }
        return UInt32(lower)
    }

    public var windowID: UInt32? { WindowQueryEntry.windowID(from: address) }

    /// `at`/`size` as a rect in CG points (nil when the arrays are malformed).
    public var frame: CGRect? {
        guard at.count == 2, size.count == 2 else { return nil }
        return CGRect(x: at[0], y: at[1], width: size[0], height: size[1])
    }

    private enum CodingKeys: String, CodingKey {
        case address, at, size, workspace, floating, pinned, fullscreen, `class`, title, pid, focusHistoryID, monitor
        case mapped, hidden, initialClass, initialTitle, appName, role, subrole, minimized
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decode(String.self, forKey: .address)
        at = try c.decode([Int].self, forKey: .at)
        size = try c.decode([Int].self, forKey: .size)
        workspace = try c.decode(WorkspaceRef.self, forKey: .workspace)
        floating = try c.decode(Bool.self, forKey: .floating)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        fullscreen = try c.decodeIfPresent(Int.self, forKey: .fullscreen) ?? 0
        `class` = try c.decode(String.self, forKey: .`class`)
        title = try c.decode(String.self, forKey: .title)
        pid = try c.decode(Int.self, forKey: .pid)
        focusHistoryID = try c.decodeIfPresent(Int.self, forKey: .focusHistoryID) ?? 0
        monitor = try LenientString.decodeIfPresent(from: c, key: .monitor) ?? ""
        mapped = try c.decodeIfPresent(Bool.self, forKey: .mapped)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden)
        initialClass = try c.decodeIfPresent(String.self, forKey: .initialClass)
        initialTitle = try c.decodeIfPresent(String.self, forKey: .initialTitle)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        subrole = try c.decodeIfPresent(String.self, forKey: .subrole)
        minimized = try c.decodeIfPresent(Bool.self, forKey: .minimized)
    }
}

/// One display as reported by `query.monitors` (hyprctl `monitors -j` compatible).
///
/// Shared with `monitors.json`: `name`, `id`, `width`, `height`, `x`, `y`, `scale`, `reserved`,
/// `activeWorkspace{id,name}`, `specialWorkspace{name}`, `focused`, `description`, `refreshRate`.
public struct MonitorQueryEntry: Codable, Hashable, Sendable {
    /// Localized display name ("Built-in Retina Display", "C49RG9x").
    public var name: String
    /// Stable display id (CGDisplayCreateUUIDFromDisplayID string). Hyprland emits an int index;
    /// both decode.
    public var id: String
    /// Size in points (not pixels).
    public var width: Int
    public var height: Int
    /// Origin in global CG points (top-left space).
    public var x: Int
    public var y: Int
    /// Backing scale factor (2 on Retina).
    public var scale: Double
    /// Reserved edges `[left, top, right, bottom]` in points: menu bar, Dock, screen frame, persistent bar.
    public var reserved: [Int]
    public var activeWorkspace: WorkspaceRef
    public var specialWorkspace: SpecialWorkspaceRef
    public var focused: Bool
    public var description: String?
    public var refreshRate: Double?
    /// Mac extras.
    public var displayID: Int?
    public var primary: Bool?
    public var builtin: Bool?

    public init(
        name: String, id: String, width: Int, height: Int, x: Int, y: Int, scale: Double, reserved: [Int],
        activeWorkspace: WorkspaceRef, specialWorkspace: SpecialWorkspaceRef = .none, focused: Bool,
        description: String? = nil, refreshRate: Double? = nil, displayID: Int? = nil, primary: Bool? = nil, builtin: Bool? = nil
    ) {
        self.name = name
        self.id = id
        self.width = width
        self.height = height
        self.x = x
        self.y = y
        self.scale = scale
        self.reserved = reserved
        self.activeWorkspace = activeWorkspace
        self.specialWorkspace = specialWorkspace
        self.focused = focused
        self.description = description
        self.refreshRate = refreshRate
        self.displayID = displayID
        self.primary = primary
        self.builtin = builtin
    }

    /// The full frame in global CG points.
    public var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// `reserved` as named insets (nil when the array is malformed).
    public var reservedInsets: Insets? {
        guard reserved.count == 4 else { return nil }
        return Insets(top: Double(reserved[1]), left: Double(reserved[0]), bottom: Double(reserved[3]), right: Double(reserved[2]))
    }

    private enum CodingKeys: String, CodingKey {
        case name, id, width, height, x, y, scale, reserved, activeWorkspace, specialWorkspace, focused, description, refreshRate
        case displayID, primary, builtin
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        id = try LenientString.decode(from: c, key: .id)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        x = try c.decode(Int.self, forKey: .x)
        y = try c.decode(Int.self, forKey: .y)
        scale = try c.decode(Double.self, forKey: .scale)
        reserved = try c.decode([Int].self, forKey: .reserved)
        activeWorkspace = try c.decode(WorkspaceRef.self, forKey: .activeWorkspace)
        specialWorkspace = try c.decodeIfPresent(SpecialWorkspaceRef.self, forKey: .specialWorkspace) ?? .none
        focused = try c.decode(Bool.self, forKey: .focused)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        refreshRate = try c.decodeIfPresent(Double.self, forKey: .refreshRate)
        displayID = try c.decodeIfPresent(Int.self, forKey: .displayID)
        primary = try c.decodeIfPresent(Bool.self, forKey: .primary)
        builtin = try c.decodeIfPresent(Bool.self, forKey: .builtin)
    }
}

/// One workspace as reported by `query.workspaces` (hyprctl `workspaces -j` compatible).
public struct WorkspaceQueryEntry: Codable, Hashable, Sendable {
    public var id: Int
    public var name: String
    /// Display name (hyprctl `monitor`).
    public var monitor: String
    /// Display id (`MonitorQueryEntry.id`).
    public var monitorID: String?
    /// Number of windows on the workspace.
    public var windows: Int
    public var hasfullscreen: Bool
    /// `address` of the most recently focused window, `"0x0"` when empty.
    public var lastwindow: String
    public var lastwindowtitle: String?
    /// Mac extras: the workspace group (1-based) and whether it is the active one on its display.
    public var group: Int?
    public var active: Bool?

    public init(
        id: Int, name: String, monitor: String, monitorID: String? = nil, windows: Int, hasfullscreen: Bool = false,
        lastwindow: String = "0x0", lastwindowtitle: String? = nil, group: Int? = nil, active: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.monitor = monitor
        self.monitorID = monitorID
        self.windows = windows
        self.hasfullscreen = hasfullscreen
        self.lastwindow = lastwindow
        self.lastwindowtitle = lastwindowtitle
        self.group = group
        self.active = active
    }

    public var isSpecial: Bool { id < 0 }

    private enum CodingKeys: String, CodingKey {
        case id, name, monitor, monitorID, windows, hasfullscreen, lastwindow, lastwindowtitle, group, active
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        monitor = try c.decodeIfPresent(String.self, forKey: .monitor) ?? ""
        monitorID = try LenientString.decodeIfPresent(from: c, key: .monitorID)
        windows = try c.decodeIfPresent(Int.self, forKey: .windows) ?? 0
        hasfullscreen = try c.decodeIfPresent(Bool.self, forKey: .hasfullscreen) ?? false
        lastwindow = try c.decodeIfPresent(String.self, forKey: .lastwindow) ?? "0x0"
        lastwindowtitle = try c.decodeIfPresent(String.self, forKey: .lastwindowtitle)
        group = try c.decodeIfPresent(Int.self, forKey: .group)
        active = try c.decodeIfPresent(Bool.self, forKey: .active)
    }
}

/// One bind as reported by `query.binds` / `keys.list` (our own shape; `hyprctl binds` fields
/// that have a Mac meaning are included: `locked`, `mouse`, `release`, `repeat`, `description`).
public struct BindQueryEntry: Codable, Hashable, Sendable {
    public var id: String
    /// Chords as written in keymap.toml ("SUPER + 1").
    public var keys: [String]
    /// Chords rendered with Mac symbols for the active modifier map ("⌥L + 1").
    public var mac: [String]
    /// `ActionKind` raw value.
    public var action: String
    public var args: [String: JSONValue]
    public var locked: Bool
    public var mouse: Bool
    public var release: Bool
    public var `repeat`: Bool
    public var description: String
    public var enabled: Bool
    /// Original Hyprland bind text, when known.
    public var linux: String?

    public init(
        id: String, keys: [String], mac: [String], action: String, args: [String: JSONValue] = [:],
        locked: Bool = false, mouse: Bool = false, release: Bool = false, repeat: Bool = false,
        description: String = "", enabled: Bool = true, linux: String? = nil
    ) {
        self.id = id
        self.keys = keys
        self.mac = mac
        self.action = action
        self.args = args
        self.locked = locked
        self.mouse = mouse
        self.release = release
        self.repeat = `repeat`
        self.description = description
        self.enabled = enabled
        self.linux = linux
    }

    /// Builds an entry from a parsed keymap bind, rendering Mac chords with the modifier map.
    public init(bind: Bind, modifiers: ModifierMap) {
        self.init(
            id: bind.id,
            keys: bind.keys,
            mac: bind.chords.map { BindQueryEntry.macChord($0, modifiers: modifiers) },
            action: bind.action.kind.rawValue,
            args: bind.action.args.mapValues(JSONValue.init),
            locked: bind.flags.contains(.locked),
            mouse: bind.flags.contains(.mouse),
            release: bind.flags.contains(.release),
            repeat: bind.flags.contains(.repeat),
            description: bind.description,
            enabled: bind.enabled,
            linux: bind.linux
        )
    }

    /// Renders a chord with Mac modifier symbols ("⌥L + ⇧ + Left").
    public static func macChord(_ chord: KeyChord, modifiers: ModifierMap) -> String {
        let mods = chord.modifiers.sorted().map { modifiers[$0].symbol }
        let key: String
        switch chord.key {
        case .modifierTap(let m): key = "\(modifiers[m].symbol) (tap)"
        default: key = chord.key.description
        }
        return (mods + [key]).joined(separator: " + ")
    }

    /// Action with arguments in one column ("workspace.focus(index=3)").
    public var actionDescription: String {
        if args.isEmpty { return action }
        let a = args.keys.sorted().map { "\($0)=\(args[$0]!.stringValue ?? args[$0]!.compactJSON)" }.joined(separator: ", ")
        return "\(action)(\(a))"
    }
}

/// `query.state` payload: a compact summary for scripts and the doctor.
public struct StateQueryEntry: Codable, Hashable, Sendable {
    /// "standard" or "enhanced".
    public var mode: String
    public var version: String
    public var pid: Int
    public var uptimeSeconds: Double
    public var focusedWindow: String?
    public var focusedWorkspace: WorkspaceRef?
    public var focusedMonitor: String?
    public var windowCount: Int
    public var workspaceCount: Int
    public var monitorCount: Int
    public var gameMode: Bool
    /// Free-form counters (layout passes, AX setFrame calls, ...) for the Riko suite.
    public var counters: [String: Int]
    /// What the tiler did when a window could not take its natural size, for `skyrose doctor`.
    public var tilingNotes: [String]

    public init(
        mode: String, version: String = CaelestiaVersion.string, pid: Int = Int(ProcessInfo.processInfo.processIdentifier),
        uptimeSeconds: Double = 0, focusedWindow: String? = nil, focusedWorkspace: WorkspaceRef? = nil, focusedMonitor: String? = nil,
        windowCount: Int = 0, workspaceCount: Int = 0, monitorCount: Int = 0, gameMode: Bool = false, counters: [String: Int] = [:],
        tilingNotes: [String] = []
    ) {
        self.mode = mode
        self.version = version
        self.pid = pid
        self.uptimeSeconds = uptimeSeconds
        self.focusedWindow = focusedWindow
        self.focusedWorkspace = focusedWorkspace
        self.focusedMonitor = focusedMonitor
        self.windowCount = windowCount
        self.workspaceCount = workspaceCount
        self.monitorCount = monitorCount
        self.gameMode = gameMode
        self.counters = counters
        self.tilingNotes = tilingNotes
    }
}

/// `permissions.status` payload. Each value is `true`, `false`, or `"unknown"` when the check
/// cannot run (e.g. no Automation target has been probed yet).
public struct PermissionsStatusEntry: Codable, Hashable, Sendable {
    public var accessibility: Bool
    public var inputMonitoring: Bool
    public var screenRecording: Bool
    /// Automation targets probed so far, by bundle id.
    public var automation: [String: Bool]
    /// Standard / Enhanced and whether the scripting addition is loaded.
    public var mode: String
    public var enhancedLoaded: Bool

    public init(accessibility: Bool, inputMonitoring: Bool, screenRecording: Bool, automation: [String: Bool] = [:], mode: String = "standard", enhancedLoaded: Bool = false) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.screenRecording = screenRecording
        self.automation = automation
        self.mode = mode
        self.enhancedLoaded = enhancedLoaded
    }
}
