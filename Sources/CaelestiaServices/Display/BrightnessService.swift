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

/// Brightness with public APIs only.
///
/// - Displays that publish an `IODisplayConnect` service (external displays over DDC-capable
///   connections on Intel Macs, some older panels) are read and set through
///   `IODisplayGetFloatParameter` / `IODisplaySetFloatParameter(kIODisplayBrightnessKey)`.
/// - Built-in Apple Silicon panels expose no such service, and the APIs that read their
///   brightness (`DisplayServices`, `CoreDisplay_Display_GetUserBrightness`) are private, so this
///   service *tracks* the level instead: the WM forwards every F1/F2 (brightness key) press through
///   `noteBrightnessKey(up:)`, which moves a shadow value by 1/16 (the system's own key step), and
///   `exact` is `false`. `set(_:)` then posts as many brightness key events as needed to reach the
///   target. The shadow starts at 1.0 (full) until the first key press, which the OSD shows as an
///   approximate bar; the stock macOS brightness HUD stays visible for those key events.
@MainActor
public final class BrightnessService {
    /// Brightness change per F1/F2 press (macOS uses 16 steps).
    public static let keyStep: Double = 1.0 / 16.0

    public private(set) var state = BrightnessState()
    public var onChange: ((BrightnessState) -> Void)?
    /// How brightness keys are posted when no API exists; the WM may route this through its tap.
    public var postBrightnessKey: (MediaKeyKind) -> Void = { MediaKeyPoster.post($0) }

    private var service: io_service_t = 0
    private var shadow: Double = 1
    private var observer: NSObjectProtocol?
    private var running = false

    public init() {}

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

    /// The WM calls this for every brightness key it sees (down events only) so the tracked value
    /// follows what macOS did.
    public func noteBrightnessKey(up: Bool) {
        shadow = clamp(shadow + (up ? Self.keyStep : -Self.keyStep), 0...1)
        refresh()
    }

    /// Sets brightness to `value` (0...1). Without an IOKit control this presses the brightness
    /// keys `round(|Δ| / keyStep)` times.
    public func set(_ value: Double) {
        let target = clamp(value, 0...1)
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

    /// One Caelestia-style step (±10 % with an exact control, one key press otherwise).
    public func step(up: Bool) {
        if service != 0 {
            set(state.value + (up ? 0.1 : -0.1))
        } else {
            postBrightnessKey(up ? .brightnessUp : .brightnessDown)
            noteBrightnessKey(up: up)
        }
    }

    public func refresh() {
        var s = BrightnessState()
        if service != 0, let exact = Self.readBrightness(service) {
            s.value = Double(exact)
            s.exact = true
        } else {
            s.value = shadow
            s.exact = false
            s.unavailableReason = "Built-in display brightness is not readable with public APIs; showing the tracked level"
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
