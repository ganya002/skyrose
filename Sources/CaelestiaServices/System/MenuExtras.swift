import AppKit
import ApplicationServices
import Foundation

/// Other apps' menu bar items (Discord, Spotify, Dropbox…), read through Accessibility
/// (`AXExtrasMenuBar`) so SkyRose can list and press them when the menu bar is hidden.
public struct MenuExtra: Hashable, Sendable, Identifiable {
    public var id: String { "\(pid):\(index)" }
    public var pid: pid_t
    public var index: Int
    public var appName: String
    public var bundleID: String
    public var title: String
}

public enum MenuExtras {
    /// Apple's own items (clock, Control Center, Wi-Fi…) live in these processes (all of them in
    /// MenuBarAgent on macOS 26+); SkyRose has its own controls for them.
    static let system: Set<String> = ["com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.Spotlight",
                                      "com.apple.TextInputMenuAgent", "com.apple.notificationcenterui", "com.apple.MenuBarAgent"]

    /// Reads every app's extras (blocking AX calls with a short timeout: call off the main thread).
    public static func list() -> [MenuExtra] {
        guard AXIsProcessTrusted() else { return [] }
        var out: [MenuExtra] = []
        let own = Bundle.main.bundleIdentifier ?? ""
        for app in NSWorkspace.shared.runningApplications {
            guard let bundle = app.bundleIdentifier, bundle != own, !system.contains(bundle), !app.isTerminated else { continue }
            for (i, item) in items(pid: app.processIdentifier).enumerated() {
                out.append(MenuExtra(pid: app.processIdentifier, index: i, appName: app.localizedName ?? bundle,
                                     bundleID: bundle, title: title(item) ?? app.localizedName ?? bundle))
            }
        }
        return out.sorted { $0.appName.lowercased() < $1.appName.lowercased() }
    }

    /// Clicks the item: the app opens its menu (or window) as if clicked in the menu bar.
    @discardableResult
    public static func press(_ extra: MenuExtra) -> Bool {
        let list = items(pid: extra.pid)
        // The app may have added or moved items since the list was read: match the title, and
        // prefer the old position when several share it.
        let same = list.indices.filter { (title(list[$0]) ?? extra.appName) == extra.title }
        guard let i = same.contains(extra.index) ? extra.index : same.first else { return false }
        return AXUIElementPerformAction(list[i], kAXPressAction as CFString) == .success
    }

    private static func items(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar,
              CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        return menuItems(in: bar as! AXUIElement, depth: 0)
    }

    /// The menu bar items under `e`; newer macOS wraps each one in a group.
    private static func menuItems(in e: AXUIElement, depth: Int) -> [AXUIElement] {
        var children: CFTypeRef?
        guard depth < 3, AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &children) == .success else { return [] }
        return ((children as? [AXUIElement]) ?? []).flatMap { c -> [AXUIElement] in
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(c, kAXRoleAttribute as CFString, &role)
            return (role as? String) == (kAXMenuBarItemRole as String) ? [c] : menuItems(in: c, depth: depth + 1)
        }
    }

    private static func title(_ e: AXUIElement) -> String? {
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute] {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(e, key as CFString, &v) == .success, let s = v as? String, !s.isEmpty { return s }
        }
        return nil
    }
}
