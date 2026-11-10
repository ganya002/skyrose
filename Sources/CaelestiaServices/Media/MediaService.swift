import AppKit
import Foundation
import CaelestiaCore

/// Now-playing information for the dashboard media card / tab.
public struct MediaState: Hashable, Sendable {
    public var available: Bool = false
    /// "Spotify" or "Music".
    public var player: String = ""
    public var playerBundleID: String = ""
    public var title: String = ""
    public var artist: String = ""
    public var album: String = ""
    public var isPlaying: Bool = false
    /// Seconds.
    public var position: Double = 0
    /// Seconds.
    public var duration: Double = 0
    /// Spotify: a remote `https://i.scdn.co/...` image. Music: a file under Application Support
    /// exported from the track's artwork. `nil` when unknown.
    public var artworkURL: URL? = nil
    /// Why nothing (or less) is shown — see `MediaService` for the full story.
    public var unavailableReason: String? = nil
    public init() {}
}

/// Media players this service can talk to with AppleScript.
public enum MediaPlayer: String, CaseIterable, Sendable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    public var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Music"
        }
    }

    /// Distributed notification each player posts on every playback change.
    var notificationName: Notification.Name {
        switch self {
        case .spotify: return Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .music: return Notification.Name("com.apple.Music.playerInfo")
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
    }
}

/// Now-playing + transport control without private frameworks.
///
/// macOS 15.4+ restricts `MediaRemote` (the framework behind the system "Now Playing" widget) to
/// Apple-entitled processes, so a general now-playing feed is not available to this app. This
/// service therefore reads **Spotify** and **Music** through AppleScript (Automation permission,
/// prompted per app the first time) and shows `unavailableReason` when neither runs:
/// "MediaRemote restricted on macOS 15.4+; using AppleScript for Spotify/Music".
///
/// Players are never launched: `NSRunningApplication` is checked before any Apple event.
/// Updates arrive instantly from the players' own distributed notifications
/// (`com.spotify.client.PlaybackStateChanged`, `com.apple.Music.playerInfo`); the 2 s position
/// refresh runs only while `isObserved` (the dashboard/media tab is open). Transport controls use
/// AppleScript when a player runs and otherwise post the NX media keys through `postMediaKey`,
/// which the WM may replace with its own event-tap poster.
@MainActor
public final class MediaService {
    public static let mediaRemoteNote = "MediaRemote restricted on macOS 15.4+; using AppleScript for Spotify/Music"
    public static let refreshInterval: TimeInterval = 2

    public private(set) var state = MediaState()
    public var onChange: ((MediaState) -> Void)?
    /// Media key poster used when no scriptable player is running.
    public var postMediaKey: (MediaKeyKind) -> Void = { MediaKeyPoster.post($0) }

    /// Set by the shell while the media card/tab is visible: enables the 2 s refresh.
    public var isObserved: Bool = false {
        didSet {
            guard isObserved != oldValue, running else { return }
            if isObserved {
                timer.start(interval: Self.refreshInterval, fireNow: true) { [weak self] in self?.refresh() }
            } else {
                timer.stop()
            }
        }
    }

    private let timer = MainTimer()
    private let scripts = AppleScriptRunner()
    private var observers: [NSObjectProtocol] = []
    private var artworkCacheKey: String = ""
    private var running = false

    public init() {}

    /// Moves the playing track when Spotify or Music is running. Other players have no seek.
    public func seek(to seconds: Double) {
        let player = MediaPlayer.allCases.first { $0.displayName == state.player && $0.isRunning }
        guard let player else { return }
        let t = max(0, seconds)
        let script = "tell application \"\(player.displayName)\" to set player position to \(t)"
        Task { _ = await scripts.run(script) }
    }

    public func start() {
        guard !running else { return }
        running = true
        let center = DistributedNotificationCenter.default()
        for player in MediaPlayer.allCases {
            observers.append(center.addObserver(forName: player.notificationName, object: nil, queue: .main) { [weak self] note in
                let info = (note.userInfo as? [String: Any]).map { Self.sendableInfo($0) } ?? [:]
                guard let self else { return }
                onMain { self.apply(notification: info, from: player) }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let bundle = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier ?? ""
                guard let self, MediaPlayer(rawValue: bundle) != nil else { return }
                onMain { self.refresh() }
            })
        }
        if isObserved {
            timer.start(interval: Self.refreshInterval, fireNow: true) { [weak self] in self?.refresh() }
        } else {
            refresh()
        }
    }

