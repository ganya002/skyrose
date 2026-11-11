import AppKit
import SwiftUI
import CaelestiaCore
import XCTest

@testable import CaelestiaShell

@MainActor
final class SessionModelTests: XCTestCase {
    private var time = Date(timeIntervalSince1970: 1_000_000)
    private var runs: [SessionAction] = []
    private var closes = 0

    private func model() -> SessionModel {
        let m = SessionModel()
        m.now = { [unowned self] in self.time }
        m.onRun = { [unowned self] in self.runs.append($0) }
        m.onClose = { [unowned self] in self.closes += 1 }
        return m
    }

    func testFirstPressArmsWithoutRunning() {
        let m = model()
        m.press(.shutdown)
        XCTAssertEqual(m.armed, .shutdown)
        XCTAssertEqual(m.focusedAction, .shutdown)
        XCTAssertTrue(runs.isEmpty)
    }

    func testSecondPressWithinWindowRunsExactlyOnce() {
        let m = model()
        m.press(.sleep)
        time += SessionModel.armWindow - 0.1
        m.press(.sleep)
        XCTAssertEqual(runs, [.sleep])
        XCTAssertNil(m.armed)
        m.press(.sleep)  // arms again, does not run a second time
        XCTAssertEqual(runs, [.sleep])
        XCTAssertEqual(m.armed, .sleep)
    }

    func testSecondPressAfterWindowReArms() {
        let m = model()
        m.press(.reboot)
        time += SessionModel.armWindow + 0.5
        m.press(.reboot)
        XCTAssertTrue(runs.isEmpty)
        XCTAssertEqual(m.armed, .reboot)
        time += 1
        m.press(.reboot)
        XCTAssertEqual(runs, [.reboot])
    }

    func testDifferentActionReArmsThatOne() {
        let m = model()
        m.press(.logout)
        m.press(.shutdown)
        XCTAssertTrue(runs.isEmpty)
        XCTAssertEqual(m.armed, .shutdown)
        XCTAssertEqual(m.focusedAction, .shutdown)
    }

    func testMoveWrapsAndDisarms() {
        let m = model()
        XCTAssertEqual(m.focusedAction, .logout)
        m.move(-1)
        XCTAssertEqual(m.focusedAction, SessionModel.actions.last)
        m.move(1)
        XCTAssertEqual(m.focusedAction, .logout)
        m.press(.logout)
        m.move(1)
        XCTAssertNil(m.armed, "moving off the armed action disarms")
        m.press(.shutdown)
        m.move(0)
        XCTAssertEqual(m.armed, .shutdown, "staying on it keeps it armed")
    }

    func testEscapeDisarmsFirstThenCloses() {
        let m = model()
        m.press(.sleep)
        m.escape()
        XCTAssertNil(m.armed)
        XCTAssertEqual(closes, 0)
        m.escape()
        XCTAssertEqual(closes, 1)
    }

    func testPressFocusedAndReset() {
        let m = model()
        m.move(1)
        m.pressFocused()
        XCTAssertEqual(m.armed, SessionModel.actions[1])
        m.reset()
        XCTAssertNil(m.armed)
        XCTAssertEqual(m.focused, 0)
    }

    func testBodySize() {
        let n = Double(SessionModel.actions.count + 1)
        XCTAssertEqual(SessionModel.bodySize.width, 110)
        XCTAssertEqual(SessionModel.bodySize.height, n * 80 + (n - 1) * 15 + 30)
    }

    func testCommandsNeverUseSudoAndUseDocumentedPaths() {
        for a in SessionAction.allCases {
            guard let c = SessionCommands.command(for: a) else { continue }
            XCTAssertFalse(([c.path] + c.args).contains { $0.contains("sudo") }, "\(a)")
        }
        let logout = SessionCommands.command(for: .logout)
        XCTAssertEqual(logout?.path, "/usr/bin/osascript")
        XCTAssertEqual(logout?.args, ["-e", "tell application \"System Events\" to log out"])
        XCTAssertEqual(SessionCommands.command(for: .shutdown)?.args, ["-e", "tell application \"System Events\" to shut down"])
        XCTAssertEqual(SessionCommands.command(for: .reboot)?.args, ["-e", "tell application \"System Events\" to restart"])
        XCTAssertEqual(SessionCommands.command(for: .sleep)?.path, "/usr/bin/pmset")
        XCTAssertEqual(SessionCommands.command(for: .sleep)?.args, ["sleepnow"])
        XCTAssertNil(SessionCommands.command(for: .lock))
        let restart = SessionCommands.command(for: .restartSkyRose)
        XCTAssertEqual(restart?.args, ["restart"])
        XCTAssertTrue(restart?.path.hasSuffix("/skyrose") == true, "the bundled CLI, not one from PATH")
    }
}

