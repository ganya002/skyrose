import Foundation

/// Top-level configuration: built-in defaults < ~/.config/caelestia-mac/config.toml < per-display
/// overrides. Field names follow Caelestia/Hyprland names where one exists so Linux knowledge
/// carries over (gapsIn, gapsOut, borderSize, windowRounding, ...).
public struct Config: Codable, Equatable, Sendable {
    public var wm: WMConfig
    public var appearance: AppearanceConfig
    public var bar: BarConfig
    public var input: InputConfig
    public var apps: AppsConfig
    public var animations: AnimationsConfig
    /// Per-display overrides keyed by stable display id (CGDisplayCreateUUIDFromDisplayID).
    public var displays: [String: DisplayOverride]

    public init(
        wm: WMConfig = WMConfig(), appearance: AppearanceConfig = AppearanceConfig(),
        bar: BarConfig = BarConfig(), input: InputConfig = InputConfig(), apps: AppsConfig = AppsConfig(),
        animations: AnimationsConfig = AnimationsConfig(), displays: [String: DisplayOverride] = [:]
    ) {
        self.wm = wm
        self.appearance = appearance
        self.bar = bar
        self.input = input
        self.apps = apps
        self.animations = animations
        self.displays = displays
    }

    /// Gabby's effective Arch values (variables.lua + hypr-vars.lua + hypr-user.lua + shell.json).
    public static let gabbyDefaults = Config()

    /// Base Caelestia values before Gabby's overrides.
    public static var caelestiaStock: Config {
        var c = Config()
        c.wm.blurSize = 8
        c.wm.blurPasses = 2
        c.bar.persistent = false
        c.animations.preset = .caelestiaStock
        return c
    }

    /// Resolves the effective config for one display by applying its override, if any.
    public func resolved(forDisplay id: String) -> Config {
        guard let o = displays[id] else { return self }
        var c = self
        if let v = o.gapsIn { c.wm.gapsIn = v }
        if let v = o.gapsOut { c.wm.gapsOut = v }
        if let v = o.gapsOutSingle { c.wm.gapsOutSingle = v }
        if let v = o.barPersistent { c.bar.persistent = v }
        if let v = o.barEnabled { c.bar.enabled = v }
        if let v = o.uiScale { c.appearance.uiScale = v }
        if let v = o.screenFrame { c.wm.screenFrame = v }
        return c
    }
}

public struct WMConfig: Codable, Equatable, Sendable {
    /// Gap on each side of a tiled window (Hyprland gaps_in). 5 → 10 px between neighbors.
    public var gapsIn: Double = 5
    /// Gap between the tiled area and the usable-area edge (Hyprland gaps_out).
    public var gapsOut: Double = 10
    /// gaps_out when exactly one tiled window / one fullscreen-flagged window is on the workspace
    /// (workspace rules w[tv1]s[false] and f[1]s[false]).
    public var gapsOutSingle: Double = 20
    /// Horizontal gap between the outgoing and incoming workspace in the slide animation.
    public var gapsWorkspaces: Double = 20
    public var borderSize: Double = 1
    /// Group (tab) bar: tab height, and the gap between tabs and between the bar and the window
    /// (Hyprland groupbar height 25, gaps_in/gaps_out 3).
    public var groupBarHeight: Double = 25
    public var groupBarGaps: Double = 3
    public var windowRounding: Double = 15
    public var roundingPower: Double = 2
    /// Rounding for xwl_popup-style windows: min(10, windowRounding).
    public var popupRounding: Double = 10
    /// Non-fullscreen window opacity (Enhanced mode only; Standard cannot set it).
    public var windowOpacity: Double = 0.94
    public var blurEnabled: Bool = true
    public var blurSize: Double = 10
    public var blurPasses: Int = 3
    public var blurSpecial: Bool = false
    public var shadowEnabled: Bool = true
    public var shadowRange: Double = 15
    public var shadowRenderPower: Double = 4
    /// Caelestia "border" layer: thin rounded frame reserving this many points per edge.
    public var screenFrame: Bool = true
    public var screenFrameInset: Double = 10
    public var dwindle: DwindleConfig = DwindleConfig()
    public var focusFollowsMouse: Bool = true
    public var focusFollowsMouseDelayMs: Int = 100
    /// Hyprland input.focus_on_close = 1: focus the window under the cursor after a close.
    public var focusOnCloseUnderCursor: Bool = true
    public var workspacesPerGroup: Int = 10
    public var workspaceGroups: Int = 5
    /// Caelestia bar default: always show workspaces 1..N.
    public var workspacesShown: Int = 5
    /// Gabby: the special toggle closes whichever special workspace is open.
    public var specialWsCloseAny: Bool = true
    /// Standard mode: send interpolated AX frames (≤60 Hz, ≤200 ms). Off because many apps lag.
    public var animatedTiling: Bool = false
    /// Opening/focusing a window un-fullscreens the current fullscreen one (on_focus_under_fullscreen = 2).
    public var unfullscreenOnFocus: Bool = true
    public var focusOnActivate: Bool = true
    /// Game mode (Caelestia gameMode IPC): no animations/blur/gaps/borders/shadows.
    public var gameMode: Bool = false
    /// Named special workspaces (scratchpads) and the app that owns each.
    public var specialWorkspaces: [String: SpecialWorkspaceConfig] = SpecialWorkspaceConfig.defaults

