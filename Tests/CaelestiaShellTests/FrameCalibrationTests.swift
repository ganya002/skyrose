import AppKit
import XCTest
import CaelestiaCore
@testable import CaelestiaShell

/// `caelestia frame calibrate` against a real ShellController (no services or monitors started;
/// it does create its NSPanels) saving into a temporary config file.
@MainActor
final class FrameCalibrationTests: XCTestCase {
    var dir: URL!
    var file: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("calibration-\(UUID().uuidString)")
        file = dir.appendingPathComponent("config.toml")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private let builtIn = DisplayInfo(id: "BUILTIN", name: "Built-in Retina Display", frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                      isPrimary: true, isBuiltIn: true, hasNotch: true)
    private let external = DisplayInfo(id: "EXT", name: "DELL U2720Q", frame: CGRect(x: 1470, y: 0, width: 2560, height: 1440))

    private func controller(radius: Double? = 10, displays: [DisplayInfo]? = nil, running: Bool = true) -> ShellController {
        var config = Config()
        if let radius { config.frame.displayCornerRadius = radius }
        let state = ShellState(scheme: ShellTheme.gabby.scheme, config: config, animations: AnimationTable.gabbySpringy,
                               displays: displays ?? [builtIn, external], converter: CoordinateConverter(primaryHeight: 956))
        let c = ShellController(state: state, host: nil)
        c.configFileURL = file
        if running { c.start(services: false) }
        return c
    }

    private func key(_ code: UInt16, shift: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [], timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    private func failure(_ r: Result<(String, Double), FrameCalibrationError>) -> String? {
        if case .failure(let e) = r { return e.message }
        return nil
    }

    private func savedConfig() throws -> Config { try ConfigLoader.load(from: file) }

    // MARK: Start

    func testStartByIdAndByNameCaseInsensitive() throws {
        let c = controller()
        defer { c.stop() }
        var r = try c.startFrameCalibration(display: "EXT").get()
        XCTAssertEqual(r.0, "EXT")
        XCTAssertEqual(r.1, 10)
        XCTAssertTrue(c.isCalibratingFrame)
        r = try c.startFrameCalibration(display: "built-in retina display").get()
        XCTAssertEqual(r.0, "BUILTIN")
        XCTAssertEqual(c.calibration?.displayID, "BUILTIN", "a second start moves the existing panel")
    }

    func testStartWithoutQueryPicksADisplay() throws {
        let c = controller()
        defer { c.stop() }
        let r = try c.startFrameCalibration().get()
        XCTAssertTrue(["BUILTIN", "EXT"].contains(r.0))
        let empty = try c.startFrameCalibration(display: "").get()
        XCTAssertTrue(["BUILTIN", "EXT"].contains(empty.0))
    }

    func testUnknownDisplayFails() {
        let c = controller()
        defer { c.stop() }
        switch c.startFrameCalibration(display: "nope") {
        case .success: XCTFail("expected a failure")
        case .failure(let e): XCTAssertTrue(e.message.contains("nope"))
        }
        XCTAssertFalse(c.isCalibratingFrame)
    }

    func testFailsWhenTheShellIsNotRunningOrHasNoDisplay() {
        let stopped = controller(running: false)
        XCTAssertEqual(failure(stopped.startFrameCalibration()), "the shell is not running")
        let none = controller(displays: [])
        defer { none.stop() }
        XCTAssertEqual(failure(none.startFrameCalibration()), "no display")
    }

    func testStartReportsTheAutoRadiusPerDisplay() throws {
        let c = controller(radius: nil)
        defer { c.stop() }
        XCTAssertEqual(try c.startFrameCalibration(display: "BUILTIN").get().1, 10)
        XCTAssertEqual(c.displayCornerRadius(for: builtIn, corners: .bottom), 0, "built-in bottom corners are square")
        XCTAssertEqual(try c.startFrameCalibration(display: "EXT").get().1, 0)
    }

    // MARK: Top / bottom

    func testTabSwitchesToTheBottomCornersWhichSaveUnderTheirOwnKey() throws {
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        XCTAssertEqual(c.calibration?.corners, .top)
        XCTAssertTrue(c.calibrationKey(key(48)))
        XCTAssertEqual(c.calibration?.corners, .bottom)
        XCTAssertTrue(c.calibrationKey(key(126)))
        XCTAssertEqual(c.bottomCornerRadiusTrials["BUILTIN"], 0.5)
        XCTAssertNil(c.cornerRadiusTrials["BUILTIN"], "the top corners are untouched")
        XCTAssertEqual(c.layouts["BUILTIN"]?.bottomCornerRadius, 0.5)
        XCTAssertEqual(c.layouts["BUILTIN"]?.displayCornerRadius, 10)
        XCTAssertEqual(c.calibration?.view.bottomRadius, 0.5)
        XCTAssertTrue(c.calibrationKey(key(48)))
        XCTAssertEqual(c.calibration?.corners, .top)
        XCTAssertTrue(c.calibrationKey(key(125)))
        c.finishCalibration(save: true)
        let saved = try savedConfig()
        XCTAssertEqual(saved.displays["BUILTIN"]?.displayCornerRadius, 9.5)
        XCTAssertEqual(saved.displays["BUILTIN"]?.displayBottomCornerRadius, 0.5)
    }

    func testOnlyTheChangedPairIsSaved() throws {
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        _ = c.calibrationKey(key(48))
        _ = c.calibrationKey(key(126))
        c.finishCalibration(save: true)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains("displayBottomCornerRadius = 0.5"))
        XCTAssertFalse(text.contains("displayCornerRadius ="))
    }

