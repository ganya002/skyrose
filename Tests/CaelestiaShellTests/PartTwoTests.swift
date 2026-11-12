import CaelestiaCore
import CoreGraphics
import XCTest

@testable import CaelestiaShell

/// Display geometries: MacBook Air with notch strip, big external, ultrawide, small and portrait.
private let geometries: [(name: String, area: CGRect, topExtra: Double)] = [
    ("air-notch", CGRect(x: 0, y: 0, width: 1470, height: 956), 33),
    ("external-1440p", CGRect(x: 1470, y: 0, width: 2560, height: 1440), 0),
    ("ultrawide", CGRect(x: 0, y: 0, width: 5120, height: 1440), 0),
    ("small", CGRect(x: 0, y: 0, width: 1024, height: 600), 24),
    ("portrait", CGRect(x: 0, y: 0, width: 1080, height: 1920), 0),
]

final class ShellSizingTests: XCTestCase {
    private func layout(_ g: (name: String, area: CGRect, topExtra: Double), reveal: Double = 0) -> (DisplayLayout, CGRect) {
        let l = DisplayLayout(area: g.area, thickness: 10, barWidth: 48, topExtra: g.topExtra)
        return (l, l.inner(barReveal: reveal))
    }

    func testDashboardFitsEveryGeometryAndKeepsAspect() {
        for g in geometries {
            for reveal in [0.0, 1.0] {
                let (l, inner) = layout(g, reveal: reveal)
                let fit = ShellSizing.dashboard(inner: inner, fillet: 25)
                XCTAssertLessThanOrEqual(fit.scale, 1, g.name)
                XCTAssertGreaterThanOrEqual(fit.scale, 0.3, g.name)
                let size = CGSize(width: fit.body.width + 50, height: fit.body.height)
                let f = l.drawerFrame(size: size, edge: .top, barReveal: reveal)
                XCTAssertTrue(inner.insetBy(dx: -0.5, dy: -0.5).contains(f), "\(g.name) reveal \(reveal): \(f) in \(inner)")
                XCTAssertEqual(f.maxY, inner.maxY, accuracy: 0.5, "attached to the top band, below the notch strip")
                XCTAssertEqual(fit.body.width / fit.body.height, ShellSizing.dashboardDesign.width / ShellSizing.dashboardDesign.height, accuracy: 0.01)
            }
        }
    }

    func testDashboardIsFullSizeOnLargeScreensAndShrinksOnSmallOnes() {
        let big = layout(geometries[1]).1
        XCTAssertEqual(ShellSizing.dashboard(inner: big).scale, 1)
        XCTAssertEqual(ShellSizing.dashboard(inner: big).body, CGSize(width: 860, height: 560))
        let small = layout(geometries[3]).1
        XCTAssertLessThan(ShellSizing.dashboard(inner: small).scale, 1)
    }

    func testNotchStripIsNeverCovered() {
        let (l, inner) = layout(geometries[0])
        XCTAssertEqual(inner.maxY, 956 - 10 - 33)
        let f = l.drawerFrame(size: CGSize(width: 910, height: 560), edge: .top, barReveal: 0)
        XCTAssertLessThanOrEqual(f.maxY, 956 - 33 - 10)
    }

    func testSidebarWidthAndFrame() {
        for g in geometries {
            let (l, inner) = layout(g)
            let w = ShellSizing.sidebarWidth(inner: inner)
            XCTAssertLessThanOrEqual(w, 400, g.name)
            XCTAssertGreaterThanOrEqual(w, 260, g.name)
            let f = l.drawerFrame(size: CGSize(width: w, height: inner.height), edge: .right, barReveal: 0)
            XCTAssertEqual(f.maxX, inner.maxX, g.name)
            XCTAssertEqual(f.minY, inner.minY, accuracy: 0.5, g.name)
            XCTAssertEqual(f.maxY, inner.maxY, accuracy: 0.5, g.name)
        }
        XCTAssertEqual(ShellSizing.sidebarWidth(inner: layout(geometries[1]).1), 400)
    }

    func testPopoutIsClampedInsideTheInnerRect() {
        for g in geometries {
            let inner = layout(g, reveal: 1).1
            for anchor in [inner.minY - 500, inner.minY + 5, inner.midY, inner.maxY - 5, inner.maxY + 500] {
                let f = ShellSizing.popoutFrame(size: CGSize(width: 300, height: 320), anchorMidY: anchor, inner: inner)
                XCTAssertGreaterThanOrEqual(f.minY, inner.minY, g.name)
                XCTAssertLessThanOrEqual(f.maxY, inner.maxY, g.name)
                XCTAssertEqual(f.minX, inner.minX, g.name)
            }
        }
        let inner = layout(geometries[1], reveal: 1).1
        let mid = ShellSizing.popoutFrame(size: CGSize(width: 300, height: 300), anchorMidY: inner.midY, inner: inner)
        XCTAssertEqual(mid.midY, inner.midY, accuracy: 1)
        let tall = ShellSizing.popoutFrame(size: CGSize(width: 300, height: 99999), anchorMidY: inner.midY, inner: inner)
        XCTAssertEqual(tall.height, inner.height)
    }

