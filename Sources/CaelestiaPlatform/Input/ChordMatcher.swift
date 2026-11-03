// caelestia:allow-hardcoded-chord panic chord, spec 10.10
import CaelestiaCore
import CoreGraphics
import Foundation
import os

// MARK: - Events

/// Gesture phase of a scroll event (`CGEvent` scroll and momentum phases folded together).
public enum ScrollPhase: Equatable, Sendable {
    /// A plain wheel notch (no gesture phases).
    case none
    case mayBegin, began, changed, ended, cancelled
    case momentumBegan, momentumChanged, momentumEnded

    public var isMomentum: Bool {
        switch self {
        case .momentumBegan, .momentumChanged, .momentumEnded: return true
        default: return false
        }
    }

    /// Phases after which accumulated continuous-scroll distance is discarded.
    public var endsGesture: Bool {
        switch self {
        case .ended, .cancelled, .momentumEnded: return true
        default: return false
        }
    }
}

/// Hyprland mouse button numbers used by `SyntheticEvent` and `KeyToken.mouseButton`.
public enum MouseButtonCode {
    /// No button: plain pointer motion delivered as `.mouseDragged(button: 0, …)`.
    public static let none = 0
    public static let left = 272
    public static let right = 273
    public static let middle = 274

    /// Converts a `CGMouseButton` number (0 left, 1 right, 2 middle, 3…) to the Hyprland code.
    public static func fromCGButtonNumber(_ n: Int) -> Int { left + n }
}

/// A platform-independent rendering of a `CGEvent`, so the matcher can be driven by tests.
///
/// `flags` is the raw `CGEventFlags` value. Mouse locations are CG (top-left origin) points.
public enum SyntheticEvent: Equatable, Sendable {
    case keyDown(code: UInt16, flags: UInt64, isRepeat: Bool)
    case keyUp(code: UInt16, flags: UInt64)
    /// A modifier key changed; `code` is the key that moved (⌥L 0x3A, Caps Lock 0x39, …).
    case flagsChanged(code: UInt16, flags: UInt64)
    /// `button` uses the Hyprland numbering (`MouseButtonCode`): 272 left, 273 right, 274 middle.
    case mouseDown(button: Int, flags: UInt64, location: CGPoint)
    /// Pointer motion; `button` is 0 (`MouseButtonCode.none`) for plain moves.
    case mouseDragged(button: Int, flags: UInt64, location: CGPoint)
    case mouseUp(button: Int, flags: UInt64, location: CGPoint)
    /// `deltaY`/`deltaX` are notches for wheel events and points for continuous (trackpad) ones.
    case scroll(deltaY: Double, deltaX: Double, flags: UInt64, isContinuous: Bool, phase: ScrollPhase)
    /// An `NX_SYSDEFINED` media key (`nxKeyType` is NX_KEYTYPE_*: 0 volume up, 1 volume down,
    /// 2/3 brightness, 7 mute, 16 play, 17 next, 18 previous, 19 fast, 20 rewind).
    case systemDefined(nxKeyType: Int, isDown: Bool, flags: UInt64)
}

// MARK: - Decisions

/// What a bind produced for one event.
public struct Fired: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case press
        case release
        /// An OS auto-repeat of a `repeat` bind's key.
        case repeatTick
        case dragBegin
        /// Pointer movement since the previous drag event.
        case dragMove(delta: CGPoint)
        case dragEnd
        /// One scroll step: `+1` fired a `.scrollDown` chord (Hyprland `mouse_down`), `-1` a
        /// `.scrollUp` one. Always ±1; several steps produce several `Fired` values.
        case scrollStep(Int)
    }

    public var bind: Bind
    public var chord: KeyChord
    public var phase: Phase
    /// Pointer location for mouse and scroll events (and the last known one for drag-mode keys).
    public var location: CGPoint?

    public init(bind: Bind, chord: KeyChord, phase: Phase, location: CGPoint? = nil) {
        self.bind = bind
        self.chord = chord
        self.phase = phase
        self.location = location
    }
}

/// The matcher's verdict for an event. `fire` swallows the event; `fireAndPass` lets macOS see it
/// too (media keys, where the system changes the volume and we only add the OSD; modifier
/// changes; pointer motion in key-held drag mode).
public enum MatchDecision: Equatable, Sendable {
    case passThrough
    case swallow
    case fire([Fired])
    case fireAndPass([Fired])

