import Foundation

/// Top-level configuration: built-in defaults < ~/.config/skyrose/config.toml < per-display
/// overrides. Field names follow Caelestia/Hyprland names where one exists so Linux knowledge
/// carries over (gapsIn, gapsOut, borderSize, windowRounding, ...).
public struct Config: Codable, Equatable, Sendable {
    /// Mode and other app-wide switches (`[general]`).
    public var general: GeneralConfig
    /// Which shell parts run (`[shell]`); every one can be turned off.
    public var shell: ShellModulesConfig
    public var wm: WMConfig
    public var appearance: AppearanceConfig
    public var bar: BarConfig
    public var input: InputConfig
    public var apps: AppsConfig
    public var animations: AnimationsConfig
    public var dashboard: DashboardConfig
    /// Where the dashboard's weather comes from (`[weather]`, Open-Meteo).
    public var weather: WeatherConfig
    /// SIP-off mode (`[sipOff]`): opt-in, needs the scripting addition loaded into the Dock.
    public var sipOff: SIPOffConfig
    /// Screenshot tool (`[capture]`).
    public var capture: CaptureConfig
    /// Lid-closed behaviour (`[clamshell]`).
    public var clamshell: ClamshellConfig
    public var frame: FrameConfig
    /// Per-display overrides keyed by stable display id (CGDisplayCreateUUIDFromDisplayID).
    public var displays: [String: DisplayOverride]
    /// Per-app window rules by bundle id: "tile", "float" or "auto" (`AppRuleBook`).
    public var appRules: [String: String]