    func testCancelDropsBottomTrialsToo() throws {
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        _ = c.calibrationKey(key(48))
        c.stepCalibration(by: 3)
        c.finishCalibration(save: false)
        XCTAssertTrue(c.bottomCornerRadiusTrials.isEmpty)
        XCTAssertEqual(c.layouts["BUILTIN"]?.bottomCornerRadius, 0)
    }

    func testOutlineHasSeparateTopAndBottomRadii() {
        let b = CGRect(x: 0, y: 0, width: 400, height: 300)
        let p = FrameCalibrationView.outline(in: b, top: 20, bottom: 0)
        let w = FrameCalibrationView.lineWidth
        // A point just inside the square bottom-left corner of the line's path is inside; the same
        // spot at the rounded top-left is outside.
        XCTAssertTrue(p.contains(CGPoint(x: w / 2 + 1, y: 300 - w / 2 - 1)))
        XCTAssertFalse(p.contains(CGPoint(x: w / 2 + 1, y: w / 2 + 1)))
    }

    // MARK: Step

    func testStepRoundsToHundredthsAndClamps() throws {
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        c.stepCalibration(by: 0.123)
        XCTAssertEqual(c.cornerRadiusTrials["BUILTIN"], 10.12)
        XCTAssertEqual(c.calibration?.view.radius, 10.12)
        c.stepCalibration(by: 1000)
        XCTAssertEqual(c.cornerRadiusTrials["BUILTIN"], 60)
        c.stepCalibration(by: -1000)
        XCTAssertEqual(c.cornerRadiusTrials["BUILTIN"], 0)
        XCTAssertEqual(c.displayCornerRadius(for: builtIn), 0, "the frame draws the trial")
        XCTAssertEqual(c.configuredCornerRadius(builtIn), 10, "the configured value is untouched")
    }

    func testStepWithoutCalibrationDoesNothing() {
        let c = controller()
        defer { c.stop() }
        c.stepCalibration(by: 1)
        XCTAssertTrue(c.cornerRadiusTrials.isEmpty)
    }

    // MARK: Finish

    func testSaveWritesEveryTriedDisplayIntoItsOwnTable() throws {
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        c.stepCalibration(by: 2.5)
        _ = try c.startFrameCalibration(display: "EXT").get()
        c.stepCalibration(by: -3)
        c.finishCalibration(save: true)
        XCTAssertFalse(c.isCalibratingFrame)
        let saved = try savedConfig()
        XCTAssertEqual(saved.displays["BUILTIN"]?.displayCornerRadius, 12.5)
        XCTAssertEqual(saved.displays["EXT"]?.displayCornerRadius, 7)
        XCTAssertEqual(saved.frame.displayCornerRadius, -1, "global value not written")
        // Trials stay drawn until the reloaded config carries the same values.
        XCTAssertEqual(c.displayCornerRadius(for: builtIn), 12.5)
    }

