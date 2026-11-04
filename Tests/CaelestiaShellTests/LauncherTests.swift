import CaelestiaCore
import Foundation
import XCTest

@testable import CaelestiaShell

final class FuzzyMatcherTests: XCTestCase {
    private func score(_ q: String, _ c: String) -> Int? { FuzzyMatcher.match(q, in: c)?.score }

    func testSubsequenceRequired() {
        XCTAssertNotNil(FuzzyMatcher.match("ffx", in: "Firefox"))
        XCTAssertNil(FuzzyMatcher.match("xf", in: "Firefox"))
        XCTAssertNil(FuzzyMatcher.match("firefoxx", in: "Firefox"))
        XCTAssertNil(FuzzyMatcher.match("abc", in: "ab"))
    }

    func testCaseAndDiacriticInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.match("FIRE", in: "firefox"))
        XCTAssertNotNil(FuzzyMatcher.match("cafe", in: "Café"))
        XCTAssertNotNil(FuzzyMatcher.match("café", in: "CAFE"))
        XCTAssertEqual(score("cafe", "Café"), score("cafe", "Cafe"))
    }

    func testEmptyQueryMatchesWithZero() {
        XCTAssertEqual(FuzzyMatcher.match("", in: "anything"), FuzzyMatcher.Match(score: 0, positions: []))
        XCTAssertEqual(FuzzyMatcher.match("   ", in: "x")?.score, 0)
    }

    func testPrefixBeatsMiddle() {
        XCTAssertGreaterThan(score("fire", "Firefox")!, score("fire", "Backfire")!)
    }

    func testWordBoundaryBeatsMidWord() {
        XCTAssertGreaterThan(score("c", "Visual Code")!, score("c", "Abacus")!)
        XCTAssertGreaterThan(score("sp", "System Preferences")!, score("sp", "Wasxxxp")!)
    }

    func testCamelCaseHumpBeatsMidWord() {
        XCTAssertGreaterThan(score("ft", "FireTool")!, score("ft", "Afterthought")!)
    }

    func testConsecutiveBeatsScattered() {
        XCTAssertGreaterThan(score("abc", "xabcx")!, score("abc", "xaxbxcx")!)
    }

    func testPositions() {
        // Tightest window ending at the earliest full match (fzf v1): the 'f' of "fox", not the prefix.
        XCTAssertEqual(FuzzyMatcher.match("fx", in: "Firefox")?.positions, [4, 6])
        XCTAssertEqual(FuzzyMatcher.match("fire", in: "Firefox")?.positions, [0, 1, 2, 3])
        XCTAssertEqual(FuzzyMatcher.match("tx", in: "Text Edit")?.positions, [0, 2])
    }
}

final class CalculatorTests: XCTestCase {
    private func ev(_ s: String) throws -> Double { try Calculator.evaluate(s) }

    func testPrecedence() throws {
        XCTAssertEqual(try ev("2+3*4"), 14)
        XCTAssertEqual(try ev("(2+3)*4"), 20)
        XCTAssertEqual(try ev("10-4-3"), 3)
        XCTAssertEqual(try ev("100/10/5"), 2)
        XCTAssertEqual(try ev("7%4"), 3)
    }

    func testUnaryMinus() throws {
        XCTAssertEqual(try ev("-3+5"), 2)
        XCTAssertEqual(try ev("--3"), 3)
        XCTAssertEqual(try ev("2*-3"), -6)
        XCTAssertEqual(try ev("+4"), 4)
    }

    func testPower() throws {
        XCTAssertEqual(try ev("2^3"), 8)
        XCTAssertEqual(try ev("2^-1"), 0.5, accuracy: 1e-12)
        XCTAssertEqual(try ev("2^3*2"), 16)
        XCTAssertEqual(try ev("(1+1)^(1+2)"), 8)
    }

    func testImplicitMultiplication() throws {
        XCTAssertEqual(try ev("2pi"), 2 * Double.pi, accuracy: 1e-12)
        XCTAssertEqual(try ev("3(4+1)"), 15)
        XCTAssertEqual(try ev("2sqrt(16)"), 8)
    }