    public init(
        wm: WMConfig = WMConfig(), appearance: AppearanceConfig = AppearanceConfig(),
        bar: BarConfig = BarConfig(), input: InputConfig = InputConfig(), apps: AppsConfig = AppsConfig(),
        animations: AnimationsConfig = AnimationsConfig(), dashboard: DashboardConfig = DashboardConfig(),
        frame: FrameConfig = FrameConfig(), displays: [String: DisplayOverride] = [:], appRules: [String: String] = [:],
        general: GeneralConfig = GeneralConfig(), shell: ShellModulesConfig = ShellModulesConfig(),
        weather: WeatherConfig = WeatherConfig(), sipOff: SIPOffConfig = SIPOffConfig(),
        capture: CaptureConfig = CaptureConfig(), clamshell: ClamshellConfig = ClamshellConfig()
    ) {
        self.capture = capture
        self.clamshell = clamshell
        self.general = general
        self.weather = weather
        self.sipOff = sipOff
        self.shell = shell
        self.appRules = appRules
        self.frame = frame
        self.wm = wm
        self.appearance = appearance
        self.bar = bar
        self.input = input
        self.apps = apps
        self.animations = animations
        self.dashboard = dashboard
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

    /// The per-app rule book (user rules over the built-in floating list).
    public var appRuleBook: AppRuleBook { AppRuleBook(config: appRules) }

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
        if let v = o.displayCornerRadius { c.frame.displayCornerRadius = v }
        if let v = o.displayBottomCornerRadius { c.frame.displayBottomCornerRadius = v }
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
    /// Window borders on or off (Settings › Windows); `borderSize` is their width.
    public var bordersEnabled: Bool = true
    public var borderSize: Double = 1
    /// Group (tab) bar: tab height, and the gap between tabs and around the bar (Hyprland groupbar
    /// height 25, gaps_in/gaps_out 3). A grouped window moves down by height + 2 × gaps = 31.
    public var groupBarHeight: Double = 25
    public var groupBarGaps: Double = 3
    public var windowRounding: Double = 15
    public var roundingPower: Double = 2
    /// Rounding for xwl_popup-style windows: min(10, windowRounding).
    public var popupRounding: Double = 10
    /// Non-fullscreen window opacity (Enhanced mode only; Standard cannot set it).
    /// variables.lua windowOpacity = 0.95 (the live getoption in the 2026-11-05 capture).
    public var windowOpacity: Double = 0.95
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
    /// Clicking the red close button on an app's last window quits the app (a normal quit, so
    /// it can still ask to save). Off by default; yellow/green and ⌘W are never affected.
    public var closeQuitsApp: Bool = false
    /// Bundle ids the red button never quits.
    public var closeQuitsAppExceptions: [String] = ["com.apple.finder"]
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
    /// Hyprland dwindle:force_split. 0 = the new window goes to the half of the focused tile the
    /// cursor is in (right/bottom when the cursor is outside that tile), 1 = always left/top,
    /// 2 = always right/bottom.
    public var forceSplit: Int = 0
    public var splitWidthMultiplier: Double = 1.0
    public var defaultSplitRatio: Double = 1.0
    public var minSplitRatio: Double = 0.1
    public var maxSplitRatio: Double = 1.9
    /// Smallest window a split may produce (pt, gaps and border not included). Hyprland has no
    /// minimum (tiles went down to 27×32 px); a split that would go below this splits the largest
    /// tile that still fits instead, and when none fits the new window floats. 0 = no minimum.
    public var minTileWidth: Double = 120
    public var minTileHeight: Double = 80
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
    /// Theme name: "skyrose-dynamic", "skyrose-default", "catppuccin-mocha", "noctalia".
    public var theme: String = "skyrose-dynamic"
    public var variant: String = "dark"
    /// Manual accent override, hex RRGGBB, empty for none.
    public var accentOverride: String = ""
    /// Legacy flag from the first config draft; `schemeMode` is what the shell reads.
    public var dynamicColor: Bool = true
    /// "static": the scheme named by `theme` (periwinkle SkyRose Dynamic by default).
    /// "dynamic": a Material You palette extracted from the current wallpaper, applied live.
    public var schemeMode: String = "static"
    public var uiScale: Double = 1.0
    public var fontSans: String = "Rubik"
    public var fontSansFallbacks: [String] = ["Inter", "SF Pro"]
    /// Nerd Fonts v3 family name ("CaskaydiaCove NF" is the v2 / Windows name, kept as a fallback).
    public var fontMono: String = "CaskaydiaCove Nerd Font"
    public var fontMonoFallbacks: [String] = ["CaskaydiaCove NF", "JetBrainsMono Nerd Font", "JetBrainsMono NF", "Menlo"]
    public var fontIcons: String = "Material Symbols Rounded"
    public var wallpaperFolder: String = "~/Pictures/Wallpapers"
    public var wallpaperRandomIntervalMinutes: Int = 0
    /// Cursor theme for this login session: a Mousecape cape identifier (e.g.
    /// "Bibata-Modern-Classic"), or "" for the macOS cursors. The wait cursor is never replaced.
    public var cursor: String = ""
    public init() {}
}

public struct DashboardConfig: Codable, Equatable, Sendable {
    /// Seconds in the Overview clock (shell.json dashboard.showClockSeconds).
    public var showClockSeconds: Bool = true
    /// Battery card in the Performance tab (shown only on Macs that have a battery).
    public var showBattery: Bool = true
    /// "overview", "media" or "performance".
    public var defaultTab: String = "overview"
    public init() {}
}

/// SIP-off mode (docs/ENHANCED_MODE.md). Off by default; Settings only lets it be switched on
/// after the "What changes with SIP off?" showcase. Every feature needs the scripting addition
/// in the Dock; while it is not loaded (or a macOS update broke it) SkyRose silently keeps its
/// SIP-on behaviour.
public struct SIPOffConfig: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    /// Real-window open / close / move animations (transform + alpha), no snapshot cover.
    public var animations: Bool = true
    /// `wm.windowOpacity` on every non-fullscreen window.
    public var opacity: Bool = true
    /// false: other apps' windows lose their macOS shadow.
    public var shadows: Bool = true
    /// Workspace switches swap instantly (no slide, no visible parking).
    public var instantWorkspaces: Bool = true
    /// Pinned windows are really always on top (floating window level).
    public var pinOnTop: Bool = true
    public init() {}
}

/// Screenshot tool (Caelestia's grim + slurp + wl-copy + swappy flow, on ScreenCaptureKit).
public struct CaptureConfig: Codable, Equatable, Sendable {
    /// Where screenshots are saved ("~" expands). Created on first use.
    public var folder: String = "~/Pictures/Screenshots"
    /// Save a PNG into `folder`.
    public var saveToFolder: Bool = true
    /// Put the image on the clipboard (wl-copy).
    public var copyToClipboard: Bool = true
    /// A toast with a thumbnail after each screenshot.
    public var thumbnail: Bool = true
    /// Also bind macOS's own ⇧⌘3 (full), ⇧⌘4 (region) and ⇧⌘5 (freeze) to SkyRose's tool.
    /// Off by default: macOS's shortcuts stay untouched.
    public var overrideSystemShortcuts: Bool = false
    public init() {}
}