    func testWallpaperStripFits() {
        for g in geometries {
            let (l, inner) = layout(g)
            let body = ShellSizing.wallpaperBody(inner: inner)
            let f = l.drawerFrame(size: CGSize(width: body.width + 50, height: body.height), edge: .bottom, barReveal: 0)
            XCTAssertLessThanOrEqual(body.width, 920, g.name)
            XCTAssertGreaterThanOrEqual(f.minX, inner.minX - 25, g.name)
            XCTAssertEqual(f.minY, inner.minY, g.name)
        }
    }

    func testFitScaleDegenerate() {
        XCTAssertEqual(ShellSizing.fitScale(design: .zero, available: CGSize(width: 10, height: 10)), 1)
        XCTAssertEqual(ShellSizing.fitScale(design: CGSize(width: 100, height: 100), available: CGSize(width: 5, height: 5)), 0.3)
    }
}

final class NotificationTests: XCTestCase {
    private func note(_ app: String, _ summary: String, _ ago: TimeInterval, now: Date) -> ShellNotification {
        ShellNotification(appName: app, summary: summary, date: now.addingTimeInterval(-ago))
    }

    func testStoreAddsNewestFirstDismissesClearsAndCaps() {
        var s = NotificationStore()
        s.limit = 3
        let a = ShellNotification(appName: "a", summary: "1")
        s.add(a)
        s.add(ShellNotification(appName: "a", summary: "2"))
        s.add(ShellNotification(appName: "b", summary: "3"))
        s.add(ShellNotification(appName: "b", summary: "4"))
        XCTAssertEqual(s.items.map(\.summary), ["4", "3", "2"])
        s.dismiss(s.items[1].id)
        XCTAssertEqual(s.count, 2)
        s.clear()
        XCTAssertEqual(s.count, 0)
    }

    func testGroupingByAppNewestGroupFirst() {
        let now = Date()
        let g = NotificationGrouper.group([
            note("old", "x", 5000, now: now), note("new", "y", 10, now: now), note("old", "z", 20, now: now),
        ])
        XCTAssertEqual(g.map(\.appName), ["new", "old"])
        XCTAssertEqual(g.first(where: { $0.appName == "old" })?.items.map(\.summary), ["z", "x"])
        XCTAssertEqual(g.first?.appName, "new")
    }

    func testRelativeTimeAndTitle() {
        let now = Date()
        XCTAssertEqual(NotificationGrouper.relativeTime(now.addingTimeInterval(-5), now: now), "now")
        XCTAssertEqual(NotificationGrouper.relativeTime(now.addingTimeInterval(-300), now: now), "5m")
        XCTAssertEqual(NotificationGrouper.relativeTime(now.addingTimeInterval(-7200), now: now), "2h")
        XCTAssertEqual(NotificationGrouper.relativeTime(now.addingTimeInterval(-86400), now: now), "1d")
        XCTAssertEqual(NotificationGrouper.relativeTime(now.addingTimeInterval(-14 * 86400), now: now), "2w")
        XCTAssertEqual(NotificationGrouper.title(count: 0), "No notifications")
        XCTAssertEqual(NotificationGrouper.title(count: 1), "1 notification")
        XCTAssertEqual(NotificationGrouper.title(count: 4), "4 notifications")
    }
}

final class QuickToggleTests: XCTestCase {
    func testOnlySafeThingsAreRealToggles() {
        var s = StatusInfo()
        s.wifiAvailable = true
        s.bluetoothAvailable = true
        let t = QuickToggles.make(status: s, dnd: false, darkMode: true)
        XCTAssertEqual(t.map(\.id), ["wifi", "bluetooth", "dnd", "darkmode"])
        XCTAssertEqual(t.first { $0.id == "wifi" }?.kind, .toggle)
        XCTAssertEqual(t.first { $0.id == "dnd" }?.kind, .toggle)
        XCTAssertEqual(t.first { $0.id == "bluetooth" }?.kind, .opensSettings, "no public Bluetooth switch")
        XCTAssertEqual(t.first { $0.id == "darkmode" }?.kind, .opensSettings, "macOS appearance is read-only here")
    }

