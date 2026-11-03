import CaelestiaCore
import CaelestiaLayout
import CaelestiaPlatform
import CoreGraphics
import Foundation
@testable import CaelestiaWMKit

/// A window that behaves like an AX window: writes are applied (clamped to `minSize`) and each
/// write queues an echo notification on its system, delivered later by `flush()` like real AX
/// notifications are.
@MainActor
final class FakeWindow: WindowHandle {
    let windowID: WindowID
    let pid: pid_t
    let bundleID: String
    var title: String
    var frame: CGRect
    var role = "AXWindow"
    var subrole = "AXStandardWindow"
    var isResizable = true
    var isMinimized = false
    /// The app refuses to get smaller than this.
    var minSize = CGSize.zero
    /// The app ignores every write and keeps its frame (stubborn app).
    var ignoresWrites = false
    var setFrameCount = 0
    var setPositionCount = 0
    var focusCount = 0
    var raiseCount = 0
    weak var system: FakeWindowSystem?

    init(id: WindowID, pid: pid_t, bundleID: String, title: String, frame: CGRect) {
        windowID = id
        self.pid = pid
        self.bundleID = bundleID
        self.title = title
        self.frame = frame
    }

    func setFrame(_ target: CGRect) -> CGRect {
        setFrameCount += 1
        if ignoresWrites { return frame }
        frame = CGRect(
            x: target.minX, y: target.minY, width: max(target.width, minSize.width), height: max(target.height, minSize.height)
        )
        system?.queue(.frameChanged(windowID, frame: frame, isEcho: true))
        return frame
    }

    func setPosition(_ origin: CGPoint) -> CGPoint {
        setPositionCount += 1
        if ignoresWrites { return frame.origin }
        frame.origin = origin
        system?.queue(.frameChanged(windowID, frame: frame, isEcho: true))
        return origin
    }

    func focus() -> Bool {
        focusCount += 1
        system?.focusedWindowID = windowID
        system?.queue(.focused(windowID))
        return true
    }

    func raise() -> Bool {
        raiseCount += 1
        return true
    }

    func close() -> Bool {
        system?.destroy(windowID)
        return true
    }

    func descriptor() -> WindowDescriptor {
        WindowDescriptor(
            bundleID: bundleID, appName: bundleID, title: title, role: role, subrole: subrole, pid: pid,
            windowID: windowID, isResizable: isResizable, isMinimized: isMinimized
        )
    }

    /// The app moves its own window (not an echo).
    func appMoves(to rect: CGRect) {
        frame = rect
        system?.queue(.frameChanged(windowID, frame: rect, isEcho: false))
    }
}

/// The "operating system": every window that exists, announced to the WM on `start()` and when
/// opened afterwards. Window objects survive a WM restart (pass the same system to the next WM).
@MainActor
final class FakeWindowSystem: WindowSystem {
    var onEvent: ((WindowSystemEvent) -> Void)?
    var windows: [WindowID: FakeWindow] = [:]
    var focusedWindowID: WindowID?
    var cursorLocation: CGPoint?
    var underCursor: WindowID?
    var started = false
    private var pending: [WindowSystemEvent] = []
    private var nextID: WindowID = 100

    var allWindows: [any WindowHandle] { windows.keys.sorted().map { windows[$0]! } }

    func start() {
        started = true
        for id in windows.keys.sorted() { onEvent?(.created(windows[id]!)) }
    }

    func stop() { started = false }

    func windowUnderCursor() -> WindowID? { underCursor }

    func findWindow(for record: ParkedWindowRecord) -> (any WindowHandle)? {
        windows[record.windowID] ?? windows.values.first { $0.bundleID == record.bundleID && $0.title == record.title }
    }

    /// A window that already exists before the WM starts.
    @discardableResult
    func existing(_ title: String, bundle: String = "com.example.app", pid: pid_t = 500, frame: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400)) -> FakeWindow {
        let w = FakeWindow(id: allocateID(), pid: pid, bundleID: bundle, title: title, frame: frame)
        w.system = self
        windows[w.windowID] = w
        return w
    }

    /// Opens a window while the WM runs (announced immediately, focused by the app like macOS does).
    @discardableResult
    func open(_ title: String, bundle: String = "com.example.app", pid: pid_t = 500, frame: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400),
              configure: (FakeWindow) -> Void = { _ in }) -> FakeWindow {
        let w = existing(title, bundle: bundle, pid: pid, frame: frame)
        configure(w)
        if started { onEvent?(.created(w)) }
        return w
    }

    func destroy(_ id: WindowID) {
        guard windows.removeValue(forKey: id) != nil else { return }
        if focusedWindowID == id { focusedWindowID = nil }
        queue(.destroyed(id))
    }

    /// SIGKILL of an app: its windows vanish at once.
    func kill(pid: pid_t) {
        for (id, w) in windows where w.pid == pid { destroy(id) }
        queue(.appTerminated(pid))
    }

    func queue(_ event: WindowSystemEvent) { pending.append(event) }

    var hasPending: Bool { !pending.isEmpty }

    /// Delivers queued notifications (echoes, focus, destroys) in order.
    func flush() {
        while !pending.isEmpty {
            let e = pending.removeFirst()
            if started { onEvent?(e) }
        }
    }

    private func allocateID() -> WindowID {
        nextID += 1
        return nextID
    }
}