    public init() {}
}

public struct DwindleConfig: Codable, Equatable, Sendable {
    public var preserveSplit: Bool = true
    public var smartSplit: Bool = false
    public var smartResizing: Bool = true
    /// 0 = follow mouse side only when smart_split is on (effectively right/bottom), 1 = left/top, 2 = right/bottom.
    public var forceSplit: Int = 0
    public var splitWidthMultiplier: Double = 1.0
    public var defaultSplitRatio: Double = 1.0
    public var minSplitRatio: Double = 0.1
    public var maxSplitRatio: Double = 1.9
    public init() {}
}

public struct SpecialWorkspaceConfig: Codable, Equatable, Sendable {
    /// Bundle ids that are auto-assigned to this special workspace, in preference order.
    public var apps: [String]
    /// Command run when the toggle finds no window on the special workspace.
    public var launch: String
    public init(apps: [String], launch: String) {
        self.apps = apps
        self.launch = launch
    }

    public static let defaults: [String: SpecialWorkspaceConfig] = [
        "special": SpecialWorkspaceConfig(apps: [], launch: ""),
        "sysmon": SpecialWorkspaceConfig(apps: ["net.kovidgoyal.kitty#btop"], launch: "kitty --class btop -e btop"),
        "music": SpecialWorkspaceConfig(apps: ["com.spotify.client", "com.apple.Music"], launch: "open -b com.spotify.client || open -b com.apple.Music"),
        "communication": SpecialWorkspaceConfig(apps: ["com.hnc.Discord", "com.apple.MobileSMS"], launch: "open -b com.hnc.Discord || open -b com.apple.MobileSMS"),
        "todo": SpecialWorkspaceConfig(apps: ["com.todoist.mac.Todoist", "com.apple.reminders"], launch: "open -b com.todoist.mac.Todoist || open -b com.apple.reminders"),
    ]
}

public struct AppearanceConfig: Codable, Equatable, Sendable {
    public var transparencyEnabled: Bool = true
    /// Panel/bar background alpha (shell.json appearance.transparency.base).
    public var transparencyBase: Double = 0.75
    /// Inner card alpha over the panel (appearance.transparency.layers).
    public var transparencyLayers: Double = 0.35
    /// Theme name: "caelestia-dynamic", "caelestia-default", "catppuccin-mocha", "noctalia".
    public var theme: String = "caelestia-dynamic"
    public var variant: String = "dark"
    /// Manual accent override, hex RRGGBB, empty for none.
    public var accentOverride: String = ""
    public var dynamicColor: Bool = true
    public var uiScale: Double = 1.0
    public var fontSans: String = "Rubik"
    public var fontSansFallbacks: [String] = ["Inter", "SF Pro"]
    public var fontMono: String = "CaskaydiaCove NF"
    public var fontMonoFallbacks: [String] = ["JetBrainsMono Nerd Font", "Menlo"]
    public var fontIcons: String = "Material Symbols Rounded"
    public var wallpaperFolder: String = "~/Pictures/Wallpapers"
    public var wallpaperRandomIntervalMinutes: Int = 0
    public init() {}
}

public struct BarConfig: Codable, Equatable, Sendable {
    public var enabled: Bool = true
    /// Gabby's Arch shell.json: false (overlays, slides in on hover, reserves 0). true reserves
    /// the bar's width in the usable area.
    public var persistent: Bool = false
    public var edge: Edge = .left
    public var width: Double = 48
    public var showOnHover: Bool = true
    public var clockBackground: Bool = false
    public var trayBackground: Bool = false
    public var activeWindowCompact: Bool = false
    public var workspacesOccupiedBg: Bool = false
    public var statusIcons: [StatusIcon] = StatusIcon.defaults
    public init() {}

