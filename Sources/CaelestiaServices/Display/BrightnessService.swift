import AppKit
import Foundation
import IOKit
import IOKit.graphics
import CaelestiaCore

/// Display brightness for the OSD and the brightness binds.
public struct BrightnessState: Hashable, Sendable {
    /// 0...1.
    public var value: Double = 1
    /// `true` when read from IOKit; `false` when it is the shadow value tracked from key presses.
    public var exact: Bool = false
    /// Explains why the value is only tracked (e.g. built-in Apple Silicon panel).
    public var unavailableReason: String? = nil
    public init() {}
}

/// The private DisplayServices brightness calls (what MonitorControl and the system's own key
/// handler use for Apple panels), loaded with dlopen so a missing framework only disables them.
/// Listed in DESIGN.md D12. Only displays for which `DisplayServicesCanChangeBrightness` is true
/// are touched (built-in panels, Apple displays); everything else falls back.
public enum DisplayServicesBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias ChangedFn = @convention(c) (CGDirectDisplayID, Double) -> Void

    private struct Symbols: @unchecked Sendable {
        let get: GetFn
        let set: SetFn
        let can: CanFn
        let changed: ChangedFn?
    }

    private static let symbols: Symbols? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let g = dlsym(h, "DisplayServicesGetBrightness"), let s = dlsym(h, "DisplayServicesSetBrightness"),
              let c = dlsym(h, "DisplayServicesCanChangeBrightness") else { return nil }
        return Symbols(
            get: unsafeBitCast(g, to: GetFn.self), set: unsafeBitCast(s, to: SetFn.self), can: unsafeBitCast(c, to: CanFn.self),
            changed: dlsym(h, "DisplayServicesBrightnessChanged").map { unsafeBitCast($0, to: ChangedFn.self) })
    }()

    public static var isAvailable: Bool { symbols != nil }

    public static func canChange(_ display: CGDirectDisplayID) -> Bool {
        guard let s = symbols else { return false }
        var v: Float = 0
        return s.can(display) && s.get(display, &v) == 0
    }

    public static func get(_ display: CGDirectDisplayID) -> Double? {
        guard let s = symbols else { return nil }
        var v: Float = 0
        return s.get(display, &v) == 0 ? Double(v) : nil
    }

    @discardableResult
    public static func set(_ display: CGDirectDisplayID, _ value: Double) -> Bool {
        guard let s = symbols else { return false }
        let ok = s.set(display, Float(min(1, max(0, value)))) == 0
        if ok { s.changed?(display, value) }
        return ok
    }

    /// Online displays whose brightness DisplayServices can change.
    public static func controllableDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &n) == .success else { return [] }
        return ids.prefix(Int(n)).filter { canChange($0) }
    }
}

/// Brightness for the OSD, the brightness keys and the sliders.
///
/// - Built-in panels and Apple displays: DisplayServices (`DisplayServicesBrightness`), exact
///   value, set directly. The brightness keys are then intercepted (see `MediaKeyInterceptor`),
///   so only Caelestia's OSD shows.
/// - Displays that publish an `IODisplayConnect` service (external displays over DDC-capable
///   connections on Intel Macs, some older panels) are read and set through
///   `IODisplayGetFloatParameter` / `IODisplaySetFloatParameter(kIODisplayBrightnessKey)`.
/// - Otherwise brightness is unavailable: the keys go to macOS (Apple's HUD only) and the
///   OSD / sidebar hide the brightness slider. `set(_:)` then posts brightness key events.
@MainActor
public final class BrightnessService {
    /// Brightness change per F1/F2 press (macOS uses 16 steps; ⌥⇧ gives quarter steps).
    public static let keyStep: Double = 1.0 / 16.0

    public private(set) var state = BrightnessState()
    public var onChange: ((BrightnessState) -> Void)?
    /// How brightness keys are posted when no API exists; the WM may route this through its tap.
    public var postBrightnessKey: (MediaKeyKind) -> Void = { MediaKeyPoster.post($0) }
    /// The display the keys act on (the one under the pointer when it is controllable). Nil: the
    /// built-in panel, else the first controllable display.
    public var preferredDisplay: () -> CGDirectDisplayID? = { nil }