final class OSDTimerTests: XCTestCase {
    func testHidesAfterDelay() {
        var t = OSDTimer()
        XCTAssertFalse(t.shouldHide(at: 100, hovered: false), "never changed")
        t.changed(at: 10)
        XCTAssertFalse(t.shouldHide(at: 10 + OSDModel.hideDelay - 0.01, hovered: false))
        XCTAssertTrue(t.shouldHide(at: 10 + OSDModel.hideDelay, hovered: false))
    }

    func testNeverWhileHovered() {
        var t = OSDTimer()
        t.changed(at: 0)
        XCTAssertFalse(t.shouldHide(at: 1000, hovered: true))
        XCTAssertTrue(t.shouldHide(at: 1000, hovered: false))
    }

    func testNewChangeExtendsAndResetClears() {
        var t = OSDTimer()
        t.changed(at: 0)
        t.changed(at: 1)
        XCTAssertFalse(t.shouldHide(at: 1 + 1.4, hovered: false))
        XCTAssertTrue(t.shouldHide(at: 1 + 1.5, hovered: false))
        t.reset()
        XCTAssertNil(t.lastChange)
        XCTAssertFalse(t.shouldHide(at: 1000, hovered: false))
    }

    func testCustomDelay() {
        var t = OSDTimer()
        t.changed(at: 0)
        XCTAssertTrue(t.shouldHide(at: 0.5, hovered: false, delay: 0.5))
    }
}

@MainActor
final class OSDModelTests: XCTestCase {
    func testBodySize() {
        let m = OSDModel()
        XCTAssertEqual(m.bodySize, CGSize(width: 2 * 30 + 10 + 20, height: 170))
        m.brightnessAvailable = false
        XCTAssertEqual(m.bodySize, CGSize(width: 50, height: 170))
        XCTAssertEqual(OSDModel.maxBodySize, CGSize(width: 90, height: 170))
    }
}

final class ToastQueueTests: XCTestCase {
    private func toast(_ title: String, _ at: TimeInterval, kind: ToastKind = .info, message: String = "") -> Toast {
        Toast(kind: kind, title: title, message: message, createdAt: at)
    }

    func testNewestFirst() {
        var q = ToastQueue()
        q.add(toast("a", 0))
        q.add(toast("b", 1))
        q.add(toast("c", 2))
        XCTAssertEqual(q.toasts.map(\.title), ["c", "b", "a"])
    }

    func testMaxVisibleTrimsOldest() {
        var q = ToastQueue()
        q.maxVisible = 3
        for i in 0..<6 { q.add(toast("t\(i)", Double(i))) }
        XCTAssertEqual(q.toasts.map(\.title), ["t5", "t4", "t3"])
    }

    func testDuplicateRefreshesAndMovesToTop() {
        var q = ToastQueue()
        q.add(toast("a", 0))
        q.add(toast("b", 1))
        q.add(toast("a", 3))
        XCTAssertEqual(q.toasts.map(\.title), ["a", "b"])
        XCTAssertEqual(q.toasts[0].createdAt, 3)
        // Different kind or message is not a duplicate.
        q.add(toast("a", 4, kind: .error))
        q.add(toast("a", 5, message: "x"))
        XCTAssertEqual(q.toasts.count, 4)
    }

    func testExpire() {
        var q = ToastQueue()
        q.add(toast("old", 0))
        q.add(toast("new", 4))
        XCTAssertFalse(q.expire(at: 4.9))
        XCTAssertTrue(q.expire(at: 5))
        XCTAssertEqual(q.toasts.map(\.title), ["new"])
        XCTAssertTrue(q.expire(at: 9))
        XCTAssertTrue(q.isEmpty)
        XCTAssertFalse(q.expire(at: 100))
    }

    func testCustomTimeout() {
        var q = ToastQueue()
        q.timeout = 1
        q.add(toast("a", 0))
        XCTAssertTrue(q.expire(at: 1))
    }

    func testDismiss() {
        var q = ToastQueue()
        let id = q.add(toast("a", 0))
        q.add(toast("b", 1))
        q.dismiss(id)
        XCTAssertEqual(q.toasts.map(\.title), ["b"])
        q.dismiss(UUID())
        XCTAssertEqual(q.toasts.count, 1)
    }

    func testKindDefaultIcons() {
        for k in ToastKind.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: ShellIcon.sf(k.defaultIcon), accessibilityDescription: nil), "\(k)")
        }
    }
}

