import CaelestiaLayout
import CaelestiaPlatform
@testable import CaelestiaWMKit
import XCTest

/// Focusing a window without raising it puts back only the windows that really cover it.
/// Raising a parked, invisible or non-overlapping window flashed that app in front (Teams flicker).
final class OrderRestoreTests: XCTestCase {
    let front = CGRect(x: 0, y: 0, width: 800, height: 600)

    func testOnlyVisibleOverlappingWindowsAboveAreRestored() {
        let stack = [
            CGWindowSnapshot(id: 1, pid: 10, bounds: CGRect(x: 1469, y: 924, width: 800, height: 600)), // parked (other workspace)
            CGWindowSnapshot(id: 2, pid: 11, bounds: CGRect(x: 100, y: 100, width: 300, height: 300)),  // floating, covers the target
            CGWindowSnapshot(id: 3, pid: 12, bounds: CGRect(x: 900, y: 0, width: 300, height: 300)),    // beside it
            CGWindowSnapshot(id: 4, pid: 13, bounds: front, alpha: 0),                                   // invisible helper
            CGWindowSnapshot(id: 5, pid: 14, layer: 3, bounds: front),                                   // floating panel layer
            CGWindowSnapshot(id: 9, pid: 20, bounds: front),                                             // the target
            CGWindowSnapshot(id: 7, pid: 15, bounds: front),                                             // below: never raised
        ]
        let visible: [WindowID: CGRect] = [2: stack[1].bounds, 3: stack[2].bounds, 4: front, 5: front, 7: front]
        let restore = WindowManager.windowsToRestore(above: 9, stack: stack, frame: front) { visible[$0] }
        XCTAssertEqual(restore, [2])
    }

    func testFrontmostTargetRestoresNothing() {
        let stack = [CGWindowSnapshot(id: 9, pid: 20, bounds: front), CGWindowSnapshot(id: 7, pid: 15, bounds: front)]
        XCTAssertEqual(WindowManager.windowsToRestore(above: 9, stack: stack, frame: front) { _ in self.front }, [])
    }
}