    func testFunctionsAndConstants() throws {
        XCTAssertEqual(try ev("sqrt(9)"), 3)
        XCTAssertEqual(try ev("abs(-4)"), 4)
        XCTAssertEqual(try ev("pi"), Double.pi)
        XCTAssertEqual(try ev("e"), M_E, accuracy: 1e-12)
        XCTAssertEqual(try ev("ln(e)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try ev("log(1000)"), 3, accuracy: 1e-12)
        XCTAssertEqual(try ev("log2(8)"), 3, accuracy: 1e-12)
        XCTAssertEqual(try ev("floor(2.7)"), 2)
        XCTAssertEqual(try ev("ceil(2.1)"), 3)
        XCTAssertEqual(try ev("round(2.5)"), 3)
        XCTAssertEqual(try ev("sin(0)"), 0, accuracy: 1e-12)
        XCTAssertEqual(try ev("cos(0)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try ev("SQRT(4)"), 2, "case-insensitive")
        XCTAssertEqual(try ev("2×3"), 6)
        XCTAssertEqual(try ev("6÷3"), 2)
        XCTAssertEqual(try ev("1,5+1"), 2.5, accuracy: 1e-12)
    }

    func testDivisionByZeroThrows() {
        XCTAssertThrowsError(try ev("1/0")) { XCTAssertEqual($0 as? Calculator.Failure, .divisionByZero) }
        XCTAssertThrowsError(try ev("5%0")) { XCTAssertEqual($0 as? Calculator.Failure, .divisionByZero) }
    }

    func testSyntaxErrorsThrow() {
        for bad in ["", "   ", "+", "2+", "(2", "2)", "2**3", "foo", "foo(1)", "sqrt", "sqrt 4", "1..2", "2 3 )", "$", "ln()", "()"] {
            XCTAssertThrowsError(try ev(bad), "\"\(bad)\"")
        }
    }

    func testNotFiniteThrows() {
        XCTAssertThrowsError(try ev("sqrt(-1)")) { XCTAssertEqual($0 as? Calculator.Failure, .notFinite) }
        XCTAssertThrowsError(try ev("10^999")) { XCTAssertEqual($0 as? Calculator.Failure, .notFinite) }
    }

    func testRandomGarbageNeverCrashes() {
        var rng = SystemRandomNumberGenerator()
        let alphabet = Array("0123456789+-*/%^()., abcdefpilnsqrtπ×÷e")
        for _ in 0..<3000 {
            let len = Int.random(in: 0...24, using: &rng)
            let s = String((0..<len).map { _ in alphabet.randomElement(using: &rng)! })
            _ = try? Calculator.evaluate(s)
            _ = Calculator.looksLikeMath(s)
        }
        // Deep nesting must not blow up.
        _ = try? Calculator.evaluate(String(repeating: "(", count: 500) + "1" + String(repeating: ")", count: 500))
    }

    func testFormat() {
        XCTAssertEqual(Calculator.format(4), "4")
        XCTAssertEqual(Calculator.format(-12), "-12")
        XCTAssertEqual(Calculator.format(0), "0")
        XCTAssertEqual(Calculator.format(2.5), "2.5")
        XCTAssertEqual(Calculator.format(0.1 + 0.2), "0.3")
        XCTAssertEqual(Calculator.format(1.0 / 3.0), "0.3333333333")
        XCTAssertFalse(Calculator.format(2.50).hasSuffix("0"))
        XCTAssertFalse(Calculator.format(Double.pi).contains("e"))
    }

    func testLooksLikeMath() {
        XCTAssertTrue(Calculator.looksLikeMath("2+2"))
        XCTAssertTrue(Calculator.looksLikeMath("3(4+1)"))
        XCTAssertTrue(Calculator.looksLikeMath("10 / 4"))
        XCTAssertTrue(Calculator.looksLikeMath("sqrt(16)"))
        XCTAssertFalse(Calculator.looksLikeMath("firefox"))
        XCTAssertFalse(Calculator.looksLikeMath("2"))
        XCTAssertFalse(Calculator.looksLikeMath("1password"))
        XCTAssertFalse(Calculator.looksLikeMath("2+"))
        XCTAssertFalse(Calculator.looksLikeMath(""))
        XCTAssertFalse(Calculator.looksLikeMath("-5"), "a leading sign alone is not math")
    }
}

final class LauncherSearchTests: XCTestCase {
    private func app(_ name: String, _ id: String = "", desc: String = "", keywords: [String] = [], count: Int = 0) -> LaunchableApp {
        LaunchableApp(name: name, bundleID: id.isEmpty ? "com.test.\(name.lowercased())" : id,
                      url: URL(fileURLWithPath: "/Applications/\(name).app"), description: desc, keywords: keywords, launchCount: count)
    }

    private func names(_ items: [LauncherItem]) -> [String] { items.map(\.title) }

    func testCommandPrefixListsAllInOrder() {
        for q in [">", ">  ", "  > "] {
            let r = LauncherSearch.results(for: q, apps: [])
            XCTAssertEqual(r, LauncherCommand.all.map(LauncherItem.command), q)
        }
    }

    func testCommandQueryRanksLockFirst() {
        let r = LauncherSearch.results(for: ">loc", apps: [])
        XCTAssertEqual(r.first, .command(LauncherCommand.all.first { $0.name == "lock" }!))
        XCTAssertTrue(r.allSatisfy { if case .command = $0 { return true } else { return false } })
    }

    func testCommandNoMatchIsEmpty() {
        XCTAssertTrue(LauncherSearch.results(for: ">zzzq", apps: []).isEmpty)
    }

    func testCalcPrefix() {
        XCTAssertEqual(LauncherSearch.results(for: "=2+3*4", apps: []), [.calc(expression: "2+3*4", result: "14")])
        XCTAssertEqual(LauncherSearch.results(for: "= 1/4", apps: []), [.calc(expression: "1/4", result: "0.25")])
    }

    func testInvalidExpressionHasNilResult() {
        XCTAssertEqual(LauncherSearch.results(for: "=2+", apps: []), [.calc(expression: "2+", result: nil)])
        XCTAssertEqual(LauncherSearch.results(for: "=1/0", apps: []), [.calc(expression: "1/0", result: nil)])
        XCTAssertEqual(LauncherSearch.results(for: "=", apps: []), [.calc(expression: "", result: nil)])
        XCTAssertEqual(LauncherItem.calc(expression: "2+", result: nil).title, "Invalid expression")
    }

    func testPlainMathPutsCalcRowFirstThenApps() {
        let apps = [app("Calc2+2 Tool", desc: "x")]
        let r = LauncherSearch.results(for: "2+2", apps: apps)
        XCTAssertEqual(r.first, .calc(expression: "2+2", result: "4"))
        let r2 = LauncherSearch.results(for: "2+2", apps: [app("Two+2 App", keywords: ["2+2"])])
        XCTAssertEqual(r2.first, .calc(expression: "2+2", result: "4"))
        XCTAssertEqual(r2.count, 2)
    }

    func testEmptyQuerySortsByLaunchCountThenName() {
        let apps = [app("Zed", count: 0), app("beta", count: 5), app("Alpha", count: 0), app("Gamma", count: 9)]
        XCTAssertEqual(names(LauncherSearch.results(for: "", apps: apps)), ["Gamma", "beta", "Alpha", "Zed"])
    }

    func testFuzzyRanksFireFirefoxFirst() {
        let apps = [app("Backfire"), app("Fire Alarm Tool Extra Long Name"), app("Firefox"), app("Safari")]
        let r = names(LauncherSearch.results(for: "fire", apps: apps))
        XCTAssertEqual(r.first, "Firefox")
        XCTAssertFalse(r.contains("Safari"))
    }

    func testFrequencyBonusBreaksTies() {
        let apps = [app("Notes A", count: 0), app("Notes B", count: 20)]
        XCTAssertEqual(names(LauncherSearch.results(for: "notes", apps: apps)).first, "Notes B")
        XCTAssertEqual(LauncherSearch.frequencyBonus(0), 0)
        XCTAssertGreaterThan(LauncherSearch.frequencyBonus(3), LauncherSearch.frequencyBonus(1))
        XCTAssertEqual(LauncherSearch.frequencyBonus(1_000_000), 30)
    }

    func testDescriptionMatchesOnlyFromThreeChars() {
        let a = app("Zzz", desc: "Browse the web")
        XCTAssertNil(LauncherSearch.score("br", a))
        XCTAssertNotNil(LauncherSearch.score("bro", a))
        XCTAssertTrue(LauncherSearch.results(for: "bw", apps: [a]).isEmpty)
        XCTAssertEqual(LauncherSearch.results(for: "web", apps: [a]).count, 1)
    }

    func testKeywordsAndFileNameMatch() {
        let a = LaunchableApp(name: "Visual Thing", bundleID: "x", url: URL(fileURLWithPath: "/Applications/Weird.app"), keywords: ["Developer Tools"])
        XCTAssertNotNil(LauncherSearch.score("weird", a))
        XCTAssertNotNil(LauncherSearch.score("devtools", a) ?? LauncherSearch.score("developer", a))
    }

    func testLimitRespected() {
        let apps = (0..<30).map { app("App \($0)") }
        XCTAssertEqual(LauncherSearch.results(for: "app", apps: apps, limit: 5).count, 5)
        XCTAssertEqual(LauncherSearch.results(for: "", apps: apps, limit: 7).count, 7)
        XCTAssertEqual(LauncherSearch.results(for: "app", apps: apps).count, 30)
    }

    func testItemSubtitles() {
        XCTAssertEqual(LauncherItem.app(app("A", desc: "d")).subtitle, "d")
        XCTAssertEqual(LauncherItem.app(app("A")).subtitle, "A")
        XCTAssertEqual(LauncherItem.calc(expression: "1+1", result: "2").subtitle, "1+1 — press Enter to copy")
        XCTAssertEqual(LauncherItem.calc(expression: "1+", result: nil).subtitle, "1+")
    }
}

@MainActor
final class LauncherModelTests: XCTestCase {
    private func apps(_ n: Int) -> [LaunchableApp] {
        (0..<n).map { LaunchableApp(name: "App \(String(format: "%02d", $0))", bundleID: "id\($0)", url: URL(fileURLWithPath: "/Applications/App\($0).app")) }
    }

    func testMoveWraps() {
        let m = LauncherModel()
        m.apps = apps(3)
        XCTAssertEqual(m.selected, 0)
        m.move(-1)
        XCTAssertEqual(m.selected, 2)
        m.move(1)
        XCTAssertEqual(m.selected, 0)
        m.move(1); m.move(1); m.move(1)
        XCTAssertEqual(m.selected, 0)
    }

    func testMoveOnEmptyIsNoop() {
        let m = LauncherModel()
        m.move(1)
        XCTAssertEqual(m.selected, 0)
    }

    func testRefreshClampsSelection() {
        let m = LauncherModel()
        m.apps = apps(10)
        m.query = "app"
        m.selected = 9
        m.apps = apps(4)
        XCTAssertEqual(m.selected, 3)
        m.apps = []
        XCTAssertEqual(m.selected, 0)
    }

    func testEmptyQueryResetsSelectionToZero() {
        let m = LauncherModel()
        m.apps = apps(5)
        m.query = "app"
        m.selected = 3
        m.query = ""
        XCTAssertEqual(m.selected, 0)
        m.reset()
        XCTAssertEqual(m.query, "")
        XCTAssertEqual(m.selected, 0)
    }

    func testQueryChangeRefreshesItems() {
        let m = LauncherModel()
        m.apps = apps(5) + [LaunchableApp(name: "Firefox", bundleID: "ff", url: URL(fileURLWithPath: "/A/Firefox.app"))]
        XCTAssertEqual(m.items.count, 6)
        m.query = "fire"
        XCTAssertEqual(m.items.map(\.title), ["Firefox"])
    }

    func testActivateSelected() {
        let m = LauncherModel()
        m.apps = apps(3)
        var got: [LauncherItem] = []
        m.onActivate = { got.append($0) }
        m.move(1)
        m.activateSelected()
        XCTAssertEqual(got.map(\.title), ["App 01"])
    }

    func testBodySizeAndListHeight() {
        let m = LauncherModel()
        for (n, rows) in [(0, 1), (3, 3), (7, 7), (20, 7)] {
            m.apps = apps(n)
            XCTAssertEqual(m.visibleRows, rows, "n=\(n)")
            let list = Double(rows) * LauncherModel.itemHeight + Double(rows - 1) * LauncherModel.itemSpacing
            XCTAssertEqual(m.listHeight, list, "n=\(n)")
            XCTAssertEqual(m.bodySize.width, LauncherModel.itemWidth + 2 * LauncherModel.padding)
            XCTAssertEqual(m.bodySize.height, LauncherModel.padding + list + LauncherModel.gap + LauncherModel.searchHeight + LauncherModel.padding, "n=\(n)")
        }
        XCTAssertEqual(LauncherModel.maxBodySize, { m.apps = apps(50); return m.bodySize }())
        XCTAssertEqual(m.listHeight, 7 * 57 + 6 * 8)
    }
}