    /// The binds this decision fires, if any.
    public var fired: [Fired] {
        switch self {
        case .fire(let f), .fireAndPass(let f): return f
        case .passThrough, .swallow: return []
        }
    }

    /// Whether the event must be withheld from the application.
    public var swallows: Bool {
        switch self {
        case .swallow, .fire: return true
        case .passThrough, .fireAndPass: return false
        }
    }
}

// MARK: - Matcher

/// Pure, synchronous hotkey matcher: turns `SyntheticEvent`s into `MatchDecision`s.
///
/// Matching is by virtual key code, never by character, so chords sit on the same physical keys
/// on a Norwegian layout. A chord matches when its key matches and the set of *logical* modifiers
/// held (physical keys resolved through `Keymap.modifiers`) equals the chord's modifiers exactly.
///
/// `handle(_:now:)` must do less than a millisecond of work: it is called on the event-tap thread
/// for every input event. Configuration (`update(keymap:)`, `isLocked`, `secureInputActive`) can
/// be changed from any thread; `handle` itself is serialized.
///
/// Auto-repeat is left to macOS: `repeat` binds emit `.repeatTick` for each OS repeat, so the
/// user's key repeat settings apply (the "Match Arch input" toggle sets InitialKeyRepeat 15 and
/// KeyRepeat 2, the closest macOS values to Hyprland's 250 ms / 35 Hz).
public final class ChordMatcher: @unchecked Sendable {
    // MARK: Panic chord

    /// The fixed safety-net chord ⌃⌥⌘⇧Esc (spec 10.10). It is matched on *physical* flags, so it
    /// works under any modifier map and even with an empty or broken keymap.
    public static let panicChord = KeyChord(
        modifiers: [.ctrlKey, .altKey, .superKey, .shiftKey], key: .code(Key.escape))

    /// The synthetic bind reported when the panic chord fires.
    public static let panicBind = Bind(
        id: "wm.panic", keys: [panicChord.description], action: Action(.wmPanic), flags: [],
        linux: nil, description: "Panic: stop tiling and bring every window on-screen",
        enabled: true, chords: [panicChord])

    // MARK: Well-known key codes

    /// Key codes the engine has to know about regardless of the keymap.
    enum Key {
        static let escape: UInt16 = 0x35
        static let tab: UInt16 = 0x30
        static let `return`: UInt16 = 0x24
        static let capsLock: UInt16 = 0x39
        /// Caps Lock after the preset-B hidutil remap.
        static let f18: UInt16 = PhysicalModifier.capslock.keyCodes[0]
    }

    // MARK: Index

    /// One bind resolved for one of its chords.
    private struct Entry: Sendable {
        let bind: Bind
        let chord: KeyChord
        var modifiers: Set<LogicalModifier> { chord.modifiers }
        var isRelease: Bool { bind.flags.contains(.release) }
        var isRepeat: Bool { bind.flags.contains(.repeat) }
        var isMouse: Bool { bind.flags.contains(.mouse) }
    }

    /// Binds grouped by the kind of event that can trigger them.
    private struct Index: Sendable {
        let map: ModifierMap
        var keys: [UInt16: [Entry]] = [:]
        var taps: [LogicalModifier: [Entry]] = [:]
        var mouse: [Int: [Entry]] = [:]
        var scroll: [Entry] = []
        var media: [Int: [Entry]] = [:]
        /// The map binds a logical modifier to Caps-Lock-as-F18, so key code 0x4F is a modifier.
        let usesF18: Bool