@MainActor
final class FakeDisplays: DisplayProvider {
    var displays: [DisplayInfo]
    var onChange: (([DisplayInfo]) -> Void)?

    init(_ displays: [DisplayInfo]) { self.displays = displays }

    func start() {}
    func stop() {}

    func change(to list: [DisplayInfo]) {
        displays = list
        onChange?(list)
    }
}

enum TestDisplays {
    /// MacBook Air 13" (M4): 1470×956, notch/menu bar 33 pt.
    static let air = DisplayInfo(id: "air", name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1470, height: 956), menuBarHeight: 33, isPrimary: true)
    /// 2560×1440 external to the right of the Air.
    static let external = DisplayInfo(id: "ext", name: "External", frame: CGRect(x: 1470, y: 0, width: 2560, height: 1440))
    /// Gabby's ultrawide, menu bar hidden (golden numbers from clients.json).
    static let ultrawide = DisplayInfo(id: "uw", name: "DP-2", frame: CGRect(x: 0, y: 0, width: 5120, height: 1440), isPrimary: true)
}

/// A clock tests can advance.
final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
}

/// One WM over fakes, with manual layout scheduling and a private journal file.
@MainActor
final class Harness {
    let system: FakeWindowSystem
    let screens: FakeDisplays
    let journalURL: URL
    var wm: WindowManager
    let clock = TestClock()
    var quitCount = 0
    let matcher: ChordMatcher
    private var eventTime: TimeInterval = 0

    init(displays: [DisplayInfo] = [TestDisplays.air], config: Config = Config(), system: FakeWindowSystem = FakeWindowSystem(),
         journalURL: URL? = nil) {
        self.system = system
        screens = FakeDisplays(displays)
        self.journalURL = journalURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("wm-journal-\(UUID().uuidString).json")
        let keymap = KeymapLoader.loadDefault()
        matcher = ChordMatcher(keymap: keymap, input: config.input)
        wm = WindowManager(windowSystem: system, displayProvider: screens, journal: ParkingJournal(url: self.journalURL),
                           config: config, keymap: keymap, scheduling: .manual, now: { [clock] in clock.now })
        wm.onQuit = { [unowned self] in self.quitCount += 1 }
    }

    /// Starts the WM and settles.
    @discardableResult
    func start() -> Int {
        wm.start()
        return settle()
    }

    /// Delivers pending notifications and runs layout passes until nothing changes. Returns the
    /// number of layout passes it took.
    @discardableResult
    func settle(maxIterations: Int = 20) -> Int {
        let before = wm.counters.layoutPasses
        for _ in 0..<maxIterations {
            system.flush()
            wm.layoutIfNeeded()
            if !system.hasPending && !wm.needsLayout { break }
        }
        return wm.counters.layoutPasses - before
    }

    var journal: ParkingJournal { ParkingJournal(url: journalURL) }

    // MARK: Hotkeys through the real matcher

    static let lopt: UInt64 = 0x80000 | 0x20
    static let lcmd: UInt64 = 0x100000 | 0x08
    static let ctrl: UInt64 = 0x40000 | 0x01
    static let shift: UInt64 = 0x20000 | 0x02

    /// Presses `key` with `flags` (e.g. `Harness.lopt | Harness.shift`) through the ChordMatcher and
    /// hands what fired to the WM. Returns the fired bind ids.
    @discardableResult
    func press(_ key: String, _ flags: UInt64) -> [String] {
        guard let code = KeyTable.code(for: key) else { fatalError("no key code for \(key)") }
        eventTime += 1
        var fired: [Fired] = []
        fired += matcher.handle(.flagsChanged(code: 0x3A, flags: flags), now: eventTime).fired
        fired += matcher.handle(.keyDown(code: code, flags: flags, isRepeat: false), now: eventTime + 0.01).fired
        fired += matcher.handle(.keyUp(code: code, flags: flags), now: eventTime + 0.02).fired
        fired += matcher.handle(.flagsChanged(code: 0x3A, flags: 0), now: eventTime + 0.5).fired
        wm.handle(fired: fired)
        settle()
        return fired.map(\.bind.id)
    }

    // MARK: Assertions helpers

    func frame(_ w: FakeWindow) -> CGRect { system.windows[w.windowID]?.frame ?? .null }

    func isOnScreen(_ w: FakeWindow) -> Bool {
        !ParkingPlanner.isOffScreen(w.frame, displays: screens.displays.map(\.frame))
    }
}
