import AppKit
import CaelestiaCore
import Darwin
import Foundation
import IOKit.ps

/// Facts about the machine and the installed app, gathered with read-only calls.
enum Environment {
    /// Bundle identifier of the WM agent app (spec section 1: prefix `com.skyrose.mac`).
    static let wmBundleID = "com.skyrose.mac"
    /// Bundle identifier of the Settings app.
    static let settingsBundleID = "com.skyrose.mac.settings"

    /// "15.1 (24B83)".
    static var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let build = sysctlString("kern.osversion") ?? ""
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)" + (build.isEmpty ? "" : " (\(build))")
    }

    /// "arm64" / "x86_64".
    static var architecture: String {
        var u = utsname()
        uname(&u)
        return withUnsafePointer(to: &u.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }

    /// "Mac15,3", "MacBookAir10,1", ...
    static var model: String { sysctlString("hw.model") ?? "unknown" }

    /// True when IOKit reports an internal battery (MacBook); drives the "keys a MacBook lacks" check.
    static var isLaptop: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType { return true }
        }
        return false
    }

    /// Path of the active developer directory (`xcode-select -p`), nil when none is selected.
    static var developerDirectory: String? {
        let r = run("/usr/bin/xcode-select", ["-p"], timeout: 5)
        guard r.status == 0 else { return nil }
        let path = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// SIP status from `csrutil status` (read-only): "enabled", "disabled", "custom", or nil.
    static var sipStatus: String? {
        switch SIPStatus.parse(SIPStatus.readCSRUtil()) {
        case .enabled: return "enabled"
        case .custom: return "enabled (custom configuration)"
        case .disabled: return "disabled"
        case .unknown: return nil
        }
    }

    /// Location of the installed WM app, if Launch Services knows one.
    static var wmAppURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: wmBundleID)
    }

    /// Location of SkyRose Settings: next to the app this CLI runs from, else Launch Services.
    static var settingsAppURL: URL? {
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            // …/SkyRose.app/Contents/MacOS/skyrose → …/SkyRose Settings.app
            let sibling = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("SkyRose Settings.app")
            if FileManager.default.fileExists(atPath: sibling.path) { return sibling }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: settingsBundleID)
    }

    /// CFBundleShortVersionString of an app bundle.
    static func bundleVersion(_ url: URL) -> String? {
        Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The repository root when this binary runs from a SwiftPM build directory, found by walking
    /// up from the executable to a directory with `Package.swift`. `SKYROSE_REPO` overrides it.
    static var repositoryRoot: URL? {
        if let env = ProcessInfo.processInfo.environment["SKYROSE_REPO"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
        }
        var dir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            guard let d = dir else { break }
            if FileManager.default.fileExists(atPath: d.appendingPathComponent("Package.swift").path),
                FileManager.default.fileExists(atPath: d.appendingPathComponent("Sources/skyrose").path)
            {
                return d
            }
            if d.path == "/" { break }
            dir = d.deletingLastPathComponent()
        }
        return nil
    }

    /// Home-relative rendering for messages ("~/.config/...").
    static func tilde(_ url: URL) -> String {
        let home = Paths.home.path
        let p = url.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    // MARK: Processes

    struct ProcessResult {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    /// Runs a program with captured output. Never throws: a launch failure is status 127.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return ProcessResult(status: 127, stdout: "", stderr: error.localizedDescription)
        }
        // Drain both pipes concurrently so a chatty stderr cannot stall stdout (or vice versa).
        let out = OutputBuffer()
        let err = OutputBuffer()
        let group = DispatchGroup()
        for (pipe, buffer) in [(outPipe, out), (errPipe, err)] {
            group.enter()
            DispatchQueue.global().async {
                buffer.set(pipe.fileHandleForReading.readDataToEndOfFile())
                group.leave()
            }
        }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        p.waitUntilExit()
        group.wait()
        killer.cancel()
        return ProcessResult(
            status: p.terminationStatus,
            stdout: String(decoding: out.get(), as: UTF8.self),
            stderr: String(decoding: err.get(), as: UTF8.self)
        )
    }

    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func set(_ d: Data) { lock.withLock { data = d } }
        func get() -> Data { lock.withLock { data } }
    }

    /// Runs a program with the terminal attached (for interactive scripts) and returns its status.
    static func runInteractive(_ executable: String, _ arguments: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.standardInput = FileHandle.standardInput
        p.standardOutput = FileHandle.standardOutput
        p.standardError = FileHandle.standardError
        do {
            try p.run()
        } catch {
            Console.error("cannot run \(executable): \(error.localizedDescription)")
            return 127
        }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}