        init(keymap: Keymap) {
            map = keymap.modifiers
            usesF18 = LogicalModifier.allCases.contains { keymap.modifiers[$0] == .capslock }
            var nextEntries: [Entry] = []
            var hasStop = false
            for bind in keymap.binds where bind.enabled {
                var seen = Set<KeyChord>()
                for chord in bind.chords where seen.insert(chord).inserted {
                    let e = Entry(bind: bind, chord: chord)
                    switch chord.key {
                    case .code(let c):
                        keys[c, default: []].append(e)
                    case .modifierTap(let m):
                        taps[m, default: []].append(e)
                    case .mouseButton(let b):
                        mouse[b, default: []].append(e)
                    case .scrollUp, .scrollDown:
                        scroll.append(e)
                    case .media(let m):
                        if m.nxKeyType >= 0 { media[m.nxKeyType, default: []].append(e) }
                        if m == .previous { media[NXKeyType.rewind, default: []].append(e) }
                        if m == .next { nextEntries.append(e) }
                        if m == .stop { hasStop = true }
                    }
                }
            }
            // NX_KEYTYPE_FAST (19) is "next track" on older keyboards; Core reserves 19 for
            // `.stop`, so `.next` only takes it over when nothing is bound to Stop.
            if !hasStop, !nextEntries.isEmpty { media[NXKeyType.fast, default: []] += nextEntries }
        }
    }

    /// NX_KEYTYPE_* values the index needs beyond `MediaKey.nxKeyType`.
    private enum NXKeyType {
        static let fast = 19
        static let rewind = 20
    }

    // MARK: Transient state

    private struct HeldKey {
        var entries: [Entry]
        var armsDrag: Bool
    }

    private struct TapCandidate {
        let logical: LogicalModifier
        let key: PhysicalModifier
        let start: TimeInterval
    }

    private struct ButtonDrag {
        let button: Int
        let entries: [Entry]
        var last: CGPoint
    }

    private struct ArmedDrag {
        let code: UInt16
        let entries: [Entry]
        var last: CGPoint?
    }

    private let lock = OSAllocatedUnfairLock()

    // Configuration (any thread, under `lock`).
    private var _keymap: Keymap
    private var _input: InputConfig
    private var index: Index
    private var _isLocked = false
    private var _secureInputActive = false
    private var _treatUnknownSideAsLeft = true

    // Hot-path state (only touched by `handle`/`reset`, under `lock`).
    private var f18Held = false
    private var capsLockOn = false
    private var buttonsDown = Set<Int>()
    private var swallowedButtons = Set<Int>()
    private var pendingButtonRelease: [Int: [Entry]] = [:]
    private var lastMouseLocation: CGPoint?
    private var tapCandidate: TapCandidate?
    private var pendingRelease: [UInt16: [Entry]] = [:]
    private var heldSwallowed: [UInt16: HeldKey] = [:]
    private var buttonDrag: ButtonDrag?
    private var armedDrag: ArmedDrag?
    private var scrollAccumulator: Double = 0
    private var mediaDown = Set<Int>()
    private var loggedCmdTab = false

    // MARK: Lifecycle

    public init(keymap: Keymap, input: InputConfig = InputConfig()) {
        _keymap = keymap
        _input = input
        index = Index(keymap: keymap)
    }

    /// Hot reload: the new keymap applies to the next event. In-flight releases and drags finish
    /// with the binds they started with.
    public func update(keymap: Keymap) {
        let newIndex = Index(keymap: keymap)
        lock.lock()
        defer { lock.unlock() }
        _keymap = keymap
        index = newIndex
        if !newIndex.usesF18 { f18Held = false }
        tapCandidate = nil
    }

    /// Applies new input settings (tap window, scroll factor, ⌘Tab takeover).
    public func update(input: InputConfig) {
        lock.lock()
        defer { lock.unlock() }
        _input = input
        scrollAccumulator = 0
    }

    public var keymap: Keymap {
        lock.lock()
        defer { lock.unlock() }
        return _keymap
    }

    public var input: InputConfig {
        lock.lock()
        defer { lock.unlock() }
        return _input
    }

