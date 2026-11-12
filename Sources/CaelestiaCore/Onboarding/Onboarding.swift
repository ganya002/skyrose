import Foundation

/// The permissions SkyRose asks for (Automation and Microphone are asked by macOS only when you
/// use the feature that needs them). Location and Bluetooth are optional, for the Wi-Fi and
/// Bluetooth panels.
public enum SkyRosePermission: String, Codable, CaseIterable, Sendable, Hashable {
    case accessibility
    case inputMonitoring
    case screenRecording
    case location
    case bluetooth

    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        case .screenRecording: return "Screen Recording"
        case .location: return "Location"
        case .bluetooth: return "Bluetooth"
        }
    }

    /// One plain sentence: what SkyRose does with it.
    public var why: String {
        switch self {
        case .accessibility: return "Lets SkyRose move, resize and focus your windows. This is what tiling is."
        case .inputMonitoring: return "Lets SkyRose hear its keyboard shortcuts, like ⌥ + T for a terminal."
        case .screenRecording: return "Lets SkyRose take still pictures of windows so they can glide smoothly. Nothing is saved or sent anywhere."
        case .location: return "macOS only shows Wi-Fi network names to apps with Location. SkyRose uses it for the Wi-Fi panel, never to track you."
        case .bluetooth: return "Lets the Bluetooth panel list, connect and pair your devices."
        }
    }

    /// What stops working without it.
    public var withoutIt: String {
        switch self {
        case .accessibility: return "Nothing tiles."
        case .inputMonitoring: return "No keyboard shortcuts."
        case .screenRecording: return "Windows jump instead of gliding."
        case .location: return "The Wi-Fi panel can't see network names, so you can't pick a network there."
        case .bluetooth: return "The Bluetooth panel can't show or connect devices."
        }
    }

    /// The name of the list in System Settings › Privacy & Security.
    public var paneName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        case .screenRecording: return "Screen & System Audio Recording"
        case .location: return "Location Services"
        case .bluetooth: return "Bluetooth"
        }
    }

    /// The exact System Settings pane.
    public var settingsURL: URL {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .screenRecording: anchor = "Privacy_ScreenCapture"
        case .location: anchor = "Privacy_LocationServices"
        case .bluetooth: anchor = "Privacy_Bluetooth"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    /// Location and Bluetooth only serve the Wi-Fi and Bluetooth panels: turning them off is a
    /// choice, never a reason to reopen onboarding.
    public var isOptional: Bool { self == .location || self == .bluetooth }

    /// Required in a mode, or only recommended (Screen Recording is never required).
    public func isRequired(in mode: GeneralConfig.Mode) -> Bool { self == .accessibility || self == .inputMonitoring }

    /// macOS applies a new Screen Recording grant only after the app restarts.
    public var needsRestartAfterGrant: Bool { self == .screenRecording }
}

/// One snapshot of the three permissions, as the WM process sees them (TCC is per process: the
/// Settings app asks the WM over IPC, never checks itself).
public struct PermissionSnapshot: Codable, Equatable, Sendable {
    public var accessibility: Bool
    public var inputMonitoring: Bool
    public var screenRecording: Bool
    public var location: Bool
    public var bluetooth: Bool

    public init(accessibility: Bool, inputMonitoring: Bool, screenRecording: Bool, location: Bool = false, bluetooth: Bool = false) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
        self.screenRecording = screenRecording
        self.location = location
        self.bluetooth = bluetooth
    }

    private enum CodingKeys: String, CodingKey { case accessibility, inputMonitoring, screenRecording, location, bluetooth }

    /// Snapshots written before Location and Bluetooth existed decode with both off.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessibility = try c.decode(Bool.self, forKey: .accessibility)
        inputMonitoring = try c.decode(Bool.self, forKey: .inputMonitoring)
        screenRecording = try c.decode(Bool.self, forKey: .screenRecording)
        location = try c.decodeIfPresent(Bool.self, forKey: .location) ?? false
        bluetooth = try c.decodeIfPresent(Bool.self, forKey: .bluetooth) ?? false
    }

    public static let none = PermissionSnapshot(accessibility: false, inputMonitoring: false, screenRecording: false)

    public func isGranted(_ p: SkyRosePermission) -> Bool {
        switch p {
        case .accessibility: return accessibility
        case .inputMonitoring: return inputMonitoring
        case .screenRecording: return screenRecording
        case .location: return location
        case .bluetooth: return bluetooth
        }
    }

    public var granted: Set<SkyRosePermission> { Set(SkyRosePermission.allCases.filter(isGranted)) }

    /// `SKYROSE_SIMULATE_MISSING=accessibility,screenRecording` (or the `--simulate-missing`
    /// flag of the Settings app) reports those as missing without touching the real grants:
    /// for tests and screenshots only.
    public func simulatingMissing(_ missing: Set<SkyRosePermission>) -> PermissionSnapshot {
        var s = self
        if missing.contains(.accessibility) { s.accessibility = false }
        if missing.contains(.inputMonitoring) { s.inputMonitoring = false }
        if missing.contains(.screenRecording) { s.screenRecording = false }
        if missing.contains(.location) { s.location = false }
        if missing.contains(.bluetooth) { s.bluetooth = false }
        return s
    }

    public static func parseSimulated(_ text: String?) -> Set<SkyRosePermission> {
        guard let text, !text.isEmpty else { return [] }
        return Set(text.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { SkyRosePermission(rawValue: String($0)) })
    }
}

