import Foundation
import CoreGraphics
import Combine
import CaelestiaCore

/// Everything the shell draws comes from this observable state. The WM (CaelestiaWMKit) owns it
/// and mutates it on the main actor; the shell never calls into the WM except through
/// `ShellActions`. Keeping the dependency one-directional lets the shell be driven by a fake
/// state in previews and tests, and would let it move to a second process behind IPC later.
@MainActor
public final class ShellState: ObservableObject {
    @Published public var scheme: Scheme
    @Published public var config: Config
    @Published public var animations: AnimationTable
    /// Displays in CG top-left space plus the converter to AppKit space.
    @Published public var displays: [DisplayInfo]
    @Published public var converter: CoordinateConverter
    /// Per display id: the workspace pills to show.
    @Published public var workspaces: [String: [WorkspacePill]]
    /// Per display id: the open special workspace name, if any.
    @Published public var openSpecial: [String: String]
    @Published public var activeWindow: ActiveWindowInfo?
    @Published public var focusedDisplayID: String?
    @Published public var status: StatusInfo
    @Published public var notifications: [ShellNotification]
    @Published public var doNotDisturb: Bool
    @Published public var keepAwake: Bool
    /// When a timed keep-awake ends (nil = off or until turned off).
    @Published public var keepAwakeUntil: Date?
    /// The length the timed keep-awake was started with, for the sidebar chip highlight.
    @Published public var keepAwakeDuration: TimeInterval?
    /// Lid / power / external-display facts (sidebar clamshell line).
    @Published public var clamshell: ClamshellFacts
    /// Clamshell on/off, keep-awake and whether the `disablesleep` helper works.
    @Published public var lidSleep: LidSleepStatus
    @Published public var gameMode: Bool
    @Published public var recorder: RecorderInfo
    @Published public var media: MediaInfo
    @Published public var weather: WeatherInfo?
    @Published public var weatherStatus: WeatherStatus
    @Published public var performance: PerformanceInfo
    @Published public var capsLockOn: Bool
    /// Installed apps for the launcher (filled lazily by the WM's app index).
    @Published public var apps: [LaunchableApp]
    @Published public var wallpapers: [URL]
    @Published public var currentWallpaper: URL?
    /// macOS appearance (read only; changing it needs System Settings).
    @Published public var systemDarkMode: Bool
    @Published public var secureInputApp: String?
    @Published public var reduceMotion: Bool

    public init(scheme: Scheme, config: Config, animations: AnimationTable, displays: [DisplayInfo], converter: CoordinateConverter) {
        self.scheme = scheme
        self.config = config
        self.animations = animations
        self.displays = displays
        self.converter = converter
        self.workspaces = [:]
        self.openSpecial = [:]
        self.activeWindow = nil
        self.focusedDisplayID = displays.first?.id
        self.status = StatusInfo()
        self.notifications = []
        self.doNotDisturb = false
        self.keepAwake = false
        self.keepAwakeUntil = nil
        self.keepAwakeDuration = nil
        self.clamshell = ClamshellFacts(hasLid: false, lidClosed: false, onAC: true, externalDisplays: 0)
        self.lidSleep = LidSleepStatus()
        self.gameMode = false
        self.recorder = RecorderInfo()
        self.media = MediaInfo()
        self.weather = nil
        self.weatherStatus = .notConfigured
        self.performance = PerformanceInfo()
        self.capsLockOn = false
        self.apps = []
        self.wallpapers = []
        self.currentWallpaper = nil
        self.systemDarkMode = true
        self.secureInputApp = nil
        self.reduceMotion = false
    }
}

public struct WorkspacePill: Hashable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var occupied: Bool
    public var active: Bool
    public var windowCount: Int
    /// Bundle ids of the workspace's windows, in tiling order, at most `maxWindowIcons`
    /// (Caelestia `bar.workspaces.showWindows`): the bar draws their app icons in the pill.
    public var apps: [String]
    /// Caelestia `bar.workspaces.maxWindowIcons`.
    public static let maxWindowIcons = 5
    public init(id: Int, name: String, occupied: Bool, active: Bool, windowCount: Int, apps: [String] = []) {
        self.id = id
        self.name = name
        self.occupied = occupied
        self.active = active
        self.windowCount = windowCount
        self.apps = Array(apps.prefix(Self.maxWindowIcons))
    }
}

