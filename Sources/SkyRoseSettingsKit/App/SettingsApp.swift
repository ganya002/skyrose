import AppKit
import CaelestiaCore
import CaelestiaPlatform
import CaelestiaShell
import SwiftUI

/// Command-line options of SkyRose Settings.
public struct SettingsLaunchOptions: Equatable, Sendable {
    public var onboarding: OnboardingRequest?
    public var page: SettingsPage = .general
    /// Reported as missing without touching the real grants.
    public var simulateMissing: Set<SkyRosePermission> = []
    /// Shows the SIP reminder on launch (uninstaller preview).
    public var demoSIPPopup = false
    /// `--sip-reminder`: the uninstaller found that SIP-off mode was used. Shown only if
    /// ``RestoreManifest/mustShowSIPReminder(csrutilStatus:)`` agrees or the manifest is already
    /// gone (the uninstaller decided before removing it).
    public var sipReminder = false
    /// `--sip-off-showcase`: opens "What changes with SIP off?" (with `--page sipOff`).
    public var sipOffShowcase = false
    /// Opens the onboarding at this step (screenshots, tests).
    public var onboardingStep: OnboardingStep?
    /// `--uninstaller [--dry-run]`: opens the uninstaller window (Settings › Backup & uninstall
    /// does the same after a confirm). `--dry-run` previews it: the engine runs with --dry-run.
    public var uninstaller = false
    public var installer = false
    public var payload: String?
    public var dryRun = false

    /// `--sip-reminder` on its own: the uninstaller is blocked in `open -W` until this instance
    /// quits, and it quits when the reminder is dismissed.
    public var sipReminderOnly: Bool { sipReminder && !uninstaller && !installer && onboarding == nil }

    public init() {}

    /// `--onboarding [--repair] [--only a,b]`, `--page <name>`, `--simulate-missing a,b`,
    /// `--demo-sip-popup`. `SKYROSE_SIMULATE_MISSING` works too. Unknown arguments are ignored
    /// (macOS adds its own, like -NSDocumentRevisionsDebugMode).
    public static func parse(_ args: [String], environment: [String: String] = [:]) -> SettingsLaunchOptions {
        var o = SettingsLaunchOptions()
        o.onboarding = OnboardingRequest.parse(args)
        if let i = args.firstIndex(of: "--page"), i + 1 < args.count, let p = SettingsPage(rawValue: args[i + 1]) { o.page = p }
        var missing = PermissionSnapshot.parseSimulated(environment["SKYROSE_SIMULATE_MISSING"])
        if let i = args.firstIndex(of: "--simulate-missing"), i + 1 < args.count {
            missing.formUnion(PermissionSnapshot.parseSimulated(args[i + 1]))
        }
        o.simulateMissing = missing
        o.demoSIPPopup = args.contains("--demo-sip-popup")
        o.sipReminder = args.contains("--sip-reminder")
        o.sipOffShowcase = args.contains("--sip-off-showcase")
        if let i = args.firstIndex(of: "--step"), i + 1 < args.count { o.onboardingStep = OnboardingStep(rawValue: args[i + 1]) }
        o.uninstaller = args.contains("--uninstaller")
        o.installer = args.contains("--installer")
        if let i = args.firstIndex(of: "--payload"), i + 1 < args.count { o.payload = args[i + 1] }
        o.dryRun = args.contains("--dry-run")
        return o
    }
}