/// Lid closed. Clamshell on/off itself is runtime state (`skyrose clamshell on`, `LidSleepControl`).
public struct ClamshellConfig: Codable, Equatable, Sendable {
    /// Hold a keep-awake (idle display sleep off) while the lid is closed.
    public var keepAwake: Bool = false
    public init() {}
}

/// Weather for the dashboard (Open-Meteo, no API key). Nothing is fetched until a city is set or
/// `useLocation` is on; there are no placeholder values.
public struct WeatherConfig: Codable, Equatable, Sendable {
    /// Shown name of the chosen place ("Munich, Germany"); "" = no weather.
    public var city: String = ""
    /// Coordinates of `city`, from the Open-Meteo geocoding search in Settings.
    public var latitude: Double = 0
    public var longitude: Double = 0
    /// Use this Mac's location (CoreLocation) instead of the city. Off by default; asks for the
    /// Location permission when switched on. Falls back to the city if it is denied.
    public var useLocation: Bool = false
    /// Show °F instead of °C.
    public var fahrenheit: Bool = false
    /// Minutes between refreshes (Open-Meteo updates hourly).
    public var refreshMinutes: Int = 30
    public init() {}

    /// A city was picked (coordinates are set) or the location is used.
    public var isConfigured: Bool { useLocation || hasCity }
    public var hasCity: Bool { !city.isEmpty && !(latitude == 0 && longitude == 0) }
}

public struct BarConfig: Codable, Equatable, Sendable {
    public var enabled: Bool = true
    // Bar modules, top to bottom (Settings › Bar and Shell).
    public var showLogo: Bool = true
    public var showWorkspaces: Bool = true
    public var showActiveWindow: Bool = true
    public var showTray: Bool = true
    public var showClock: Bool = true
    public var showStatusIcons: Bool = true
    public var showPower: Bool = true
    /// Gabby's Arch shell.json: false (overlays, slides in on hover, reserves 0). true reserves
    /// the bar's width in the usable area.
    public var persistent: Bool = false
    public var edge: Edge = .left
    /// Measured in the 2026-11-05 capture: the revealed bar is ~60 px wide at scale 1.
    public var width: Double = 60
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
    /// The F-row volume / mute / brightness keys are handled by Caelestia: volume through
    /// CoreAudio, brightness through DisplayServices, only Caelestia's OSD shows and the key never
    /// reaches macOS (so Apple's HUD stays away). A key Caelestia cannot handle (no settable
    /// volume on the output, no brightness control for the display) passes through to macOS.
    public var interceptMediaKeys: Bool = true
    public init() {}
}

public struct AppsConfig: Codable, Equatable, Sendable {
    public var terminal: String = "kitty"
    public var browser: String = "org.mozilla.firefox"
    public var editor: String = "com.vscodium"
    public var fileManager: String = "com.apple.finder"
    public var audioSettings: String = "x-apple.systempreferences:com.apple.Sound-Settings.extension"
    /// Font of the SkyRose kitty profile (skyrose.conf): Gabby's kitty.conf value.
    public var kittyFont: String = KittyProfile.Options.defaultFont
    public var kittyFontSize: Double = 13
    public var kittyOptions: KittyProfile.Options { KittyProfile.Options(fontFamily: kittyFont, fontSize: kittyFontSize) }
    public init() {}
}

public struct AnimationsConfig: Codable, Equatable, Sendable {
    public enum Preset: String, Codable, Sendable, CaseIterable {
        case gabbySpringy = "gabby-springy"
        case caelestiaStock = "caelestia-stock"
        case reduced
        case off
    }
    /// How real windows animate in Standard mode (SIP on).
    public enum WindowMode: String, Codable, Sendable, CaseIterable {
        /// ScreenCaptureKit stills animate on an overlay cover while the real windows are moved
        /// once underneath (needs Screen Recording; instant without it).
        case snapshot
        /// Windows snap to their final frame; only the borders fade.
        case off
    }
    public var preset: Preset = .gabbySpringy
    /// Window open/close/move/drag animations. Curves and speeds come from the preset and the
    /// `windowsIn` / `windowsMove` / `windowsOut` overrides.
    public var windows: WindowMode = .snapshot
    /// Global multiplier on all durations (Hyprland global speed / shell durations.scale are
    /// applied separately inside the Motion tables).
    public var globalMultiplier: Double = 1.0
    /// Speed multiplier for every animation (window, workspace and shell): 2 = twice as fast,
    /// 0.5 = half speed. Durations are divided by it (after `globalMultiplier`).
    public var speed: Double = 1.0
    public var shellDurationScale: Double = 0.8
    public var respectReduceMotion: Bool = true
    /// SkyRose's own Reduce Motion switch (Settings › Windows): every animation becomes the short
    /// cross-fade, whatever the macOS setting says.
    public var reduceMotion: Bool = false
    /// Per-animation overrides keyed by animation name (windowsIn, windowsMove, ...).
    public var overrides: [String: AnimationOverride] = [:]
    public init() {}