public struct ActiveWindowInfo: Hashable, Sendable {
    public var windowID: UInt32
    public var title: String
    public var appName: String
    public var bundleID: String
    public var displayID: String
    public init(windowID: UInt32, title: String, appName: String, bundleID: String, displayID: String) {
        self.windowID = windowID
        self.title = title
        self.appName = appName
        self.bundleID = bundleID
        self.displayID = displayID
    }
}

public struct StatusInfo: Hashable, Sendable {
    public var volume: Double = 0.5
    public var muted: Bool = false
    public var outputDeviceName: String = ""
    public var micMuted: Bool = false
    public var micVolume: Double = 1
    public var wifiAvailable: Bool = true
    public var wifiEnabled: Bool = true
    public var wifiConnected: Bool = false
    public var ssid: String? = nil
    public var wifiStrength: Int = 0
    public var ethernetConnected: Bool = false
    public var bluetoothAvailable: Bool = false
    public var bluetoothOn: Bool = false
    public var bluetoothDevices: [String] = []
    public var hasBattery: Bool = false
    public var batteryPercent: Int = 0
    public var batteryCharging: Bool = false
    public var batteryTimeRemainingMinutes: Int? = nil
    public var batteryPluggedIn: Bool = false
    public var lowPowerMode: Bool = false
    public var inputDeviceName: String = ""
    public var keyboardLayout: String = ""
    public var brightness: Double = 1
    public init() {}
}

public struct ShellNotification: Hashable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var appName: String
    public var appBundleID: String
    public var summary: String
    public var body: String
    public var icon: String
    public var date: Date
    public var actions: [String]
    public var urgency: String
    public init(id: UUID = UUID(), appName: String, appBundleID: String = "", summary: String, body: String = "", icon: String = "", date: Date = Date(), actions: [String] = [], urgency: String = "normal") {
        self.id = id
        self.appName = appName
        self.appBundleID = appBundleID
        self.summary = summary
        self.body = body
        self.icon = icon
        self.date = date
        self.actions = actions
        self.urgency = urgency
    }
}

public struct RecorderInfo: Hashable, Sendable {
    public enum State: String, Sendable { case ready, recording, paused, unavailable }
    public var state: State = .ready
    public var mode: String = "fullscreen"
    public var recordings: [URL] = []
    public var startedAt: Date? = nil
    public var unavailableReason: String? = nil
    public init() {}
}

public struct MediaInfo: Hashable, Sendable {
    public var available: Bool = false
    public var title: String = ""
    public var artist: String = ""
    public var album: String = ""
    public var isPlaying: Bool = false
    public var position: Double = 0
    public var duration: Double = 0
    public var artworkPath: URL? = nil
    public var player: String = ""
    public init() {}
}

public struct WeatherInfo: Hashable, Sendable {
    public var temperatureC: Double
    public var description: String
    /// SF Symbol name.
    public var icon: String
    public var location: String
    public var hourly: [HourlyForecast]
    public var daily: [DailyForecast]
    public var feelsLikeC: Double?
    public var humidity: Int?
    public var windKmh: Double?
    public var sunrise: Date?
    public var sunset: Date?
    public var updated: Date?
    public init(temperatureC: Double, description: String, icon: String, location: String, hourly: [HourlyForecast] = [], daily: [DailyForecast] = [],
                feelsLikeC: Double? = nil, humidity: Int? = nil, windKmh: Double? = nil, sunrise: Date? = nil, sunset: Date? = nil, updated: Date? = nil) {
        self.temperatureC = temperatureC
        self.description = description
        self.icon = icon
        self.location = location
        self.hourly = hourly
        self.daily = daily
        self.feelsLikeC = feelsLikeC
        self.humidity = humidity
        self.windKmh = windKmh
        self.sunrise = sunrise
        self.sunset = sunset
        self.updated = updated
    }
    public struct HourlyForecast: Hashable, Sendable { public var time: Date; public var temperatureC: Double; public var icon: String; public var precipitationChance: Int?
        public init(time: Date, temperatureC: Double, icon: String, precipitationChance: Int? = nil) { self.time = time; self.temperatureC = temperatureC; self.icon = icon; self.precipitationChance = precipitationChance } }
    public struct DailyForecast: Hashable, Sendable { public var date: Date; public var minC: Double; public var maxC: Double; public var icon: String; public var description: String; public var precipitationChance: Int?
        public init(date: Date, minC: Double, maxC: Double, icon: String, description: String = "", precipitationChance: Int? = nil) { self.date = date; self.minC = minC; self.maxC = maxC; self.icon = icon; self.description = description; self.precipitationChance = precipitationChance } }
}

