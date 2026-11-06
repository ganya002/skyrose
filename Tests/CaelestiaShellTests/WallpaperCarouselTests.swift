import AppKit
@testable import CaelestiaShell
import XCTest

@MainActor
final class WallpaperCarouselTests: XCTestCase {
    let walls = ["aurora", "beach", "city", "dunes", "forest"].map { URL(fileURLWithPath: "/w/\($0).jpg") }

    func model(current: Int = 2) -> LauncherModel {
        let m = LauncherModel()
        m.currentWallpaper = walls[current]
        m.wallpapers = walls
        return m
    }

    func testTypingTheCommandTurnsTheLauncherIntoTheCarousel() {
        let m = model()
        let appBody = m.bodySize
        XCTAssertFalse(m.isWallpaperMode)
        m.query = ">wallpaper"
        XCTAssertFalse(m.isWallpaperMode, "Caelestia needs the trailing space")
        m.query = ">wallpaper "
        XCTAssertTrue(m.isWallpaperMode)
        XCTAssertEqual(m.wallpaperResults, walls)
        XCTAssertEqual(m.wallpaperIndex, 2, "starts on the desktop's wallpaper")
        XCTAssertEqual(m.bodySize.height, LauncherModel.padding * 2 + LauncherModel.wallpaperHeight + LauncherModel.gap + LauncherModel.searchHeight)
        XCTAssertNotEqual(m.bodySize, appBody)
    }

    func testWallpaperCommandAutocompletes() {
        XCTAssertEqual(LauncherCommand.all.first { $0.name == "wallpaper" }?.effect, .autocomplete("wallpaper"))
    }

    func testSlotsFollowCaelestiaNumItems() {
        let slot = LauncherModel.carouselItemWidth
        XCTAssertEqual(slot, 280 * 0.8 + 30)
        XCTAssertEqual(LauncherModel.carouselSlots(room: slot * 12, count: 40), 9, "at most maxWallpapers")
        XCTAssertEqual(LauncherModel.carouselSlots(room: slot * 4.5, count: 40), 3, "even counts drop to odd")
        XCTAssertEqual(LauncherModel.carouselSlots(room: slot * 2.2, count: 40), 1, "two becomes one")
        XCTAssertEqual(LauncherModel.carouselSlots(room: slot * 9, count: 5), 5)
        XCTAssertEqual(LauncherModel.carouselSlots(room: 10, count: 5), 0)
        let m = model()
        m.carouselRoom = slot * 12
        m.query = ">wallpaper "
        XCTAssertEqual(m.carouselSize.width, 5 * slot)
        m.carouselRoom = slot * 1.5
        XCTAssertEqual(m.carouselSize.width, LauncherModel.itemWidth * 1.2, "never narrower than the app list × 1.2")
    }

    func testPathIsCircular() {
        XCTAssertEqual(LauncherModel.pathOffset(0, current: 0, count: 5), 0)
        XCTAssertEqual(LauncherModel.pathOffset(4, current: 0, count: 5), -1)
        XCTAssertEqual(LauncherModel.pathOffset(1, current: 4, count: 5), 2)
        XCTAssertEqual(LauncherModel.pathOffset(3, current: 1, count: 5), 2)
    }

    func testMovingPreviewsAndWraps() {
        let m = model(current: 4)
        var previews: [URL] = []
        m.onPreview = { previews.append($0) }
        m.query = ">wallpaper "
        XCTAssertEqual(previews, [walls[4]])
        m.move(1)
        XCTAssertEqual(m.wallpaperIndex, 0, "wraps like a PathView")
        m.move(-2)
        XCTAssertEqual(m.wallpaperIndex, 3)
        XCTAssertEqual(previews, [walls[4], walls[0], walls[3]])
    }

    func testSearchFiltersAndStartsOnTheBestMatch() {
        let m = model()
        var previews: [URL] = []
        m.onPreview = { previews.append($0) }
        m.query = ">wallpaper for"
        XCTAssertEqual(m.wallpaperResults.first, walls[4])
        XCTAssertEqual(m.wallpaperIndex, 0)
        XCTAssertEqual(previews.last, walls[4])
        m.query = ">wallpaper zzzz"
        XCTAssertTrue(m.wallpaperResults.isEmpty)
    }

    func testEnterPicksTheCentredWallpaper() {
        let m = model()
        var picked: URL?
        var launched = false
        m.onPickWallpaper = { picked = $0 }
        m.onActivate = { _ in launched = true }
        m.query = ">wallpaper "
        m.move(1)
        m.activateSelected()
        XCTAssertEqual(picked, walls[3])
        XCTAssertFalse(launched)
    }

    func testLeavingTheCommandStopsPreviewing() {
        let m = model()
        var previews = 0
        m.onPreview = { _ in previews += 1 }
        m.query = ">wallpaper "
        m.query = "saf"
        XCTAssertFalse(m.isWallpaperMode)
        m.move(1)
        XCTAssertEqual(previews, 1)
    }

    func testPanelHoldsTheWidestCarousel() {
        let room = LauncherModel.carouselItemWidth * 12
        let max = LauncherModel.maxBodySize(carouselRoom: room)
        XCTAssertEqual(max.width, 9 * LauncherModel.carouselItemWidth + 2 * LauncherModel.padding)
        XCTAssertEqual(LauncherModel.maxBodySize.width, LauncherModel.itemWidth + 2 * LauncherModel.padding)
    }

    func testPreviewIsIdleUntilAsked() {
        let p = WallpaperPreview()
        XCTAssertFalse(p.isActive)
        p.revert()
        p.finish()
        XCTAssertFalse(p.isActive)
        XCTAssertEqual(WallpaperPreview.crossfade, 0.6)
    }
}