    /// What every duration is multiplied by: `globalMultiplier / speed`.
    public var durationFactor: Double {
        guard speed > 0, speed.isFinite else { return globalMultiplier }
        return globalMultiplier / speed
    }
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
    /// Physical corner radius of this display (pt); see ``FrameConfig/displayCornerRadius``.
    public var displayCornerRadius: Double?
    /// Physical radius of this display's bottom corners; see ``FrameConfig/displayBottomCornerRadius``.
    public var displayBottomCornerRadius: Double?
    public init() {}
}

/// The screen frame's fit to the display hardware.
public struct FrameConfig: Codable, Equatable, Sendable {
    /// Radius (pt) of the display's physical rounded *top* corners (and of the bottom corners
    /// unless ``displayBottomCornerRadius`` is set). The frame's outer edge follows it and its
    /// inner corners use this − the band thickness, so the band keeps one width around the
    /// corner. Apple does not publish the value, so it is tuned by eye (`skyrose frame
    /// calibrate`, saved per display under `[displays."<uuid>"]`). Negative = auto:
    /// ``autoBuiltInRadius`` on a built-in panel with a notch, 0 (square) everywhere else.
    public var displayCornerRadius: Double = -1
    /// Radius (pt) of the physical bottom corners. Negative = auto: 0 on a built-in panel (the
    /// notched MacBook panels round only their top corners; a frame corner rounded more than the
    /// hardware shows the wallpaper through), else the same as ``displayCornerRadius``.
    public var displayBottomCornerRadius: Double = -1

    /// The auto top radius of notched MacBook panels (an eyeballed starting point).
    public static let autoBuiltInRadius: Double = 10
    public static let maxRadius: Double = 60

    public init() {}

    /// The effective top radius for a display: the configured value, or the auto default.
    public func cornerRadius(isBuiltIn: Bool, hasNotch: Bool) -> Double {
        if displayCornerRadius >= 0 { return min(displayCornerRadius, Self.maxRadius) }
        return isBuiltIn && hasNotch ? Self.autoBuiltInRadius : 0
    }

    /// The effective bottom radius for a display: the configured value, else 0 on a built-in
    /// panel, else the top radius.
    public func bottomCornerRadius(isBuiltIn: Bool, hasNotch: Bool) -> Double {
        if displayBottomCornerRadius >= 0 { return min(displayBottomCornerRadius, Self.maxRadius) }
        return isBuiltIn ? 0 : cornerRadius(isBuiltIn: isBuiltIn, hasNotch: hasNotch)
    }
}