/// Where the weather is at: the shell shows text for each state, never made-up numbers.
public enum WeatherStatus: Hashable, Sendable {
    /// No city set and the location is off.
    case notConfigured
    case loading
    case ready
    /// The last fetch failed (the previous report, if any, stays shown with its time).
    case failed(String)
}

/// °C or °F text for a Celsius value.
public enum WeatherText {
    public static func temperature(_ c: Double, fahrenheit: Bool, unit: Bool = true) -> String {
        let v = fahrenheit ? c * 9 / 5 + 32 : c
        let n = Int(v.rounded())
        return unit ? "\(n)°\(fahrenheit ? "F" : "C")" : "\(n)°"
    }
}

public struct PerformanceInfo: Hashable, Sendable {
    public var cpuPercent: Double = 0
    public var gpuPercent: Double? = nil
    public var memoryUsedBytes: UInt64 = 0
    public var memoryTotalBytes: UInt64 = 0
    public var storageUsedBytes: UInt64 = 0
    public var storageTotalBytes: UInt64 = 0
    public var networkUpBytesPerSec: Double = 0
    public var networkDownBytesPerSec: Double = 0
    /// SoC die average (CPU), from the HID sensors; nil = not readable on this Mac (hidden).
    public var temperatureC: Double? = nil
    public var cpuMaxTemperatureC: Double? = nil
    public var gpuTemperatureC: Double? = nil
    public var batteryTemperatureC: Double? = nil
    public var ssdTemperatureC: Double? = nil
    public var temperatureHistory: [Double] = []
    public var cpuHistory: [Double] = []
    public var memoryHistory: [Double] = []
    public var uptimeSeconds: Double = 0
    public var thermalState: Int = 0
    public var networkUpHistory: [Double] = []
    public var networkDownHistory: [Double] = []
    public var osVersion: String = ""
    public init() {}
}

public struct LaunchableApp: Hashable, Sendable, Identifiable {
    public var id: String { bundleID.isEmpty ? url.path : bundleID }
    public var name: String
    public var bundleID: String
    public var url: URL
    public var description: String
    public var keywords: [String]
    public var launchCount: Int
    public init(name: String, bundleID: String, url: URL, description: String = "", keywords: [String] = [], launchCount: Int = 0) {
        self.name = name
        self.bundleID = bundleID
        self.url = url
        self.description = description
        self.keywords = keywords
        self.launchCount = launchCount
    }
}

/// Drawers the shell can open (Caelestia `drawers` IPC target names).
public enum Drawer: String, CaseIterable, Sendable, Codable {
    case launcher, dashboard, sidebar, session, osd, utilities, wallpaper, clipboard
}

/// What the shell asks the WM / services to do. Implemented by CaelestiaWMKit.
@MainActor
public protocol ShellActions: AnyObject {
    func perform(_ action: Action)
    func focusWorkspace(_ id: Int, display: String)
    func launch(app: LaunchableApp)
    func runLauncherCommand(_ command: String)
    func setWallpaper(_ url: URL, display: String?)
    func setVolume(_ value: Double)
    func setMuted(_ muted: Bool)
    func setMicMuted(_ muted: Bool)
    func setBrightness(_ value: Double)
    func setKeepAwake(_ on: Bool)
    func setDoNotDisturb(_ on: Bool)
    func setGameMode(_ on: Bool)
    func setWifi(_ on: Bool)
    func openBluetoothSettings()
    func openSettingsApp()
    func mediaPlayPause()
    func mediaNext()
    func mediaPrevious()
    func recorderStart(mode: String, withSound: Bool)
    func recorderStop()
    func revealRecording(_ url: URL)
    func trashRecording(_ url: URL)
    func dismissNotification(_ id: UUID)
    func clearNotifications()
    func notificationAction(_ id: UUID, action: String)
    func session(_ action: SessionAction)
    func revealMenuBar()
}

public enum SessionAction: String, Sendable, CaseIterable {
    case logout, shutdown, sleep, reboot, lock
}
