import CaelestiaCore
import CoreFoundation
import CoreGraphics
import Darwin
import Foundation
import ScreenCaptureKit

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

    // Windows SkyLight calls square, measured once. A borderless window with rounded content
    // (SkyRose's own Settings, frameless apps) is a clear square to the WindowServer.
    private static var measured: [CGWindowID: CornerRadii] = [:]
    private static var measuring: Set<CGWindowID> = []
    private static var attempts: [CGWindowID: Int] = [:]
    private static let maxAttempts = 3

    /// Radii for each id. `changed` runs (on any thread) when a measurement finishes.
    public static func radii(for sizes: [CGWindowID: CGSize], changed: (@Sendable () -> Void)? = nil) -> [CGWindowID: CornerRadii] {
        var result = reported(for: sizes)
        var start: [CGWindowID] = []
        lock.lock()
        if measured.count > 512 { measured.removeAll() }
        if attempts.count > 512 { attempts.removeAll() }
        for (id, radii) in result where radii.isSquare {
            if let shape = measured[id] {
                result[id] = shape
            } else if !measuring.contains(id), attempts[id, default: 0] < maxAttempts {
                measuring.insert(id)
                attempts[id, default: 0] += 1
                start.append(id)
            }
        }
        lock.unlock()
        for id in start {
            Task.detached(priority: .utility) {
                // Give a new window a moment to draw.
                try? await Task.sleep(nanoseconds: 500_000_000)
                let shape = await measure(id)
                lock.lock()
                measuring.remove(id)
                if let shape { measured[id] = shape }
                lock.unlock()
                if shape != nil { changed?() }
            }
        }
        return result
    }

    /// What the window itself looks like at its corners. Nil without Screen Recording, for a
    /// window that cannot be captured, and for one with nothing drawn in a corner yet.
    private static func measure(_ id: CGWindowID) async -> CornerRadii? {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let window = content.windows.first(where: { $0.windowID == id }),
              window.frame.width > 1, window.frame.height > 1 else { return nil }
        let config = SCStreamConfiguration()
        let scale = backingScale(of: window.frame)
        config.width = max(2, Int((window.frame.width * scale).rounded()))
        config.height = max(2, Int((window.frame.height * scale).rounded()))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        let width = image.width, height = image.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = alpha.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return CornerRadiusFit.radii(alpha: alpha, width: width, height: height, scale: Double(width) / window.frame.width)
    }

    /// Pixels per point of the display the window is on. A window parked off every display
    /// uses the main one.
    private static func backingScale(of frame: CGRect) -> Double {
        var display = CGMainDisplayID()
        var found: UInt32 = 0
        var hit: CGDirectDisplayID = 0
        if CGGetDisplaysWithRect(frame, 1, &hit, &found) == .success, found > 0 { display = hit }
        guard let mode = CGDisplayCopyDisplayMode(display), mode.width > 0 else { return 2 }
        return Double(mode.pixelWidth) / Double(mode.width)
    }

    /// Radii for each id, read once per size. A miss (no symbol, or the window is gone) is absent
    /// and the caller keeps `windowRounding`.
    private static func reported(for sizes: [CGWindowID: CGSize]) -> [CGWindowID: CornerRadii] {
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