    func testUnavailableHardwareIsHidden() {
        var s = StatusInfo()
        s.wifiAvailable = false
        s.bluetoothAvailable = false
        XCTAssertEqual(QuickToggles.make(status: s, dnd: true, darkMode: false).map(\.id), ["dnd", "darkmode"])
        XCTAssertTrue(QuickToggles.make(status: s, dnd: true, darkMode: false).first { $0.id == "dnd" }!.active)
    }

    func testStatusIconsMapToPopouts() {
        XCTAssertEqual(PopoutKind.forStatusIcon("audio"), .audio)
        XCTAssertEqual(PopoutKind.forStatusIcon("microphone"), .audio)
        XCTAssertEqual(PopoutKind.forStatusIcon("network"), .network)
        XCTAssertEqual(PopoutKind.forStatusIcon("bluetooth"), .bluetooth)
        XCTAssertEqual(PopoutKind.forStatusIcon("battery"), .battery)
        XCTAssertNil(PopoutKind.forStatusIcon("kbLayout"))
        XCTAssertNil(PopoutKind.forStatusIcon("lockStatus"))
    }

    /// The Controls button opens on click only: hovering it must not pop the panel open.
    func testControlsOpensOnClickNotHover() {
        XCTAssertEqual(PopoutKind.forStatusIcon("controls"), .controls)
        XCTAssertNil(PopoutKind.forBarItem("controls"))
        XCTAssertEqual(PopoutKind.forBarItem("network"), .network)
    }
}

final class DashboardLogicTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    func testClockParts() {
        let d = date(2026, 11, 3, 8, 0, 42)
        XCTAssertEqual(ClockParts.make(d, use24h: false, seconds: true, calendar: cal),
                       ClockParts(hours: "08", minutes: "00", seconds: "42", meridiem: "AM"))
        XCTAssertEqual(ClockParts.make(date(2026, 11, 3, 15, 5), use24h: true, seconds: false, calendar: cal),
                       ClockParts(hours: "15", minutes: "05", seconds: nil, meridiem: nil))
        XCTAssertEqual(ClockParts.make(date(2026, 11, 3, 0, 5), use24h: false, seconds: false, calendar: cal).hours, "12")
        XCTAssertEqual(ClockParts.make(date(2026, 11, 3, 12, 5), use24h: false, seconds: false, calendar: cal).meridiem, "PM")
        XCTAssertTrue(ClockParts.localeUses24h(Locale(identifier: "nb_NO")))
        XCTAssertFalse(ClockParts.localeUses24h(Locale(identifier: "en_US")))
    }

    func testCalendarGridNovember2026() {
        let today = date(2026, 11, 3)
        let start = CalendarGrid.monthStart(containing: today, offsetMonths: 0, calendar: cal)
        let weeks = CalendarGrid.weeks(monthStart: start, today: today, calendar: cal)
        XCTAssertEqual(weeks.count, 6)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        // 1 Nov 2026 is a Sunday: the first cell is the 1st (reference screenshot shows Sun 1).
        XCTAssertEqual(weeks[0][0].number, 1)
        XCTAssertTrue(weeks[0][0].inMonth)
        XCTAssertEqual(weeks.flatMap { $0 }.filter(\.isToday).map(\.number), [3])
        XCTAssertEqual(weeks.flatMap { $0 }.filter(\.inMonth).count, 30)
        XCTAssertEqual(weeks[5].last?.inMonth, false)
    }

    func testCalendarLeadingDaysAndOffsets() {
        let today = date(2026, 11, 3)
        let dec = CalendarGrid.monthStart(containing: today, offsetMonths: 1, calendar: cal)
        XCTAssertEqual(cal.component(.month, from: dec), 12)
        let weeks = CalendarGrid.weeks(monthStart: dec, today: today, calendar: cal)
        XCTAssertEqual(weeks[0][0].number, 29, "1 Dec 2026 is a Tuesday: Sun 29 Nov leads")
        XCTAssertFalse(weeks[0][0].inMonth)
        XCTAssertTrue(weeks.flatMap { $0 }.filter(\.isToday).isEmpty)
        let prev = CalendarGrid.monthStart(containing: date(2026, 1, 15), offsetMonths: -1, calendar: cal)
        XCTAssertEqual(cal.component(.year, from: prev), 2025)
        var monday = cal
        monday.firstWeekday = 2
        XCTAssertEqual(CalendarGrid.weekdayHeaders(calendar: monday).first, monday.shortWeekdaySymbols[1])
        XCTAssertEqual(CalendarGrid.weekdayHeaders(calendar: cal).count, 7)
        // Monday first: Sat and Sun are the last two columns. Sunday first: the first and last.
        XCTAssertEqual((0..<7).filter { CalendarGrid.isWeekend(column: $0, calendar: monday) }, [5, 6])
        var sunday = cal
        sunday.firstWeekday = 1
        XCTAssertEqual((0..<7).filter { CalendarGrid.isWeekend(column: $0, calendar: sunday) }, [0, 6])
    }

    func testTabsAndText() {
        XCTAssertEqual(DashboardTab(config: "MEDIA"), .media)
        XCTAssertEqual(DashboardTab(config: "nonsense"), .overview)
        XCTAssertEqual(DashboardTab.allCases.map(\.rawValue), ["overview", "media", "performance", "weather"])
        XCTAssertEqual(ShellText.uptimeText(15 * 3600 + 11 * 60), "up 15 hours, 11 min")
        XCTAssertEqual(ShellText.uptimeText(30), "up 0 min")
        XCTAssertEqual(ShellText.bytesText(8 * 1024 * 1024 * 1024), "8.0 GiB")
        XCTAssertEqual(ShellText.thermalText(9), "Critical")
        var s = StatusInfo()
        s.batteryCharging = true
        s.batteryTimeRemainingMinutes = 75
        s.lowPowerMode = true
        XCTAssertEqual(BatteryText.status(s), "Charging · 1 h 15 min left · Low Power Mode")
    }
}