    func testSaveKeepsAnExistingUserFileAndReplacesTheKey() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "# mine\n[wm]\ngapsIn = 3\n\n[displays.\"BUILTIN\"]\ndisplayCornerRadius = 4.0\n".write(to: file, atomically: true, encoding: .utf8)
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        c.stepCalibration(by: 1)
        c.finishCalibration(save: true)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# mine\n"))
        XCTAssertEqual(text.components(separatedBy: "displayCornerRadius").count - 1, 1)
        let cfg = try ConfigLoader.parse(toml: text)
        XCTAssertEqual(cfg.wm.gapsIn, 3)
        XCTAssertEqual(cfg.displays["BUILTIN"]?.displayCornerRadius, 11)
    }

    func testCancelWritesNothingAndDropsTrials() throws {
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        c.stepCalibration(by: 5)
        c.finishCalibration(save: false)
        XCTAssertFalse(c.isCalibratingFrame)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(c.cornerRadiusTrials.isEmpty)
        XCTAssertEqual(c.displayCornerRadius(for: builtIn), 10)
    }

    func testSaveWithoutChangesWritesNothing() throws {
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        c.finishCalibration(save: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testTrialIsDroppedOnceTheReloadedConfigCarriesTheSameValue() throws {
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        c.stepCalibration(by: 2)
        c.finishCalibration(save: true)
        XCTAssertEqual(c.cornerRadiusTrials["BUILTIN"], 12)
        c.state.config.displays["BUILTIN"] = {
            var o = DisplayOverride()
            o.displayCornerRadius = 12
            return o
        }()
        XCTAssertEqual(c.displayCornerRadius(for: builtIn), 12)
        XCTAssertNil(c.cornerRadiusTrials["BUILTIN"])
    }

    func testStopForgetsCalibrationAndTrials() throws {
        let c = controller()
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        c.stepCalibration(by: 1)
        c.stop()
        XCTAssertFalse(c.isCalibratingFrame)
        XCTAssertTrue(c.cornerRadiusTrials.isEmpty)
    }

    // MARK: Keys

    func testArrowKeysStepByHalfAndShiftByTenth() throws {
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        XCTAssertTrue(c.calibrationKey(key(126)))
        XCTAssertEqual(c.cornerRadiusTrials["BUILTIN"], 10.5)
        XCTAssertTrue(c.calibrationKey(key(125)))
        XCTAssertTrue(c.calibrationKey(key(125)))
        XCTAssertEqual(c.cornerRadiusTrials["BUILTIN"], 9.5)
        XCTAssertTrue(c.calibrationKey(key(126, shift: true)))
        XCTAssertEqual(c.cornerRadiusTrials["BUILTIN"], 9.6)
        XCTAssertTrue(c.calibrationKey(key(125, shift: true)))
        XCTAssertTrue(c.calibrationKey(key(125, shift: true)))
        XCTAssertEqual(c.cornerRadiusTrials["BUILTIN"], 9.4)
    }

    func testLeftRightSwitchDisplays() throws {
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        XCTAssertTrue(c.calibrationKey(key(124)))
        XCTAssertEqual(c.calibration?.displayID, "EXT")
        XCTAssertTrue(c.calibrationKey(key(124)))
        XCTAssertEqual(c.calibration?.displayID, "BUILTIN", "wraps around")
        XCTAssertTrue(c.calibrationKey(key(123)))
        XCTAssertEqual(c.calibration?.displayID, "EXT")
    }

    func testReturnAndEnterSaveEscapeCancels() throws {
        for code: UInt16 in [36, 76] {
            let c = controller()
            _ = try c.startFrameCalibration(display: "BUILTIN").get()
            c.stepCalibration(by: 1)
            XCTAssertTrue(c.calibrationKey(key(code)))
            XCTAssertFalse(c.isCalibratingFrame)
            XCTAssertEqual(try savedConfig().displays["BUILTIN"]?.displayCornerRadius, 11)
            try? FileManager.default.removeItem(at: file)
            c.stop()
        }
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        c.stepCalibration(by: 1)
        XCTAssertTrue(c.calibrationKey(key(53)))
        XCTAssertFalse(c.isCalibratingFrame)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testOtherKeysAreNotConsumed() throws {
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        XCTAssertFalse(c.calibrationKey(key(0)))
        XCTAssertTrue(c.isCalibratingFrame)
        XCTAssertTrue(c.cornerRadiusTrials.isEmpty)
    }

    // MARK: Frame follows the radius

    func testSurfacesRebuildWithTheTrialRadius() throws {
        let c = controller()
        defer { c.stop() }
        _ = try c.startFrameCalibration(display: "BUILTIN").get()
        c.stepCalibration(by: 5)
        XCTAssertEqual(c.layouts["BUILTIN"]?.displayCornerRadius, 15)
        XCTAssertEqual(c.layouts["EXT"]?.displayCornerRadius, 10, "other displays keep the configured radius")
    }

    func testOutlineKeepsTheRadiusAndStaysInsideBounds() {
        let b = CGRect(x: 0, y: 0, width: 400, height: 300)
        let p = FrameCalibrationView.outline(in: b, radius: 10)
        XCTAssertEqual(p.boundingBoxOfPath.minX, FrameCalibrationView.lineWidth / 2, accuracy: 0.01)
        XCTAssertEqual(p.boundingBoxOfPath.width, 400 - FrameCalibrationView.lineWidth, accuracy: 0.01)
        XCTAssertFalse(p.contains(CGPoint(x: 1, y: 1)), "a corner pixel is outside the rounded outline")
        XCTAssertNoThrow(FrameCalibrationView.outline(in: b, radius: 0))
        XCTAssertNoThrow(FrameCalibrationView.outline(in: b, radius: 1000))
    }
}