/// Remembers which permissions were ever seen granted, so a later loss (macOS sometimes drops a
/// grant after an update, or the user unticks it) reopens only that onboarding step. Owned by
/// the WM process (`permissions-seen.json`).
public struct PermissionHistory: Codable, Equatable, Sendable {
    public var everGranted: Set<SkyRosePermission> = []
    /// Losses already reported (cleared when the permission comes back), so the step opens once
    /// per loss, not on every check.
    public var reportedLost: Set<SkyRosePermission> = []

    public init(everGranted: Set<SkyRosePermission> = [], reportedLost: Set<SkyRosePermission> = []) {
        self.everGranted = everGranted
        self.reportedLost = reportedLost
    }

    /// Records `snapshot` and returns the permissions newly lost (granted before, missing now,
    /// not reported yet). The caller opens the onboarding permission step for exactly those.
    public mutating func observe(_ snapshot: PermissionSnapshot) -> [SkyRosePermission] {
        var lost: [SkyRosePermission] = []
        for p in SkyRosePermission.allCases where !p.isOptional {
            if snapshot.isGranted(p) {
                everGranted.insert(p)
                reportedLost.remove(p)
            } else if everGranted.contains(p), !reportedLost.contains(p) {
                reportedLost.insert(p)
                lost.append(p)
            }
        }
        return lost
    }

    public static var url: URL { Paths.appSupport.appendingPathComponent("permissions-seen.json") }

    public static func load(from url: URL = url) -> PermissionHistory {
        guard let data = try? Data(contentsOf: url), let h = try? JSONDecoder().decode(PermissionHistory.self, from: data) else {
            return PermissionHistory()
        }
        return h
    }

    public func save(to url: URL = url) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// The onboarding steps, in order.
public enum OnboardingStep: String, Codable, CaseIterable, Sendable {
    case welcome, mode, permissions, tweaks, extras, kitty, fonts, corners, done

    /// First run, in order: mode, permissions, one recommended-setup step, kitty and fonts, done.
    public static let guided: [OnboardingStep] = [.mode, .permissions, .tweaks, .extras, .done]

    public var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .mode: return "Pick a mode"
        case .permissions: return "Permissions"
        case .tweaks: return "Recommended"
        case .extras: return "kitty and fonts"
        case .kitty: return "kitty"
        case .fonts: return "Fonts"
        case .corners: return "Corners"
        case .done: return "All set"
        }
    }
}

/// Onboarding progress (`onboarding.json`, written by the Settings app).
public struct OnboardingState: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int = OnboardingState.currentVersion
    public var completed: Bool = false
    public var completedAt: Date?

    public init(completed: Bool = false, completedAt: Date? = nil) {
        self.completed = completed
        self.completedAt = completedAt
    }

    public static func load(from url: URL = Paths.onboardingState) -> OnboardingState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let s = try? decoder.decode(OnboardingState.self, from: data) else {
            return OnboardingState()
        }
        return s
    }

    public func save(to url: URL = Paths.onboardingState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// Where an onboarding run starts and what it shows.
public struct OnboardingRequest: Equatable, Sendable {
    /// Steps shown, in order.
    public var steps: [OnboardingStep]
    /// Permission step: only these permissions (a lost grant), or all three when empty.
    public var onlyPermissions: [SkyRosePermission]

    public init(steps: [OnboardingStep] = OnboardingStep.guided, onlyPermissions: [SkyRosePermission] = []) {
        self.steps = steps
        self.onlyPermissions = onlyPermissions
    }

    /// The full first-run flow.
    public static let firstRun = OnboardingRequest()

    /// Just the permission step for `lost` (a grant that went away later).
    public static func repair(_ lost: [SkyRosePermission]) -> OnboardingRequest {
        OnboardingRequest(steps: [.permissions], onlyPermissions: lost)
    }

    /// Command-line arguments for the Settings app (`--onboarding [--only a,b]`).
    public var arguments: [String] {
        var a = ["--onboarding"]
        if steps == [.permissions] { a.append("--repair") }
        if !onlyPermissions.isEmpty { a += ["--only", onlyPermissions.map(\.rawValue).joined(separator: ",")] }
        return a
    }

    /// Parses `arguments`; nil when `--onboarding` is absent.
    public static func parse(_ args: [String]) -> OnboardingRequest? {
        guard args.contains("--onboarding") else { return nil }
        var only: [SkyRosePermission] = []
        if let i = args.firstIndex(of: "--only"), i + 1 < args.count {
            only = args[i + 1].split(separator: ",").compactMap { SkyRosePermission(rawValue: String($0)) }
        }
        if args.contains("--repair") { return .repair(only) }
        return OnboardingRequest(onlyPermissions: only)
    }
}
