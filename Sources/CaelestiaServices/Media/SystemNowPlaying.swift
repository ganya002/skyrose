import AppKit
import Foundation

/// The system Now Playing item: what a browser tab (YouTube Music) or any other player reports.
///
/// macOS 15.4+ refuses `MediaRemote` to ordinary apps but still answers Apple's own tools, so
/// `osascript` reads it. Nothing is written and no player is touched. It returns no track when
/// the call stops working, and SkyRose falls back to Spotify and Music through AppleScript.
enum SystemNowPlaying {
    static let script = """
    ObjC.import('Foundation');
    function run() {
      $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
      const R = $.NSClassFromString('MRNowPlayingRequest');
      const info = R.localNowPlayingItem.nowPlayingInfo;
      if (!info || !info.js) return '{}';
      const key = k => { const v = info.objectForKey('kMRMediaRemoteNowPlayingInfo' + k); return v && v.js !== undefined ? ObjC.unwrap(v) : undefined; };
      const when = key('Timestamp');
      const client = R.localNowPlayingPlayerPath.client;
      return JSON.stringify({
        bundle: ObjC.unwrap(client.bundleIdentifier), name: ObjC.unwrap(client.displayName),
        title: key('Title'), artist: key('Artist'), album: key('Album'),
        duration: key('Duration'), elapsed: key('ElapsedTime'), rate: key('PlaybackRate'),
        timestamp: when ? when.getTime() / 1000 : undefined, playing: R.localIsPlaying
      });
    }
    """

    /// The state in `json`, or nil when nothing is playing.
    static func parse(_ json: Data, now: Date, appName: (String) -> String? = { _ in nil }) -> MediaState? {
        guard let o = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let title = o["title"] as? String, !title.isEmpty else { return nil }
        var s = MediaState()
        let bundle = o["bundle"] as? String ?? ""
        s.available = true
        s.title = title
        s.artist = o["artist"] as? String ?? ""
        s.album = o["album"] as? String ?? ""
        s.playerBundleID = bundle
        s.player = (o["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appName(bundle) ?? bundle
        s.duration = (o["duration"] as? NSNumber)?.doubleValue ?? 0
        let rate = (o["rate"] as? NSNumber)?.doubleValue ?? 0
        s.isPlaying = (o["playing"] as? Bool) ?? (rate > 0)
        var position = (o["elapsed"] as? NSNumber)?.doubleValue ?? 0
        if s.isPlaying, let stamp = (o["timestamp"] as? NSNumber)?.doubleValue, stamp > 0 {
            position += max(0, now.timeIntervalSince1970 - stamp) * max(rate, 1)
        }
        s.position = s.duration > 0 ? min(position, s.duration) : position
        return s
    }

    /// Runs off the main thread and gives up after 2 s.
    static func read() async -> MediaState? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-l", "JavaScript", "-e", script]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = Pipe()
                guard (try? p.run()) != nil else {
                    continuation.resume(returning: nil)
                    return
                }
                let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: watchdog)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                watchdog.cancel()
                let name: (String) -> String? = { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.localizedName }
                continuation.resume(returning: p.terminationStatus == 0 ? parse(data, now: Date(), appName: name) : nil)
            }
        }
    }
}