final class ShellThemeTests: XCTestCase {
    private func theme(_ edit: (inout Config) -> Void = { _ in }, reduceMotion: Bool = false) -> ShellTheme {
        var c = Config()
        edit(&c)
        return ShellTheme(scheme: ShellTheme.fallbackScheme, config: c, reduceMotion: reduceMotion)
    }

    func testAlphasFromConfig() {
        let t = theme()
        XCTAssertEqual(t.baseAlpha, 0.75)
        XCTAssertEqual(t.layerAlpha, 0.35)
        let custom = theme { $0.appearance.transparencyBase = 0.5; $0.appearance.transparencyLayers = 0.2 }
        XCTAssertEqual(custom.baseAlpha, 0.5)
        XCTAssertEqual(custom.layerAlpha, 0.2)
    }

    func testTransparencyDisabledMeansOpaque() {
        let t = theme { $0.appearance.transparencyEnabled = false }
        XCTAssertEqual(t.baseAlpha, 1)
        XCTAssertEqual(t.layerAlpha, 1)
    }

    func testGeometryFromConfig() {
        let t = theme()
        XCTAssertEqual(t.frameRounding, 25)
        XCTAssertEqual(t.frameThickness, 10)
        XCTAssertEqual(t.barWidth, 60)
        let off = theme { $0.wm.screenFrame = false }
        XCTAssertEqual(off.frameThickness, 0)
        let custom = theme { $0.wm.windowRounding = 20; $0.wm.gapsOut = 4 }
        XCTAssertEqual(custom.frameRounding, 24)
    }

    func testDurationScale() {
        let t = theme()
        XCTAssertEqual(t.durationScale, 0.8)
        XCTAssertEqual(t.seconds(500), 0.4, accuracy: 1e-12)
        XCTAssertEqual(t.seconds(0), 0)
        let slow = theme { $0.animations.shellDurationScale = 2 }
        XCTAssertEqual(slow.seconds(500), 1, accuracy: 1e-12)
    }

    func testReduceMotion() {
        let t = theme(reduceMotion: true)
        XCTAssertTrue(t.reduceMotion)
        // Reduce Motion caps every duration at the 120 ms short fade (x0.8 shell scale), never 0.
        XCTAssertEqual(t.seconds(500), 0.096, accuracy: 1e-12)
        XCTAssertEqual(t.seconds(50), 0.04, accuracy: 1e-12, "shorter durations are kept")
        XCTAssertEqual(t.seconds(0), 0)
        // ...with a plain ease-in-out curve and no slide distance.
        XCTAssertEqual(t.curve(.emphasizedDecel, ms: 500), Animation.easeInOut(duration: 0.096))
        XCTAssertEqual(t.slide(300), 0)
        XCTAssertEqual(theme().slide(300), 300)
        let ignored = theme({ $0.animations.respectReduceMotion = false }, reduceMotion: true)
        XCTAssertFalse(ignored.reduceMotion)
        XCTAssertEqual(ignored.seconds(500), 0.4, accuracy: 1e-12)
        XCTAssertFalse(theme().reduceMotion)
    }

    func testFirstInstalled() {
        XCTAssertNil(ShellTheme.firstInstalled(["SF Pro"]), "SF Pro is the system font, never custom")
        XCTAssertNil(ShellTheme.firstInstalled(["Definitely Not A Font 12345", "SF Pro"]))
        XCTAssertEqual(ShellTheme.firstInstalled(["Definitely Not A Font 12345", "SF Pro", "Helvetica"]), "Helvetica")
        XCTAssertEqual(ShellTheme.firstInstalled(["Helvetica", "Menlo"]), "Helvetica")
        XCTAssertNil(ShellTheme.firstInstalled([]))
    }

    func testPanelFillUsesBaseAlpha() {
        let t = theme()
        XCTAssertEqual(t.panelFill.alphaComponent, 0.75, accuracy: 0.001)
    }
}

final class ShellIconTests: XCTestCase {
    private func assertSymbol(_ material: String, file: StaticString = #filePath, line: UInt = #line) {
        let sf = ShellIcon.sf(material)
        XCTAssertFalse(sf.isEmpty, material, file: file, line: line)
        XCTAssertNotNil(NSImage(systemSymbolName: sf, accessibilityDescription: nil), "\(material) -> \(sf)", file: file, line: line)
    }

    func testLauncherCommandIcons() {
        for c in LauncherCommand.all { assertSymbol(c.icon) }
    }

    @MainActor
    func testSessionIcons() {
        for a in SessionAction.allCases { assertSymbol(SessionModel.icon(a)) }
    }