    public struct StatusIcon: Codable, Equatable, Sendable {
        public var id: String
        public var enabled: Bool
        public init(id: String, enabled: Bool) {
            self.id = id
            self.enabled = enabled
        }
        public static let defaults: [StatusIcon] = [
            StatusIcon(id: "lockStatus", enabled: true),
            StatusIcon(id: "audio", enabled: true),
            StatusIcon(id: "microphone", enabled: false),
            StatusIcon(id: "kbLayout", enabled: false),
            StatusIcon(id: "network", enabled: true),
            StatusIcon(id: "bluetooth", enabled: false),
            // Gabby's desktop had no battery; a laptop defaults to ON. The loader flips this when
            // IOKit reports an internal battery and the user never set it.
            StatusIcon(id: "battery", enabled: false),
        ]
    }
}

public struct InputConfig: Codable, Equatable, Sendable {
    /// Super tap window (ms): Super down then up with nothing else in between opens the launcher.
    public var superTapMs: Int = 300
    public var repeatDelayMs: Int = 250
    public var repeatRatePerSecond: Int = 35
    public var scrollFactor: Double = 0.3
    public var naturalScroll: Bool = true
    /// Continuous scroll distance per workspace step (points).
    public var scrollStepPoints: Double = 60
    public var gesturesEnabled: Bool = false
    public var gestureFingers: Int = 3
    public var gestureFingersMore: Int = 4
    public var gestureDistance: Double = 700
    public var gestureCancelRatio: Double = 0.15
    public var gestureMinSpeedToForce: Double = 5
    public var gestureDirectionLock: Bool = true
    public var gestureDirectionLockThreshold: Double = 10
    public var gestureCreateNew: Bool = true
    /// "Take over ⌘Tab" (off: ALT+Tab cycle maps to ⌥L+Tab).
    public var takeOverCmdTab: Bool = false
    public init() {}
}

public struct AppsConfig: Codable, Equatable, Sendable {
    public var terminal: String = "kitty"
    public var browser: String = "org.mozilla.firefox"
    public var editor: String = "com.vscodium"
    public var fileManager: String = "com.apple.finder"
    public var audioSettings: String = "x-apple.systempreferences:com.apple.Sound-Settings.extension"
    public init() {}
}

public struct AnimationsConfig: Codable, Equatable, Sendable {
    public enum Preset: String, Codable, Sendable, CaseIterable {
        case gabbySpringy = "gabby-springy"
        case caelestiaStock = "caelestia-stock"
        case reduced
        case off
    }
    public var preset: Preset = .gabbySpringy
    /// Global multiplier on all durations (Hyprland global speed / shell durations.scale are
    /// applied separately inside the Motion tables).
    public var globalMultiplier: Double = 1.0
    public var shellDurationScale: Double = 0.8
    public var respectReduceMotion: Bool = true
    /// Per-animation overrides keyed by animation name (windowsIn, windowsMove, ...).
    public var overrides: [String: AnimationOverride] = [:]
    public init() {}
}

public struct AnimationOverride: Codable, Equatable, Sendable {
    public var enabled: Bool?
    public var curve: String?
    public var speed: Double?
    public var style: String?
    public init(enabled: Bool? = nil, curve: String? = nil, speed: Double? = nil, style: String? = nil) {
        self.enabled = enabled
        self.curve = curve
        self.speed = speed
        self.style = style
    }
}

public struct DisplayOverride: Codable, Equatable, Sendable {
    public var gapsIn: Double?
    public var gapsOut: Double?
    public var gapsOutSingle: Double?
    public var barPersistent: Bool?
    public var barEnabled: Bool?
    public var uiScale: Double?
    public var screenFrame: Bool?
    public init() {}
}

/// Well-known paths. Never hard-code a username: everything derives from the home directory.
public enum Paths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    public static var configDir: URL { home.appendingPathComponent(".config/caelestia-mac", isDirectory: true) }
    public static var configFile: URL { configDir.appendingPathComponent("config.toml") }
    public static var keymapFile: URL { configDir.appendingPathComponent("keymap.toml") }
    public static var rulesFile: URL { configDir.appendingPathComponent("rules.toml") }
    public static var appSupport: URL {
        home.appendingPathComponent("Library/Application Support/CaelestiaMac", isDirectory: true)
    }
    public static var ipcSocket: URL { appSupport.appendingPathComponent("ipc.sock") }
    public static var backupJournal: URL { appSupport.appendingPathComponent("backup.json") }
    public static var parkedWindowsJournal: URL { appSupport.appendingPathComponent("parked-windows.json") }
    public static var workspaceAssignments: URL { appSupport.appendingPathComponent("workspace-assignments.json") }
    public static var logsDir: URL { home.appendingPathComponent("Library/Logs/CaelestiaMac", isDirectory: true) }
    public static var kittyThemeFile: URL { home.appendingPathComponent(".config/kitty/caelestia-theme.conf") }
}