/// A borderless window that can take the keyboard (text fields, shortcut recording).
final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
public final class SettingsAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store: SettingsStore
    var options: SettingsLaunchOptions
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var uninstallerWindow: NSWindow?
    private var installerWindow: NSWindow?

    public init(options: SettingsLaunchOptions) {
        self.options = options
        store = SettingsStore(simulatedMissing: options.simulateMissing)
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.menu()
        if !FontStore.shared.registerForProcess().isEmpty { ShellTheme.fontsChanged() }
        store.start()
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.skyrose.mac.settings.show"), object: nil, queue: .main
        ) { [weak self] n in
            let args = n.userInfo?["arguments"] as? [String] ?? []
            MainActor.assumeIsolated { self?.handle(arguments: args) }
        }
        if options.sipReminderOnly {
            SIPReminderPresenter.show(look: store.look) { NSApp.terminate(nil) }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if options.installer {
            showInstaller(dryRun: options.dryRun, payload: options.payload)
        } else if options.uninstaller {
            showUninstaller(dryRun: options.dryRun)
        } else if let req = options.onboarding {
            showOnboarding(req)
        } else {
            showSettings(page: options.page)
        }
        if options.sipOffShowcase { SIPOffShowcase.present(look: store.look) }
        if options.demoSIPPopup || (options.sipReminder && Self.uninstallerReminderStillNeeded()) {
            SIPReminderPresenter.show(look: store.look)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The uninstaller's decision stands when the manifest is gone; otherwise it is re-checked.
    static func uninstallerReminderStillNeeded() -> Bool {
        let m = RestoreManifest()
        let recordsLeft = FileManager.default.fileExists(atPath: m.journal.url.path) || FileManager.default.fileExists(atPath: m.flagURL(.sipOff).path)
        return !recordsLeft || m.mustShowSIPReminder(csrutilStatus: SIPStatus.readCSRUtil())
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettings(page: options.page) }
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    /// Another launch (the WM or `skyrose settings`) asked for a window.
    func handle(arguments: [String]) {
        let o = SettingsLaunchOptions.parse(arguments)
        if o.installer { showInstaller(dryRun: o.dryRun, payload: o.payload) }
        else if o.uninstaller { showUninstaller(dryRun: o.dryRun) }
        else if let req = o.onboarding { showOnboarding(req) } else { showSettings(page: o.page) }
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings(page: SettingsPage) {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let root = SettingsRoot(store: store, page: page,
                                onClose: { [weak self] in self?.settingsWindow?.close() },
                                onRunOnboarding: { [weak self] in self?.showOnboarding(.firstRun) },
                                onUninstall: { [weak self] dry in self?.showUninstaller(dryRun: dry) })
        let w = makeWindow(NSHostingView(rootView: root), size: NSSize(width: 980, height: 700), title: "SkyRose Settings")
        w.minSize = NSSize(width: 860, height: 600)
        settingsWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    func showOnboarding(_ request: OnboardingRequest) {
        onboardingWindow?.close()
        let view = OnboardingView(store: store, request: request, startAt: options.onboardingStep) { [weak self] in
            guard let self else { return }
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            if request == .firstRun, self.settingsWindow == nil, self.options.onboarding != nil {
                NSApp.terminate(nil)
            }
        }
        // A normal window: it never floats over Settings (or anything else) and can go behind.
        let w = makeWindow(NSHostingView(rootView: view), size: NSSize(width: 780, height: 640), title: "Welcome to SkyRose")
        if let s = settingsWindow { w.setFrameTopLeftPoint(NSPoint(x: s.frame.minX + 40, y: s.frame.maxY - 40)) }
        onboardingWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    /// The uninstaller window. Closing it while the engine runs is not offered (no close button);
    /// when it was the only window, closing it quits.
    func showUninstaller(dryRun: Bool) {
        if let w = uninstallerWindow { w.makeKeyAndOrderFront(nil); return }
        let view = UninstallerView(store: store, dryRun: dryRun) { [weak self] in
            guard let self else { return }
            self.uninstallerWindow?.close()
            if self.settingsWindow == nil, self.onboardingWindow == nil { NSApp.terminate(nil) }
        }
        let w = makeWindow(NSHostingView(rootView: view), size: SetupChrome<EmptyView, EmptyView>.size, title: dryRun ? "Preview the SkyRose uninstall" : "Uninstall SkyRose")
        w.styleMask.remove(.resizable)
        if let s = settingsWindow { w.setFrameTopLeftPoint(NSPoint(x: s.frame.minX + 60, y: s.frame.maxY - 50)) }
        uninstallerWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    /// The installer window. `payload` is a folder of apps the script already checked.
    func showInstaller(dryRun: Bool, payload: String?) {
        if let w = installerWindow { w.makeKeyAndOrderFront(nil); return }
        let view = InstallerView(store: store, dryRun: dryRun, payload: payload) { [weak self] in
            guard let self else { return }
            self.installerWindow?.close()
            if self.settingsWindow == nil, self.onboardingWindow == nil { NSApp.terminate(nil) }
        }
        let w = makeWindow(NSHostingView(rootView: view), size: SetupChrome<EmptyView, EmptyView>.size, title: dryRun ? "Preview the SkyRose install" : "Install SkyRose")
        w.styleMask.remove(.resizable)
        installerWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(_ content: NSView, size: NSSize, title: String) -> NSWindow {
        let w = SettingsWindow(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .resizable, .miniaturizable, .fullSizeContentView],
                               backing: .buffered, defer: false)
        w.title = title
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        // Clip everything (blur included) to the window's rounded shape so nothing square shows
        // at the corners, and let the shadow follow that shape.
        content.wantsLayer = true
        content.layer?.cornerRadius = SettingsLook.windowRadius
        content.layer?.cornerCurve = .circular
        content.layer?.masksToBounds = true
        w.contentView = content
        w.center()
        DispatchQueue.main.async { w.invalidateShadow() }
        return w
    }

    public func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if w === settingsWindow { store.flush(); settingsWindow = nil }
        if w === onboardingWindow { onboardingWindow = nil }
        if w === uninstallerWindow { uninstallerWindow = nil }
        if w === installerWindow { installerWindow = nil }
    }

    static func menu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: "About SkyRose Settings", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide SkyRose Settings", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit SkyRose Settings", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        let winItem = NSMenuItem()
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "Minimise", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win
        main.addItem(winItem)
        return main
    }
}

/// Entry point for the SkyRoseSettings executable.
@MainActor
public enum SettingsApp {
    public static func run() -> Never {
        let app = NSApplication.shared
        let options = SettingsLaunchOptions.parse(Array(CommandLine.arguments.dropFirst()), environment: ProcessInfo.processInfo.environment)
        let delegate = SettingsAppDelegate(options: options)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
        exit(0)
    }
}
