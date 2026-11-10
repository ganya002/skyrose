import CaelestiaCore
import CoreFoundation
import CoreGraphics
import Darwin
import Foundation

/// Per-window corner radii from SkyLight's window iterator.
///
/// `SLSWindowIteratorGetCornerRadii` is present in the system SkyLight and returns four doubles
/// (top-left, top-right, bottom-right, bottom-left). It works with SIP on: the same iterator
/// yabai and JankyBorders use. Symbols are resolved at runtime, so a macOS that drops one just
/// makes this return nil and the border falls back to `windowRounding`.
public enum WindowCornerQuery {
    private typealias Connection = @convention(c) () -> Int32
    private typealias Query = @convention(c) (Int32, CFArray, Int32) -> Unmanaged<CFTypeRef>?
    private typealias CopyWindows = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private typealias Advance = @convention(c) (CFTypeRef) -> Bool
    private typealias WindowIDFn = @convention(c) (CFTypeRef) -> UInt32
    private typealias RadiiFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?

    private struct API {
        var connection: Int32
        var query: Query
        var copy: CopyWindows
        var advance: Advance
        var windowID: WindowIDFn
        var radii: RadiiFn
    }

    private static let api: API? = {
        _ = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        let all = UnsafeMutableRawPointer(bitPattern: -2)
        func sym<T>(_ name: String) -> T? {
            guard let p = dlsym(all, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let connection: Connection = sym("SLSMainConnectionID"),
              let query: Query = sym("SLSWindowQueryWindows"),
              let copy: CopyWindows = sym("SLSWindowQueryResultCopyWindows"),
              let advance: Advance = sym("SLSWindowIteratorAdvance"),
              let windowID: WindowIDFn = sym("SLSWindowIteratorGetWindowID"),
              let radii: RadiiFn = sym("SLSWindowIteratorGetCornerRadii") else { return nil }
        return API(connection: connection(), query: query, copy: copy, advance: advance, windowID: windowID, radii: radii)
    }()

    private static let lock = NSLock()
    private static var cache: [CGWindowID: (size: CGSize, radii: CornerRadii)] = [:]

    /// Radii for each id, read once per size. A miss (no symbol, or the window is gone) is absent
    /// and the caller keeps `windowRounding`.
    public static func radii(for sizes: [CGWindowID: CGSize]) -> [CGWindowID: CornerRadii] {
        var known: [CGWindowID: CornerRadii] = [:]
        var needed: [CGWindowID] = []
        lock.lock()
        for (id, size) in sizes {
            if let hit = cache[id], abs(hit.size.width - size.width) < 1, abs(hit.size.height - size.height) < 1 {
                known[id] = hit.radii
            } else {
                needed.append(id)
            }
        }
        lock.unlock()
        guard !needed.isEmpty, let api else { return known }
        let fresh = read(needed, api: api)
        lock.lock()
        for id in needed {
            guard let radii = fresh[id], let size = sizes[id] else { continue }
            cache[id] = (size, radii)
            known[id] = radii
        }
        // Drop windows that are gone so the cache does not grow forever.
        cache = cache.filter { sizes[$0.key] != nil }
        lock.unlock()
        return known
    }

    /// Four doubles from `SLSWindowIteratorGetCornerRadii`. Nil when the array is not four numbers.
    public static func parse(_ array: CFArray) -> CornerRadii? {
        guard CFArrayGetCount(array) >= 4 else { return nil }
        func number(_ index: Int) -> Double? {
            let raw = CFArrayGetValueAtIndex(array, index)
            guard let raw else { return nil }
            let value = unsafeBitCast(raw, to: CFTypeRef.self)
            guard CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
            var out = 0.0
            return CFNumberGetValue(unsafeBitCast(value, to: CFNumber.self), .doubleType, &out) ? out : nil
        }
        guard let tl = number(0), let tr = number(1), let br = number(2), let bl = number(3) else { return nil }
        return CornerRadii(topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
    }

    private static func read(_ ids: [CGWindowID], api: API) -> [CGWindowID: CornerRadii] {
        let list = ids as CFArray
        guard let query = api.query(api.connection, list, Int32(ids.count))?.takeRetainedValue(),
              let iterator = api.copy(query)?.takeRetainedValue() else { return [:] }
        var found: [CGWindowID: CornerRadii] = [:]
        let wanted = Set(ids)
        while api.advance(iterator) {
            let id = CGWindowID(api.windowID(iterator))
            guard wanted.contains(id), let array = api.radii(iterator)?.takeRetainedValue(),
                  let radii = parse(array) else { continue }
            found[id] = radii
        }
        return found
    }
}
