import Darwin
import Foundation

/// Checks the daemon runs before it touches any window. Pure parts are separate from the
/// process-table read so they can be tested.
public enum LaunchChecks {
    /// Other window managers that move windows through AX. Two WMs fighting over the same windows
    /// leave the WM's state out of sync with the screen (first live test: CatWM running in the
    /// background). Keys are lowercased process names.
    public static let knownWindowManagers: [String: String] = [
        "catwm": "CatWM",
        "aerospace": "AeroSpace",
        "yabai": "yabai",
        "amethyst": "Amethyst",
        "chunkwm": "chunkwm",
        "spacey": "Spacey",
        // The pre-rename build of SkyRose itself (Caelestia for Mac): quit it with `caelestia wm quit`.
        "caelestiawm": "CaelestiaWM (the old Caelestia for Mac build)",
    ]

    /// Names of known window managers among `processNames` (sorted, without duplicates).
    public static func competingWindowManagers(processNames: [String]) -> [String] {
        Set(processNames.compactMap { knownWindowManagers[$0.lowercased()] }).sorted()
    }

    /// Short names of every process of the current user (best effort).
    public static func runningProcessNames() -> [String] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        let me = getpid()
        var names: [String] = []
        var buffer = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(filled)) where pid > 0 && pid != me {
            if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 { names.append(String(cString: buffer)) }
        }
        return names
    }

    public static func competingWindowManagerMessage(_ names: [String]) -> String {
        "\(names.joined(separator: ", ")) is running. Two window managers moving the same windows fight "
            + "each other, so SkyRose will not start. Quit \(names.count == 1 ? "it" : "them") first, then start SkyRose again."
    }

    public static let accessibilityMessage =
        "SkyRose needs Accessibility access to move and resize windows.\n\n"
        + "Turn on SkyRose in System Settings → Privacy & Security → Accessibility "
        + "(called “Device Control and Data Access” on newer macOS). "
        + "SkyRose starts by itself as soon as access is granted."
}
