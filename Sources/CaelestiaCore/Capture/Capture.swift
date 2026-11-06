import CoreGraphics
import Foundation

/// What a screenshot captures (`skyrose screenshot <mode>`, the capture.* binds).
public enum CaptureMode: String, CaseIterable, Sendable {
    /// Drag a rectangle over the live screen (click = the window under the pointer). Linux: Print.
    case region
    /// The same picker over a still of the screen taken first (S+Sh+S).
    case freeze
    /// Click a window.
    case window
    /// The display under the pointer, at once (Sh+Print).
    case full

    public init?(argument: String?) {
        guard let a = argument?.lowercased(), !a.isEmpty else { self = .region; return }
        self.init(rawValue: a)
    }
}

/// Pure geometry and naming for the screenshot tool (tested without a screen).
public enum CaptureGeometry {
    /// A press and release closer than this is a click (select the window under the pointer).
    public static let clickTolerance: Double = 4

    /// The rectangle between two drag points.
    public static func selection(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    public static func isClick(from a: CGPoint, to b: CGPoint) -> Bool {
        abs(a.x - b.x) < clickTolerance && abs(a.y - b.y) < clickTolerance
    }

    /// `rect` (global points) inside `display` (global points), as display-local points; nil if
    /// they do not overlap.
    public static func local(_ rect: CGRect, in display: CGRect) -> CGRect? {
        let r = rect.intersection(display)
        guard !r.isNull, r.width >= 1, r.height >= 1 else { return nil }
        return r.offsetBy(dx: -display.minX, dy: -display.minY)
    }

    /// `local` (display points) as whole pixels of an image of that display at `scale`.
    public static func pixels(_ local: CGRect, scale: Double) -> CGRect {
        CGRect(x: (local.minX * scale).rounded(.down), y: (local.minY * scale).rounded(.down),
               width: (local.width * scale).rounded(), height: (local.height * scale).rounded())
    }

    /// The topmost window under `point` from window-list entries (front to back): a normal-layer
    /// window of another process, at least 8×8.
    public static func windowUnder(_ point: CGPoint, in windows: [WindowCandidate], excludingPID pid: pid_t) -> WindowCandidate? {
        windows.first { $0.layer == 0 && $0.pid != pid && $0.bounds.width >= 8 && $0.bounds.height >= 8 && $0.bounds.contains(point) }
    }

    public struct WindowCandidate: Equatable, Sendable {
        public var id: CGWindowID
        public var pid: pid_t
        public var layer: Int
        /// Global top-left points.
        public var bounds: CGRect
        public init(id: CGWindowID, pid: pid_t, layer: Int, bounds: CGRect) {
            self.id = id
            self.pid = pid
            self.layer = layer
            self.bounds = bounds
        }
    }

    /// "Screenshot 2026-11-06 at 09.15.24.png" (macOS's own pattern, so Finder sorts them with
    /// ⇧⌘3 shots); a second shot in the same second gets " (2)".
    public static func fileName(at date: Date, existing: (String) -> Bool = { _ in false }) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Screenshot \(f.string(from: date))"
        var name = "\(base).png"
        var n = 2
        while existing(name) {
            name = "\(base) (\(n)).png"
            n += 1
        }
        return name
    }

    /// `folder` with "~" expanded.
    public static func folderURL(_ folder: String) -> URL {
        URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Opt-in binds for macOS's own screenshot chords (`capture.overrideSystemShortcuts`): ⇧⌘3
    /// full, ⇧⌘4 region, ⇧⌘5 freeze. Written with whichever logical modifier is ⌘ in this preset;
    /// none (Caps Lock is Hyper) → no binds.
    public static func systemShortcutBinds(modifiers: ModifierMap) -> [Bind] {
        guard let cmd = LogicalModifier.allCases.first(where: { [.lcmd, .rcmd, .cmd].contains(modifiers[$0]) }), cmd != .shiftKey else { return [] }
        let defs: [(String, ActionKind, String, String)] = [
            ("full", .captureFull, "3", "full-screen screenshot"),
            ("region", .captureRegion, "4", "region screenshot"),
            ("freeze", .captureFreeze, "5", "frozen region screenshot"),
        ]
        return defs.compactMap { id, kind, key, what in
            let text = "\(cmd.rawValue) + SHIFT + \(key)"
            guard let chord = try? ChordParser.parse(text) else { return nil }
            return Bind(id: "capture.system.\(id)", keys: [text], action: Action(kind),
                        description: "\(what) (replaces macOS ⇧⌘\(key); capture.overrideSystemShortcuts)", chords: [chord])
        }
    }

    /// `keymap` plus the opt-in system-shortcut binds when `enabled`.
    public static func withSystemShortcuts(_ keymap: Keymap, enabled: Bool) -> Keymap {
        guard enabled else { return keymap }
        var k = keymap
        let ids = Set(k.binds.map(\.id))
        k.binds += systemShortcutBinds(modifiers: keymap.modifiers).filter { !ids.contains($0.id) }
        return k
    }
}