    /// Screen-lock state, set by the WM. While locked only `locked` binds whose action is
    /// `allowedWhileLocked` fire; everything else passes through to the lock screen.
    public var isLocked: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isLocked }
        set { lock.lock(); defer { lock.unlock() }; _isLocked = newValue }
    }

    /// Another app holds Secure Event Input (password field). Hotkeys pass through while it is on;
    /// the panic chord still works. Updated by `EventTap`.
    public var secureInputActive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _secureInputActive }
        set {
            lock.lock()
            defer { lock.unlock() }
            guard _secureInputActive != newValue else { return }
            _secureInputActive = newValue
            // Key-ups are missed while secure input is on; never leave a key or drag stuck.
            resetTransientState()
        }
    }

    /// Whether a modifier press without device-dependent side bits counts as the left key
    /// (see `ModifierState`). Default `true` so remote-desktop keyboards still drive the WM.
    public var treatUnknownSideAsLeft: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _treatUnknownSideAsLeft }
        set { lock.lock(); defer { lock.unlock() }; _treatUnknownSideAsLeft = newValue }
    }

    /// Forgets all transient state (held keys, drags, tap candidate). Call when the event stream
    /// is interrupted, e.g. after the tap was re-created.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        resetTransientState()
    }

    /// Requires `lock`.
    private func resetTransientState() {
        f18Held = false
        buttonsDown.removeAll()
        swallowedButtons.removeAll()
        pendingButtonRelease.removeAll()
        tapCandidate = nil
        pendingRelease.removeAll()
        heldSwallowed.removeAll()
        buttonDrag = nil
        armedDrag = nil
        scrollAccumulator = 0
        mediaDown.removeAll()
    }

    // MARK: Dispatch

    /// Matches one event. `now` is a monotonic timestamp in seconds (used for the Super tap window).
    public func handle(_ ev: SyntheticEvent, now: TimeInterval) -> MatchDecision {
        lock.lock()
        defer { lock.unlock() }
        if let panic = panicDecision(ev) { return panic }
        if _secureInputActive { return .passThrough }
        switch ev {
        case let .keyDown(code, flags, isRepeat):
            return keyDown(code: code, flags: flags, isRepeat: isRepeat, now: now)
        case let .keyUp(code, flags):
            return keyUp(code: code, flags: flags, now: now)
        case let .flagsChanged(code, flags):
            return flagsChanged(code: code, flags: flags, now: now)
        case let .mouseDown(button, flags, location):
            return mouseDown(button: button, flags: flags, location: location)
        case let .mouseDragged(button, flags, location):
            return mouseDragged(button: button, flags: flags, location: location)
        case let .mouseUp(button, flags, location):
            return mouseUp(button: button, flags: flags, location: location)
        case let .scroll(deltaY, _, flags, isContinuous, phase):
            return scroll(deltaY: deltaY, flags: flags, isContinuous: isContinuous, phase: phase)
        case let .systemDefined(nxKeyType, isDown, flags):
            return systemDefined(nxKeyType: nxKeyType, isDown: isDown, flags: flags)
        }
    }

    // MARK: Helpers

    private func modifierState(_ flags: UInt64) -> ModifierState {
        ModifierState(flags: flags, f18Held: f18Held, treatUnknownSideAsLeft: _treatUnknownSideAsLeft)
    }

    /// The lock-screen gate.
    private func permitted(_ e: Entry) -> Bool {
        guard _isLocked else { return true }
        return e.bind.flags.contains(.locked) && e.bind.action.kind.allowedWhileLocked
    }

    private func fired(_ e: Entry, _ phase: Fired.Phase, location: CGPoint? = nil) -> Fired {
        Fired(bind: e.bind, chord: e.chord, phase: phase, location: location)
    }

    private func entries(_ list: [Entry]?, matching logical: Set<LogicalModifier>) -> [Entry] {
        guard let list else { return [] }
        return list.filter { $0.modifiers == logical && permitted($0) }
    }

    /// ⌘Tab (optionally with ⇧) is the macOS app switcher; it stays untouched unless the user
    /// opted into "Take over ⌘Tab".
    private func isCommandTab(code: UInt16, state: ModifierState) -> Bool {
        code == Key.tab && state.command.isHeld && !state.option.isHeld && !state.control.isHeld
            && !state.fn && !state.f18
    }

    private func panicDecision(_ ev: SyntheticEvent) -> MatchDecision? {
        guard case let .keyDown(code, flags, isRepeat) = ev, !isRepeat, code == Key.escape else { return nil }
        let required = ModifierFamily.option.familyFlag | ModifierFamily.command.familyFlag
            | ModifierFamily.control.familyFlag | ModifierFamily.shift.familyFlag
        guard flags & required == required else { return nil }
        heldSwallowed[code] = HeldKey(entries: [], armsDrag: false)
        tapCandidate = nil
        return .fire([Fired(bind: Self.panicBind, chord: Self.panicChord, phase: .press)])
    }

    // MARK: Keys

    private func keyDown(code: UInt16, flags: UInt64, isRepeat: Bool, now: TimeInterval) -> MatchDecision {
        if index.usesF18, code == Key.f18 {
            guard !isRepeat else { return .swallow }
            f18Held = true
            beginTapCandidate(key: .capslock, state: modifierState(flags), now: now)
            return .swallow
        }
        if isRepeat {
            if let held = heldSwallowed[code] {
                let ticks = held.entries.filter(\.isRepeat).map { fired($0, .repeatTick) }
                return ticks.isEmpty ? .swallow : .fire(ticks)
            }
            if pendingRelease[code] != nil { return .swallow }
            return .passThrough
        }
        tapCandidate = nil
        let state = modifierState(flags)
        guard let logical = state.logicalModifiers(under: index.map) else { return .passThrough }
        let candidates = (index.keys[code] ?? []).filter { $0.modifiers == logical }
        guard !candidates.isEmpty else { return .passThrough }
        if isCommandTab(code: code, state: state), !_input.takeOverCmdTab {
            if !loggedCmdTab {
                loggedCmdTab = true
                Log.input.notice("⌘Tab is bound in the keymap but takeOverCmdTab is off; leaving it to macOS")
            }
            return .passThrough
        }
        let allowed = candidates.filter(permitted)
        guard !allowed.isEmpty else { return .passThrough }

        var fires: [Fired] = []
        var held = HeldKey(entries: [], armsDrag: false)
        var releases: [Entry] = []
        var drags: [Entry] = []
        for e in allowed {
            if e.isRelease {
                releases.append(e)
                continue
            }
            held.entries.append(e)
            if e.isMouse {
                drags.append(e)
                fires.append(fired(e, .dragBegin, location: lastMouseLocation))
            } else {
                fires.append(fired(e, .press))
            }
        }
        if !drags.isEmpty {
            armedDrag = ArmedDrag(code: code, entries: drags, last: lastMouseLocation)
            held.armsDrag = true
        }
        if !releases.isEmpty { pendingRelease[code] = releases }
        if !held.entries.isEmpty { heldSwallowed[code] = held }
        return fires.isEmpty ? .swallow : .fire(fires)
    }

    private func keyUp(code: UInt16, flags: UInt64, now: TimeInterval) -> MatchDecision {
        if index.usesF18, code == Key.f18 {
            f18Held = false
            let fires = completeTapCandidate(family: .capsLock, now: now)
            return fires.isEmpty ? .swallow : .fire(fires)
        }
        var fires: [Fired] = []
        var swallow = false
        if let releases = pendingRelease.removeValue(forKey: code) {
            swallow = true
            fires += releases.map { fired($0, .release) }
        }
        if let held = heldSwallowed.removeValue(forKey: code) {
            swallow = true
            if held.armsDrag, let armed = armedDrag, armed.code == code {
                fires += armed.entries.map { fired($0, .dragEnd, location: armed.last) }
                armedDrag = nil
            }
        }
        guard swallow else { return .passThrough }
        return fires.isEmpty ? .swallow : .fire(fires)
    }

    /// Modifier changes are never swallowed. They drive the Super tap, and a modifier key bound as
    /// a plain key (`Option_R`, `Shift_R`, … from `KeyTable`) is matched here with itself lifted
    /// from the modifier state.
    private func flagsChanged(code: UInt16, flags: UInt64, now: TimeInterval) -> MatchDecision {
        let state = modifierState(flags)
        if code == Key.capsLock {
            return capsLockChanged(state: state)
        }
        guard let key = ModifierState.physicalKey(forModifierKeyCode: code) else {
            if let c = tapCandidate, state.heldKeys != [c.key] { tapCandidate = nil }
            return .passThrough
        }
        let isDown: Bool
        if let fam = state.family(key.family), fam.unknownSide {
            isDown = true
        } else {
            isDown = state.isHeld(key)
        }
        var fires: [Fired] = []
        if isDown {
            // Resolve an unknown-side press to the key `heldKeys` reports for the family.
            let resolved = state.heldKeys.first { $0.family == key.family } ?? key
            beginTapCandidate(key: resolved, state: state, now: now)
            if let logical = state.removing(key).logicalModifiers(under: index.map) {
                let matched = entries(index.keys[code], matching: logical)
                let releases = matched.filter(\.isRelease)
                if !releases.isEmpty { pendingRelease[code] = releases }
                fires += matched.filter { !$0.isRelease }.map { fired($0, .press) }
            }
        } else {
            fires += completeTapCandidate(family: key.family, now: now)
            if let releases = pendingRelease.removeValue(forKey: code) {
                fires += releases.map { fired($0, .release) }
            }
        }
        return fires.isEmpty ? .passThrough : .fireAndPass(fires)
    }

    /// Caps Lock never produces key events, only `flagsChanged` with the latch toggled; a
    /// `.code(0x39)` bind fires once per toggle (Hyprland's `Caps_Lock` lock-key OSD).
    private func capsLockChanged(state: ModifierState) -> MatchDecision {
        tapCandidate = nil
        guard state.capsLockOn != capsLockOn else { return .passThrough }
        capsLockOn = state.capsLockOn
        guard let logical = state.logicalModifiers(under: index.map) else { return .passThrough }
        let fires = entries(index.keys[Key.capsLock], matching: logical).map {
            fired($0, $0.isRelease ? .release : .press)
        }
        return fires.isEmpty ? .passThrough : .fireAndPass(fires)
    }

    // MARK: Modifier tap

    /// A tap candidate starts when the mapped physical key goes down alone: nothing else held,
    /// no mouse button down, no drag in progress.
    private func beginTapCandidate(key: PhysicalModifier, state: ModifierState, now: TimeInterval) {
        tapCandidate = nil
        guard buttonsDown.isEmpty, buttonDrag == nil, armedDrag == nil else { return }
        guard state.heldKeys == [key] else { return }
        for logical in LogicalModifier.allCases {
            guard index.map[logical].covers(key), let taps = index.taps[logical],
                taps.contains(where: permitted)
            else { continue }
            tapCandidate = TapCandidate(logical: logical, key: key, start: now)
            return
        }
    }

    /// The candidate key came back up: fire the tap binds if it happened within `superTapMs`.
    /// Matching is by family because a candidate can only exist while that one key is held.
    private func completeTapCandidate(family: ModifierFamily, now: TimeInterval) -> [Fired] {
        guard let c = tapCandidate, c.key.family == family else { return [] }
        tapCandidate = nil
        let elapsed = now - c.start
        guard elapsed >= 0, elapsed <= Double(_input.superTapMs) / 1000 else { return [] }
        return (index.taps[c.logical] ?? []).filter(permitted).map { fired($0, .release) }
    }

    // MARK: Mouse

    private func mouseDown(button: Int, flags: UInt64, location: CGPoint) -> MatchDecision {
        tapCandidate = nil
        buttonsDown.insert(button)
        lastMouseLocation = location
        guard buttonDrag == nil else { return .passThrough }
        let state = modifierState(flags)
        guard let logical = state.logicalModifiers(under: index.map) else { return .passThrough }
        let matched = entries(index.mouse[button], matching: logical)
        guard !matched.isEmpty else { return .passThrough }

        var fires: [Fired] = []
        var drags: [Entry] = []
        var releases: [Entry] = []
        for e in matched {
            if e.isMouse {
                drags.append(e)
                fires.append(fired(e, .dragBegin, location: location))
            } else if e.isRelease {
                releases.append(e)
            } else {
                fires.append(fired(e, .press, location: location))
            }
        }
        if !drags.isEmpty { buttonDrag = ButtonDrag(button: button, entries: drags, last: location) }
        if !releases.isEmpty { pendingButtonRelease[button] = releases }
        swallowedButtons.insert(button)
        return fires.isEmpty ? .swallow : .fire(fires)
    }

    private func mouseDragged(button: Int, flags: UInt64, location: CGPoint) -> MatchDecision {
        lastMouseLocation = location
        if var drag = buttonDrag, drag.button == button {
            let delta = CGPoint(x: location.x - drag.last.x, y: location.y - drag.last.y)
            drag.last = location
            buttonDrag = drag
            return .fire(drag.entries.map { fired($0, .dragMove(delta: delta), location: location) })
        }
        if button == MouseButtonCode.none, var armed = armedDrag {
            let delta = armed.last.map { CGPoint(x: location.x - $0.x, y: location.y - $0.y) } ?? .zero
            armed.last = location
            armedDrag = armed
            return .fireAndPass(armed.entries.map { fired($0, .dragMove(delta: delta), location: location) })
        }
        if swallowedButtons.contains(button) { return .swallow }
        return .passThrough
    }

    private func mouseUp(button: Int, flags: UInt64, location: CGPoint) -> MatchDecision {
        buttonsDown.remove(button)
        lastMouseLocation = location
        var fires: [Fired] = []
        if let drag = buttonDrag, drag.button == button {
            buttonDrag = nil
            fires += drag.entries.map { fired($0, .dragEnd, location: location) }
        }
        if let releases = pendingButtonRelease.removeValue(forKey: button) {
            fires += releases.map { fired($0, .release, location: location) }
        }
        guard swallowedButtons.remove(button) != nil else { return .passThrough }
        return fires.isEmpty ? .swallow : .fire(fires)
    }

    // MARK: Scroll

    /// `deltaY` is the CGEvent value (positive = "up" as macOS reports it, with the system's
    /// natural-scrolling preference already applied). It is negated when `naturalScroll` is on, so
    /// a two-finger swipe up becomes a positive `.scrollDown` step, the same way Hyprland's
    /// `natural_scroll` makes swiping up fire `mouse_down`. Wheel notches are one step each;
    /// continuous distance × `scrollFactor` is accumulated and one step is emitted per
    /// `scrollStepPoints`. Momentum events are swallowed but never step.
    private func scroll(deltaY: Double, flags: UInt64, isContinuous: Bool, phase: ScrollPhase) -> MatchDecision {
        tapCandidate = nil
        let state = modifierState(flags)
        guard let logical = state.logicalModifiers(under: index.map) else {
            scrollAccumulator = 0
            return .passThrough
        }
        let matched = entries(index.scroll, matching: logical)
        guard !matched.isEmpty else {
            scrollAccumulator = 0
            return .passThrough
        }
        if phase.endsGesture {
            scrollAccumulator = 0
            return .swallow
        }
        if phase.isMomentum { return .swallow }

        let signed = deltaY * (_input.naturalScroll ? -1 : 1)
        var steps = 0
        if isContinuous {
            scrollAccumulator += signed * _input.scrollFactor
            let stepPoints = max(_input.scrollStepPoints, 1)
            while abs(scrollAccumulator) >= stepPoints {
                let s = scrollAccumulator > 0 ? 1 : -1
                steps += s
                scrollAccumulator -= Double(s) * stepPoints
            }
        } else if signed != 0 {
            steps = signed > 0 ? 1 : -1
        }
        guard steps != 0 else { return .swallow }

        let token: KeyToken = steps > 0 ? .scrollDown : .scrollUp
        let direction = steps > 0 ? 1 : -1
        let targets = matched.filter { $0.chord.key == token }
        guard !targets.isEmpty else { return .swallow }
        var fires: [Fired] = []
        for _ in 0..<abs(steps) {
            fires += targets.map { fired($0, .scrollStep(direction), location: lastMouseLocation) }
        }
        return .fire(fires)
    }

    // MARK: Media keys

    /// Media keys always pass through so macOS performs the actual change; we only add the OSD.
    /// A down following a down without an up is an OS auto-repeat.
    private func systemDefined(nxKeyType: Int, isDown: Bool, flags: UInt64) -> MatchDecision {
        let state = modifierState(flags)
        guard let logical = state.logicalModifiers(under: index.map) else {
            if !isDown { mediaDown.remove(nxKeyType) }
            return .passThrough
        }
        let matched = entries(index.media[nxKeyType], matching: logical)
        guard isDown else {
            mediaDown.remove(nxKeyType)
            let fires = matched.filter(\.isRelease).map { fired($0, .release) }
            return fires.isEmpty ? .passThrough : .fireAndPass(fires)
        }
        tapCandidate = nil
        let isRepeat = !mediaDown.insert(nxKeyType).inserted
        var fires: [Fired] = []
        for e in matched {
            if isRepeat {
                if e.isRepeat { fires.append(fired(e, .repeatTick)) }
            } else if !e.isRelease {
                fires.append(fired(e, .press))
            }
        }
        return fires.isEmpty ? .passThrough : .fireAndPass(fires)
    }
}
