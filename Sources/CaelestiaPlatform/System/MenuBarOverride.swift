import CoreGraphics
import Darwin
import Foundation

/// Removes Apple's menu bar entirely, including the reveal at the top edge. SIP-off mode only.
///
/// The hide belongs to this process's WindowServer connection, so quitting or crashing brings the
/// bar back without any cleanup. No macOS setting is written. Main thread only.
public enum MenuBarOverride {
    private typealias Connection = @convention(c) () -> Int32
    private typealias SetBar = @convention(c) (Int32, Double, Double, Double) -> Int32

    /// `SLSSetMenuBarInsetAndAlpha` on this Mac (macOS 27): 0 removes the bar, and 1 leaves it
    /// removed. Anything in between hands it back to macOS, shown or auto-hidden as set there.
    static let removed = 0.0
    static let handedBack = 0.99

    private static let api: (connection: Int32, set: SetBar)? = {
        _ = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        let all = UnsafeMutableRawPointer(bitPattern: -2)
        guard let c = dlsym(all, "SLSMainConnectionID"), let s = dlsym(all, "SLSSetMenuBarInsetAndAlpha") else { return nil }
        return (unsafeBitCast(c, to: Connection.self)(), unsafeBitCast(s, to: SetBar.self))
    }()

    /// Tests replace it.
    static var send: (Double) -> Void = { value in
        guard let api else { return }
        _ = api.set(api.connection, 0, 1, value)
    }

    /// Whether SkyRose wants the bar gone. Stays true during a peek, so windows don't jump.
    public private(set) static var isHidden = false
    /// Layout has to be read again: the top strip was reserved or freed.
    public static var onChange: (() -> Void)?

    private static var peekToken = 0
    private static var peeking = false

    public static func set(hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        peekToken += 1
        peeking = false
        send(hidden ? removed : handedBack)
        onChange?()
    }

    /// macOS can rebuild the bar (sleep, display changes), so the hide is repeated regularly.
    public static func reassert() {
        if isHidden, !peeking { send(removed) }
    }

    /// Hands the bar back for a few seconds. Does nothing when SkyRose isn't hiding it.
    public static func peek(seconds: TimeInterval) {
        guard isHidden else { return }
        peeking = true
        peekToken += 1
        let token = peekToken
        send(handedBack)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard token == peekToken else { return }
            peeking = false
            send(removed)
        }
    }

    /// Tests only.
    static func reset() {
        isHidden = false
        peeking = false
        peekToken += 1
    }
}