/// Well-known paths. Never hard-code a username: everything derives from the home directory.
public enum Paths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    public static var configDir: URL { home.appendingPathComponent(".config/skyrose", isDirectory: true) }
    public static var configFile: URL { configDir.appendingPathComponent("config.toml") }
    public static var keymapFile: URL { configDir.appendingPathComponent("keymap.toml") }
    public static var rulesFile: URL { configDir.appendingPathComponent("rules.toml") }
    public static var appSupport: URL {
        home.appendingPathComponent("Library/Application Support/SkyRose", isDirectory: true)
    }
    public static var ipcSocket: URL { appSupport.appendingPathComponent("ipc.sock") }
    /// The restore manifest: every system change SkyRose makes (Dock, menu bar, shortcuts, …),
    /// with the original value, so the uninstaller can put everything back (`RestoreManifest`).
    public static var restoreManifest: URL { appSupport.appendingPathComponent("restore-manifest.json") }
    /// The manifest under its older name (the format is the same; kept as the journal API name).
    public static var backupJournal: URL { restoreManifest }
    /// Onboarding progress, the chosen mode and the permissions seen granted (`OnboardingState`).
    public static var onboardingState: URL { appSupport.appendingPathComponent("onboarding.json") }
    /// The colour scheme the shell is drawing right now (the Settings app follows it).
    public static var currentScheme: URL { appSupport.appendingPathComponent("current-scheme.toml") }
    public static var parkedWindowsJournal: URL { appSupport.appendingPathComponent("parked-windows.json") }
    /// Workspace model at the last WM run, so a restart keeps every window's workspace and side.
    public static var sessionSnapshot: URL { appSupport.appendingPathComponent("session.json") }
    public static var workspaceAssignments: URL { appSupport.appendingPathComponent("workspace-assignments.json") }
    public static var logsDir: URL { home.appendingPathComponent("Library/Logs/SkyRose", isDirectory: true) }
    public static var kittyConfigDir: URL { home.appendingPathComponent(".config/kitty", isDirectory: true) }
    public static var kittyThemeFile: URL { home.appendingPathComponent(".config/kitty/skyrose-theme.conf") }

    // Pre-rename locations (Caelestia for Mac), read once by `LegacyMigration`.
    public static var legacyConfigDir: URL { home.appendingPathComponent(".config/caelestia-mac", isDirectory: true) }
    public static var legacyAppSupport: URL {
        home.appendingPathComponent("Library/Application Support/CaelestiaMac", isDirectory: true)
    }
    public static var legacyLogsDir: URL { home.appendingPathComponent("Library/Logs/CaelestiaMac", isDirectory: true) }
    public static var legacyKittyThemeFile: URL { home.appendingPathComponent(".config/kitty/caelestia-theme.conf") }
}

// MARK: - SkyRose modes and modules

/// App-wide switches (`[general]`).
public struct GeneralConfig: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        /// Everything: SkyRose WM plus the shell (bar, frame, launcher, dashboard, …).
        case full
        /// SkyRose WM only: tiling, keybinds and borders. No bar, no shell, no screen frame.
        case wm
    }
    public var mode: Mode = .full
    public init() {}
}

/// Every shell part can be switched off on its own (`[shell]`, Settings › Bar and Shell).
/// `enabled = false` turns the whole shell off (like WM-only mode, but keeps the screen frame
/// setting as it is).
public struct ShellModulesConfig: Codable, Equatable, Sendable {
    public var enabled: Bool = true
    public var launcher: Bool = true
    public var dashboard: Bool = true
    public var sidebar: Bool = true
    public var session: Bool = true
    /// Volume / brightness on-screen display (off: the media keys go back to macOS).
    public var osd: Bool = true
    /// Toasts and the notification history.
    public var notifications: Bool = true
    public var wallpaperPicker: Bool = true
    public init() {}

    /// Module ids in Settings order.
    public static let moduleIDs = ["launcher", "dashboard", "sidebar", "session", "osd", "notifications", "wallpaperPicker"]

    public func isOn(_ id: String) -> Bool {
        guard enabled else { return false }
        switch id {
        case "launcher": return launcher
        case "dashboard": return dashboard
        case "sidebar": return sidebar
        case "session": return session
        case "osd": return osd
        case "notifications": return notifications
        case "wallpaperPicker": return wallpaperPicker
        default: return true
        }
    }
}

public extension Config {
    /// True when no shell runs at all (WM-only mode, or the shell switched off).
    var shellOff: Bool { general.mode == .wm || !shell.enabled }

    /// The config the running parts use: WM-only mode turns the bar, the screen frame, every
    /// shell module and the media-key interception off (per-display overrides included), and
    /// keeps tiling, keybinds and borders. In full mode it is the config as written.
    var effective: Config {
        var c = self
        if general.mode == .wm {
            c.bar.enabled = false
            c.wm.screenFrame = false
            c.shell.enabled = false
            for id in c.displays.keys {
                c.displays[id]?.barEnabled = false
                c.displays[id]?.screenFrame = false
            }
        }
        if !c.shell.enabled {
            c.bar.enabled = false
            for id in c.displays.keys { c.displays[id]?.barEnabled = false }
        }
        if !c.shell.isOn("osd") { c.input.interceptMediaKeys = false }
        return c
    }
}
