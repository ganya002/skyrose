import Foundation
import os

/// Unified logging. Window titles are redacted unless `Log.includeTitles` is enabled in config
/// (section 10.6).
public enum Log {
    public static let subsystem = "com.caelestia.mac"
    nonisolated(unsafe) public static var includeTitles = false

    public static let wm = Logger(subsystem: subsystem, category: "wm")
    public static let layout = Logger(subsystem: subsystem, category: "layout")
    public static let input = Logger(subsystem: subsystem, category: "input")
    public static let ax = Logger(subsystem: subsystem, category: "ax")
    public static let shell = Logger(subsystem: subsystem, category: "shell")
    public static let ipc = Logger(subsystem: subsystem, category: "ipc")
    public static let config = Logger(subsystem: subsystem, category: "config")
    public static let overlay = Logger(subsystem: subsystem, category: "overlay")
    public static let services = Logger(subsystem: subsystem, category: "services")

    /// Redacts a window title for logs unless the user opted in.
    public static func title(_ t: String) -> String {
        includeTitles ? t : (t.isEmpty ? "<empty>" : "<title \(t.count) chars>")
    }
}
