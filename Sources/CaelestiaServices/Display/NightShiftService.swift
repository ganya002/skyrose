import Foundation
import ObjectiveC

/// Night Shift on/off. macOS has no public API; CoreBrightness's `CBBlueLightClient` (what
/// Control Center and the `nightlight` tool use) works without root. Missing on Macs without
/// Night Shift, then `available` is false.
@MainActor
public final class NightShiftService {
    private let client: NSObject?

    public init() {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        client = (NSClassFromString("CBBlueLightClient") as? NSObject.Type)?.init()
    }

    public var available: Bool { client != nil && status() != nil }

    /// `getBlueLightStatus:` fills a struct whose first two bytes are `active` and `enabled`.
    private func status() -> (active: Bool, enabled: Bool)? {
        guard let client else { return nil }
        let sel = NSSelectorFromString("getBlueLightStatus:")
        guard client.responds(to: sel), let imp = client.method(for: sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: 64)
        guard unsafeBitCast(imp, to: Fn.self)(client, sel, buffer) else { return nil }
        return (buffer.load(fromByteOffset: 0, as: Bool.self), buffer.load(fromByteOffset: 1, as: Bool.self))
    }

    /// On right now (manually or by schedule). Byte 0 only says the feature is active on this Mac.
    public var isOn: Bool { status()?.enabled ?? false }

    public func set(_ on: Bool) {
        guard let client else { return }
        let sel = NSSelectorFromString("setEnabled:")
        guard client.responds(to: sel), let imp = client.method(for: sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Bool
        _ = unsafeBitCast(imp, to: Fn.self)(client, sel, on)
    }
}
