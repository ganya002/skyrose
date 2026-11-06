import AppKit
import CaelestiaCore
import SwiftUI

/// Session menu state (spec 5.7): Log out, Shut down, [image], Sleep, Restart. Every action needs
/// a second press within `armWindow` (the confirm step); Esc disarms, then closes.
@MainActor
public final class SessionModel: ObservableObject {
    public static let actions: [SessionAction] = [.logout, .shutdown, .sleep, .reboot]
    public static let armWindow: TimeInterval = 3

    @Published public var focused = 0
    @Published public private(set) var armed: SessionAction?
    @Published public var shown = false
    private var armedAt: Date?
    public var now: () -> Date = Date.init
    public var onRun: (SessionAction) -> Void = { _ in }
    public var onClose: () -> Void = {}

    public init() {}

    public var focusedAction: SessionAction { Self.actions[focused] }

    public func move(_ delta: Int) {
        focused = (focused + delta + Self.actions.count) % Self.actions.count
        if armed != focusedAction { disarm() }
    }

    /// First press arms, the second (same action, within the window) runs it.
    public func press(_ action: SessionAction) {
        if let i = Self.actions.firstIndex(of: action) { focused = i }
        if armed == action, let t = armedAt, now().timeIntervalSince(t) <= Self.armWindow {
            disarm()
            onRun(action)
        } else {
            armed = action
            armedAt = now()
        }
    }

    public func pressFocused() { press(focusedAction) }

    public func escape() {
        if armed != nil { disarm() } else { onClose() }
    }

    public func disarm() {
        armed = nil
        armedAt = nil
    }

    public func reset() {
        focused = 0
        disarm()
    }

    /// Material Symbols names from Caelestia's session menu.
    public static func icon(_ a: SessionAction) -> String {
        switch a {
        case .logout: return "logout"
        case .shutdown: return "power_settings_new"
        case .sleep: return "downloading"
        case .reboot: return "cached"
        case .lock: return "lock"
        }
    }

    public static func label(_ a: SessionAction) -> String {
        switch a {
        case .logout: return "Log out"
        case .shutdown: return "Shut down"
        case .sleep: return "Sleep"
        case .reboot: return "Restart"
        case .lock: return "Lock"
        }
    }

    // Geometry measured on 1-session.jpg (1 px = 1 pt).
    public static let button: Double = 80
    public static let spacing: Double = 15
    public static let padding: Double = 15
    public static let rounding: Double = 22
    public static var bodySize: CGSize {
        let n = Double(actions.count + 1)
        return CGSize(width: button + 2 * padding, height: n * button + (n - 1) * spacing + 2 * padding)
    }
}

struct SessionView: View {
    @ObservedObject var model: SessionModel
    @Environment(\.shellTheme) var theme
    let fillet: Double

    var body: some View {
        let size = SessionModel.bodySize
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack {
                DrawerBackground(edge: .right, fillet: fillet, radius: theme.frameRounding, shown: model.shown, depth: size.width)
                VStack(spacing: SessionModel.spacing) {
                    button(.logout)
                    button(.shutdown)
                    SessionMascot()
                        .frame(width: SessionModel.button, height: SessionModel.button)
                    button(.sleep)
                    button(.reboot)
                }
                .liquidContent(edge: .right, shown: model.shown, depth: size.width, theme: theme)
            }
            .frame(width: size.width, height: size.height + 2 * fillet)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { model.move(-1); return .handled }
        .onKeyPress(.downArrow) { model.move(1); return .handled }
        .onKeyPress(.tab) { model.move(1); return .handled }
        .onKeyPress(.return) { model.pressFocused(); return .handled }
        .onKeyPress(.space) { model.pressFocused(); return .handled }
        .onKeyPress(.escape) { model.escape(); return .handled }
    }

    private func button(_ action: SessionAction) -> some View {
        let focused = model.focusedAction == action
        let armed = model.armed == action
        return Button { model.press(action) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: SessionModel.rounding, style: .continuous)
                    .fill(armed ? theme[.error] : theme[.onSurface].opacity(focused ? 0.18 : 0.11))
                MaterialIcon(armed ? "checkmark" : SessionModel.icon(action), size: 26, weight: .regular)
                    .foregroundStyle(armed ? theme[.onError] : theme[.onSurface])
            }
            .frame(width: SessionModel.button, height: SessionModel.button)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0, let i = SessionModel.actions.firstIndex(of: action) { model.focused = i } }
        .help(armed ? "Press again to \(SessionModel.label(action).lowercased())" : SessionModel.label(action))
        .accessibilityIdentifier("session.\(action.rawValue)")
        .animation(theme.small, value: focused)
        .animation(theme.small, value: armed)
    }
}

/// The animated image slot between the buttons (Caelestia shows a character gif; ours is drawn).
struct SessionMascot: View {
    @Environment(\.shellTheme) var theme
    @State private var bob = false

    var body: some View {
        MaterialIcon("bedtime", size: 34, fill: true)
            .symbolRenderingMode(.palette)
            .foregroundStyle(theme[.tertiary], theme[.primary])
            .offset(y: bob ? -4 : 4)
            .animation(theme.reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: bob)
            .onAppear { bob = true }
    }
}

/// Runs a session action through public routes only (spec 5.7 / 5.8). Never sudo.
public enum SessionCommands {
    /// What `run` executes, for tests and the log: an executable and its arguments.
    public static func command(for action: SessionAction) -> (path: String, args: [String])? {
        switch action {
        case .logout: return ("/usr/bin/osascript", ["-e", "tell application \"System Events\" to log out"])
        case .shutdown: return ("/usr/bin/osascript", ["-e", "tell application \"System Events\" to shut down"])
        case .reboot: return ("/usr/bin/osascript", ["-e", "tell application \"System Events\" to restart"])
        case .sleep: return ("/usr/bin/pmset", ["sleepnow"])
        case .lock: return nil  // ⌃⌘Q, posted as a key event
        }
    }

    public static func run(_ action: SessionAction) {
        if action == .lock { return postLockShortcut() }
        guard let (path, args) = command(for: action) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }

    /// ⌃⌘Q: the system "Lock Screen" shortcut, so the real macOS lock screen protects the session.
    static func postLockShortcut() {
        let src = CGEventSource(stateID: .hidSystemState)
        let q: CGKeyCode = 12
        let down = CGEvent(keyboardEventSource: src, virtualKey: q, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: q, keyDown: false)
        down?.flags = [.maskCommand, .maskControl]
        up?.flags = [.maskCommand, .maskControl]
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