    public func stop() {
        guard running else { return }
        running = false
        timer.stop()
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    /// The running player we talk to (Spotify first, then Music).
    public var activePlayer: MediaPlayer? {
        if let current = MediaPlayer(rawValue: state.playerBundleID), current.isRunning { return current }
        return MediaPlayer.allCases.first { $0.isRunning }
    }

    // MARK: Controls

    public func playPause() { control(.playPause) }
    public func next() { control(.next) }
    public func previous() { control(.previous) }
    /// Pauses Spotify / stops Music (Caelestia `media stop`).
    public func stopPlayback() { control(.stop) }

    private enum Transport { case playPause, next, previous, stop }

    private func control(_ command: Transport) {
        guard let player = activePlayer else {
            switch command {
            case .playPause, .stop: postMediaKey(.play)
            case .next: postMediaKey(.next)
            case .previous: postMediaKey(.previous)
            }
            return
        }
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .stop: verb = player == .spotify ? "pause" : "stop"
        }
        let source = "tell application \"\(player.displayName)\" to \(verb)"
        Task { [weak self] in
            let result = await self?.scripts.run(source)
            if case .failure(let error)? = result {
                self?.note(error: error, player: player)
            } else {
                self?.refresh()
            }
        }
    }

    // MARK: Refresh

    /// Re-reads the active player with AppleScript (off the main thread).
    public func refresh() {
        guard let player = activePlayer else {
            var s = MediaState()
            s.unavailableReason = Self.mediaRemoteNote
            publish(s)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await self.scripts.run(Self.statusScript(for: player))
            switch result {
            case .success(let value):
                var s = Self.parseStatus(value, player: player, previous: self.state)
                if player == .music {
                    s.artworkURL = await self.musicArtwork(for: s)
                }
                self.publish(s)
            case .failure(let error):
                self.note(error: error, player: player)
            }
        }
    }

    private func publish(_ s: MediaState) {
        if s != state {
            state = s
            onChange?(s)
        }
    }

    private func note(error: AppleScriptRunner.Failure, player: MediaPlayer) {
        var s = state
        switch error {
        case .automationDenied:
            s = MediaState()
            s.player = player.displayName
            s.playerBundleID = player.rawValue
            s.unavailableReason = "Automation permission for \(player.displayName) is missing (System Settings → Privacy & Security → Automation)"
        case .notRunning:
            s = MediaState()
            s.unavailableReason = Self.mediaRemoteNote
        case .other(let code, let message):
            Log.services.error("AppleScript (\(player.displayName, privacy: .public)) failed \(code): \(message, privacy: .public)")
            s.unavailableReason = "\(player.displayName) did not answer (\(code))"
        }
        publish(s)
    }

    private func apply(notification info: [String: SendableValue], from player: MediaPlayer) {
        var s = state
        s.player = player.displayName
        s.playerBundleID = player.rawValue
        s.available = true
        s.unavailableReason = nil
        if case .string(let v)? = info["Name"] { s.title = v }
        if case .string(let v)? = info["Artist"] { s.artist = v }
        if case .string(let v)? = info["Album"] { s.album = v }
        if case .string(let v)? = info["Player State"] {
            s.isPlaying = v == "Playing"
            if v == "Stopped" { s.available = false }
        }
        if case .number(let ms)? = info["Duration"] { s.duration = ms / 1000 }
        if case .number(let ms)? = info["Total Time"] { s.duration = ms / 1000 }
        if case .number(let pos)? = info["Playback Position"] { s.position = pos }
        if player == .spotify, s.title != state.title || s.artist != state.artist { s.artworkURL = nil }
        publish(s)
        // The notification has no artwork/position for every player; fill in via AppleScript.
        refresh()
    }

    // MARK: Scripts

    nonisolated static func statusScript(for player: MediaPlayer) -> String {
        switch player {
        case .spotify:
            return """
            tell application "Spotify"
                set playerState to player state as string
                set pos to 0
                try
                    set pos to player position
                end try
                try
                    set t to current track
                    return {name of t, artist of t, album of t, (duration of t) / 1000, pos, playerState, artwork url of t}
                on error
                    return {"", "", "", 0, pos, playerState, ""}
                end try
            end tell
            """
        case .music:
            return """
            tell application "Music"
                set playerState to player state as string
                set pos to 0
                try
                    set pos to player position
                end try
                try
                    set t to current track
                    return {name of t, artist of t, album of t, duration of t, pos, playerState, ""}
                on error
                    return {"", "", "", 0, pos, playerState, ""}
                end try
            end tell
            """
        }
    }