    func testOtherMappedIcons() {
        for m in ["search", "volume_up", "volume_down", "volume_mute", "volume_off", "brightness_high", "brightness_low", "wifi",
                  "wifi_off", "lan", "bluetooth", "keyboard_capslock", "mic", "mic_off", "battery", "apps", "terminal", "restart_alt"] {
            assertSymbol(m)
        }
    }

    func testUnknownPassesThrough() {
        XCTAssertEqual(ShellIcon.sf("star.fill"), "star.fill")
    }

    // MARK: Material Symbols (part 4)

    func testEverySFNameInTheMapIsARealSymbol() {
        for (sf, _) in ShellIcon.fromSF {
            XCTAssertNotNil(NSImage(systemSymbolName: sf, accessibilityDescription: nil), sf)
        }
    }

    func testGlyphResolvesSFAndMaterialNames() {
        XCTAssertEqual(ShellIcon.glyph("wifi.slash"), .init(material: "wifi_off", fill: false, sf: "wifi.slash"))
        XCTAssertEqual(ShellIcon.glyph("speaker.wave.2.fill"), .init(material: "volume_up", fill: true, sf: "speaker.wave.2.fill"))
        // A Material name from Caelestia IPC keeps its SF fallback.
        XCTAssertEqual(ShellIcon.glyph("power_settings_new"), .init(material: "power_settings_new", fill: false, sf: "power"))
        XCTAssertEqual(ShellIcon.glyph("notifications").sf, "bell.fill")
        // No Material equivalent: SF only.
        XCTAssertNil(ShellIcon.glyph("apple.logo").material)
        XCTAssertEqual(ShellIcon.glyph("").sf, "questionmark")
    }

    func testEveryMaterialFallbackIsARealSymbol() {
        let materials = Set(ShellIcon.fromSF.values.map(\.0))
        for m in materials {
            let sf = ShellIcon.glyph(m).sf
            XCTAssertNotNil(NSImage(systemSymbolName: sf, accessibilityDescription: nil), "\(m) -> \(sf)")
        }
    }

    func testMaterialWeightAxis() {
        XCTAssertEqual(ShellIcon.materialWeight(.regular), 400)
        XCTAssertEqual(ShellIcon.materialWeight(.light), 300)
        XCTAssertEqual(ShellIcon.materialWeight(.semibold), 600)
        XCTAssertEqual(ShellIcon.materialWeight(.black), 700)
    }

    /// Every Material name the shell uses is one ligature glyph in the pinned font (a typo would
    /// draw the word). Needs the downloaded font; skipped on a Mac without it.
    func testEveryMaterialNameIsALigatureInTheFont() throws {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SkyRose/Fonts")
        let url = dir.appendingPathComponent("MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Material Symbols not downloaded") }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        ShellTheme.fontsChanged()
        XCTAssertTrue(ShellIcon.materialAvailable)
        var names = Set(ShellIcon.fromSF.values.map(\.0))
        names.formUnion(LauncherCommand.all.map(\.icon))
        names.formUnion(["brightness_high", "bedtime", "lock", "logout", "restart_alt", "cached", "downloading"])
        for fill in [false, true] {
            let font = ShellIcon.materialFont(size: 24, weight: 400, fill: fill)
            XCTAssertEqual(CTFontCopyFamilyName(font) as String, ShellIcon.materialFamily)
            for n in names where !n.contains(".") {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: n, attributes: [.font: font]))
                XCTAssertEqual(CTLineGetGlyphCount(line), 1, n)
            }
        }
    }
}

final class ScreenshotTextTests: XCTestCase {
    func testSummary() {
        let f = URL(fileURLWithPath: "/tmp/Screenshot 2026-11-06 at 09.05.07.png")
        let s = CGSize(width: 2940, height: 1912)
        XCTAssertEqual(ScreenshotText.summary(file: f, copied: true, size: s), "2940 × 1912 · copied, saved as Screenshot 2026-11-06 at 09.05.07.png")
        XCTAssertEqual(ScreenshotText.summary(file: nil, copied: true, size: s), "2940 × 1912 · copied to the clipboard")
        XCTAssertTrue(ScreenshotText.summary(file: nil, copied: false, size: s).contains("not saved"))
    }

    func testToastKeepsItsThumbnail() {
        var q = ToastQueue()
        _ = q.add(Toast(kind: .success, title: "Screenshot taken", createdAt: 0, imagePath: "/tmp/x.png"))
        XCTAssertEqual(q.toasts.first?.imagePath, "/tmp/x.png")
        XCTAssertEqual(Toast(kind: .info, title: "t", createdAt: 0).imagePath, "")
    }
}