    private var service: io_service_t = 0
    private var shadow: Double = 1
    private var observer: NSObjectProtocol?
    private var running = false
    private var controllable: [CGDirectDisplayID] = []

    public init() {}

    /// DisplayServices or IOKit can set the brightness of at least one display.
    public var isControllable: Bool { !controllable.isEmpty || service != 0 }

    public func start() {
        guard !running else { return }
        running = true
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            onMain {
                self.locateService()
                self.refresh()
            }
        }
        locateService()
        refresh()
    }

    public func stop() {
        guard running else { return }
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        releaseService()
    }

    /// The display the brightness keys and sliders act on.
    public var targetDisplay: CGDirectDisplayID? {
        if let p = preferredDisplay(), controllable.contains(p) { return p }
        if let builtIn = controllable.first(where: { CGDisplayIsBuiltin($0) != 0 }) { return builtIn }
        return controllable.first
    }

    /// The WM calls this for every brightness key macOS handled (down events only) so the tracked
    /// value follows what macOS did (no exact control).
    public func noteBrightnessKey(up: Bool) {
        guard !isControllable else { return refresh() }
        shadow = clamp(shadow + (up ? Self.keyStep : -Self.keyStep), 0...1)
        refresh()
    }

    /// Sets brightness to `value` (0...1).
    public func set(_ value: Double) {
        let target = clamp(value, 0...1)
        if let d = targetDisplay {
            if !DisplayServicesBrightness.set(d, target) { Log.services.error("DisplayServicesSetBrightness failed for \(d)") }
            refresh()
            return
        }
        if service != 0 {
            let result = IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, Float(target))
            if result != kIOReturnSuccess {
                Log.services.error("IODisplaySetFloatParameter failed: \(result)")
            }
            refresh()
            return
        }
        let steps = Int((abs(target - shadow) / Self.keyStep).rounded())
        guard steps > 0 else { return }
        let key: MediaKeyKind = target > shadow ? .brightnessUp : .brightnessDown
        for _ in 0..<steps { postBrightnessKey(key) }
        shadow = target
        refresh()
    }

    /// One key step (1/16, or 1/64 with `fine`), snapped to the step grid like macOS.
    public func step(up: Bool, fine: Bool = false) {
        guard isControllable else {
            postBrightnessKey(up ? .brightnessUp : .brightnessDown)
            noteBrightnessKey(up: up)
            return
        }
        let step = fine ? Self.keyStep / 4 : Self.keyStep
        set(Self.stepped(state.value, up: up, step: step))
    }

    /// `value` moved one `step` up or down on the step grid (0.53 → 0.5625 / 0.5). Pure.
    public nonisolated static func stepped(_ value: Double, up: Bool, step: Double) -> Double {
        let n = value / step
        let snapped = up ? (n + 1e-6).rounded(.down) + 1 : (n - 1e-6).rounded(.up) - 1
        return min(1, max(0, snapped * step))
    }

    public func refresh() {
        controllable = DisplayServicesBrightness.controllableDisplays()
        var s = BrightnessState()
        if let d = targetDisplay, let v = DisplayServicesBrightness.get(d) {
            s.value = v
            s.exact = true
        } else if service != 0, let exact = Self.readBrightness(service) {
            s.value = Double(exact)
            s.exact = true
        } else {
            s.value = shadow
            s.exact = false
            s.unavailableReason = "No display brightness control (DisplayServices / IOKit) for these displays"
        }
        if s != state {
            state = s
            onChange?(s)
        }
    }

    // MARK: IOKit

    private func locateService() {
        releaseService()
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }
        while case let candidate = IOIteratorNext(iterator), candidate != 0 {
            if service == 0, Self.readBrightness(candidate) != nil {
                service = candidate
            } else {
                IOObjectRelease(candidate)
            }
        }
    }

    private func releaseService() {
        if service != 0 {
            IOObjectRelease(service)
            service = 0
        }
    }

    private nonisolated static func readBrightness(_ service: io_service_t) -> Float? {
        var value: Float = 0
        let result = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value)
        return result == kIOReturnSuccess ? value : nil
    }
}