    /// Parses the `{name, artist, album, duration, position, state, artworkURL}` list.
    nonisolated static func parseStatus(_ value: ScriptValue, player: MediaPlayer, previous: MediaState) -> MediaState {
        var s = MediaState()
        s.player = player.displayName
        s.playerBundleID = player.rawValue
        guard case .list(let items) = value, items.count >= 6 else {
            s.unavailableReason = "\(player.displayName) returned an unexpected answer"
            return s
        }
        s.title = items[0].stringValue
        s.artist = items[1].stringValue
        s.album = items[2].stringValue
        s.duration = items[3].doubleValue
        s.position = items[4].doubleValue
        let playerState = items[5].stringValue.lowercased()
        s.isPlaying = playerState == "playing"
        s.available = !s.title.isEmpty && playerState != "stopped"
        if items.count >= 7, let url = URL(string: items[6].stringValue), url.scheme != nil {
            s.artworkURL = url
        } else if player == .music {
            s.artworkURL = previous.artworkURL
        }
        if !s.available, s.title.isEmpty {
            s.unavailableReason = "\(player.displayName) is not playing anything"
        }
        return s
    }

    /// Exports Music's artwork once per track into Application Support/artwork.
    private func musicArtwork(for s: MediaState) async -> URL? {
        guard s.available else { return nil }
        let key = "\(s.title)|\(s.artist)|\(s.album)"
        if key == artworkCacheKey, let url = state.artworkURL, FileManager.default.fileExists(atPath: url.path) { return url }
        let script = """
        tell application "Music"
            try
                return data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
        """
        guard case .success(.data(let data, let type)) = await scripts.run(script), !data.isEmpty else { return nil }
        let ext: String
        switch type {
        case "JPEG": ext = "jpg"
        case "PNGf": ext = "png"
        default: ext = "tiff"
        }
        let dir = ServiceStorage.url("artwork")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = String(key.hashValue.magnitude, radix: 36)
        let url = dir.appendingPathComponent("music-\(name).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            artworkCacheKey = key
            return url
        } catch {
            Log.services.error("artwork export failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private nonisolated static func sendableInfo(_ info: [String: Any]) -> [String: SendableValue] {
        var out: [String: SendableValue] = [:]
        for (key, value) in info {
            if let s = value as? String { out[key] = .string(s) }
            else if let n = value as? NSNumber { out[key] = .number(n.doubleValue) }
        }
        return out
    }
}

/// Plain values extracted from `NSAppleEventDescriptor`s so results can cross threads.
public enum ScriptValue: Hashable, Sendable {
    case string(String)
    case number(Double)
    case list([ScriptValue])
    case data(Data, type: String)
    case none

    public var stringValue: String {
        switch self {
        case .string(let s): return s
        case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        default: return ""
        }
    }

    public var doubleValue: Double {
        switch self {
        case .number(let d): return d
        case .string(let s): return Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
        default: return 0
        }
    }

    static func from(_ descriptor: NSAppleEventDescriptor) -> ScriptValue {
        if descriptor.descriptorType == typeAEList {
            guard descriptor.numberOfItems > 0 else { return .list([]) }
            return .list((1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0) }.map(from))
        }
        switch descriptor.descriptorType {
        case typeSInt16, typeSInt32, typeSInt64, typeUInt16, typeUInt32, typeUInt64,
             typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint:
            return .number(descriptor.doubleValue)
        case typeTrue: return .number(1)
        case typeFalse: return .number(0)
        case typeNull: return .none
        default: break
        }
        if let string = descriptor.stringValue { return .string(string) }
        let code = descriptor.descriptorType
        let type = String(format: "%c%c%c%c", (code >> 24) & 0xFF, (code >> 16) & 0xFF, (code >> 8) & 0xFF, code & 0xFF)
        return .data(descriptor.data, type: type)
    }
}

/// Internal value type for notification payloads.
enum SendableValue: Sendable {
    case string(String)
    case number(Double)
}

/// Executes AppleScript on a private serial queue so an unresponsive target app (or the
/// Automation permission prompt, which blocks the calling thread) never stalls the main thread.
/// `NSAppleScript` is not thread-safe, so every run uses a fresh instance on that one queue.
final class AppleScriptRunner: @unchecked Sendable {
    enum Failure: Error, Sendable {
        /// `errAEEventNotPermitted` (-1743): Automation denied for the target app.
        case automationDenied
        /// `procNotFound` (-600) / `connectionInvalid` (-609): the app is not running.
        case notRunning
        case other(code: Int, message: String)
    }

    private let queue = DispatchQueue(label: "com.skyrose.mac.services.applescript", qos: .userInitiated)

    func run(_ source: String) async -> Result<ScriptValue, Failure> {
        await withCheckedContinuation { continuation in
            queue.async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .failure(.other(code: 0, message: "could not compile script")))
                    return
                }
                let descriptor = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                    let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
                    switch code {
                    case -1743: continuation.resume(returning: .failure(.automationDenied))
                    case -600, -609, -10810: continuation.resume(returning: .failure(.notRunning))
                    default: continuation.resume(returning: .failure(.other(code: code, message: message)))
                    }
                    return
                }
                continuation.resume(returning: .success(ScriptValue.from(descriptor)))
            }
        }
    }
}