final class WallpaperLibraryTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("wp-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    func testScanFiltersSortsAndSkipsHidden() throws {
        let d = tempDir()
        defer { try? FileManager.default.removeItem(at: d) }
        for n in ["b.PNG", "a.jpg", "a10.jpg", "a2.jpg", "notes.txt", ".hidden.jpg", "c.heic"] {
            FileManager.default.createFile(atPath: d.appendingPathComponent(n).path, contents: Data([0]))
        }
        let r = WallpaperLibrary.scan(folder: d)
        XCTAssertNil(r.message)
        XCTAssertEqual(r.urls.map(\.lastPathComponent), ["a.jpg", "a2.jpg", "a10.jpg", "b.PNG", "c.heic"])
    }

    func testMissingEmptyAndNotAFolder() throws {
        let missing = WallpaperLibrary.scan(folder: URL(fileURLWithPath: "/definitely/not/here-\(UUID().uuidString)"))
        XCTAssertTrue(missing.urls.isEmpty)
        XCTAssertTrue(missing.message?.hasPrefix("Folder not found") == true)
        let d = tempDir()
        defer { try? FileManager.default.removeItem(at: d) }
        let empty = WallpaperLibrary.scan(folder: d)
        XCTAssertTrue(empty.urls.isEmpty)
        XCTAssertTrue(empty.message?.hasPrefix("No wallpapers") == true)
        let file = d.appendingPathComponent("x.jpg")
        FileManager.default.createFile(atPath: file.path, contents: Data([1]))
        XCTAssertTrue(WallpaperLibrary.scan(folder: file).message?.hasPrefix("Not a folder") == true)
    }

    func testFolderExpansionKeyAndRandom() {
        XCTAssertEqual(WallpaperLibrary.folderURL("~/Pictures/Wallpapers").path, NSHomeDirectory() + "/Pictures/Wallpapers")
        XCTAssertEqual(WallpaperLibrary.folderURL("").path, NSHomeDirectory() + "/Pictures/Wallpapers")
        XCTAssertEqual(WallpaperLibrary.folderURL("/tmp/w").path, "/tmp/w")
        let k1 = WallpaperLibrary.thumbnailKey(path: "/a.jpg", modified: 10, size: 5)
        XCTAssertEqual(k1, WallpaperLibrary.thumbnailKey(path: "/a.jpg", modified: 10, size: 5))
        XCTAssertNotEqual(k1, WallpaperLibrary.thumbnailKey(path: "/a.jpg", modified: 11, size: 5))
        XCTAssertEqual(k1.count, 16)
        var rng = SystemRandomNumberGenerator()
        let urls = [URL(fileURLWithPath: "/a.jpg"), URL(fileURLWithPath: "/b.jpg")]
        for _ in 0..<20 { XCTAssertEqual(WallpaperLibrary.random(from: urls, excluding: urls[0], using: &rng), urls[1]) }
        XCTAssertEqual(WallpaperLibrary.random(from: [urls[0]], excluding: urls[0], using: &rng), urls[0])
        XCTAssertNil(WallpaperLibrary.random(from: [], excluding: nil, using: &rng))
    }

    func testLauncherWallpaperCommandsAreWired() {
        XCTAssertEqual(LauncherCommand.all.first { $0.name == "wallpaper" }?.effect, .autocomplete("wallpaper"))
        XCTAssertEqual(LauncherCommand.all.first { $0.name == "random" }?.effect, .randomWallpaper)
        XCTAssertTrue(Drawer.allCases.contains(.wallpaper))
    }
}
