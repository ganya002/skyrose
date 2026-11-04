import Foundation
import CoreGraphics
import TOMLKit

// MARK: - Model

/// What a rule matches. Every set field must match (AND); a rule with no fields matches every window.
///
/// `bundleID`, `appName`, `role`, `subrole` and `category` are case-insensitive globs: `*` matches any
/// run of characters, `?` one character, `|` separates alternatives (`feh|imv|swappy`) and a leading `!`
/// negates the whole pattern (`!AXStandardWindow`). `titleRegex` is an ICU regular expression evaluated
/// with search semantics (anchor with `^...$` for a full match, as the defaults do to mimic Hyprland).
/// `tag` requires a tag assigned by an earlier rule or passed in by the window manager.
public struct RuleMatch: Codable, Sendable, Hashable {
    public var bundleID: String?
    public var appName: String?
    public var titleRegex: String?
    public var role: String?
    public var subrole: String?
    public var category: String?
    public var tag: String?

    public init(
        bundleID: String? = nil, appName: String? = nil, titleRegex: String? = nil, role: String? = nil,
        subrole: String? = nil, category: String? = nil, tag: String? = nil
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.titleRegex = titleRegex
        self.role = role
        self.subrole = subrole
        self.category = category
        self.tag = tag
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case bundleID, appName, titleRegex, role, subrole, category, tag
    }

    /// True when no criterion is set (the rule applies to every window).
    public var isEmpty: Bool {
        bundleID == nil && appName == nil && titleRegex == nil && role == nil && subrole == nil && category == nil && tag == nil
    }
}

/// What a rule does. Mirrors Hyprland's windowrule fields; `nil` means "not set by this rule", so rules
/// merge field by field (later rules override earlier ones).
public struct RuleEffects: Codable, Sendable, Hashable {
    public var float: Bool?
    public var center: Bool?
    /// Width / height as a fraction (0...1) of the usable area, like Caelestia's `resize_by_screen`.
    /// 0 means "the full extent" (as in `resize_by_screen`).
    public var sizeW: Double?
    public var sizeH: Double?
    /// Width / height in points (takes precedence over the fractions).
    public var sizePointsW: Double?
    public var sizePointsH: Double?
    /// `"center"`, `"pip"` (bottom-right corner: `area.w*0.98 - w`, `area.h*0.97 - h`) or `"<x> <y>"`
    /// where each axis is a sum of terms like `98%-w`, `50%`, `100`, `100%-h-20` (`%` of the usable
    /// area, `w`/`h` the window size, bare numbers points). See ``FloatingMove``.
    public var move: String?
    /// `"special:<name>"`, `"special"` or a workspace number.
    public var workspace: String?
    public var opacity: Double?
    public var pin: Bool?
    public var keepAspectRatio: Bool?
    public var noBorder: Bool?
    public var noRounding: Bool?
    /// Corner radius override in points (Hyprland `rounding`); the popup tag uses `wm.popupRounding`'s value.
    public var rounding: Double?
    public var noGaps: Bool?
    public var noAnim: Bool?
    public var noInitialFocus: Bool?
    public var noFocus: Bool?
    public var idleInhibit: Bool?
    /// Tag(s) to add to the window; several tags are comma-separated.
    public var tag: String?

    public init(
        float: Bool? = nil, center: Bool? = nil, sizeW: Double? = nil, sizeH: Double? = nil,
        sizePointsW: Double? = nil, sizePointsH: Double? = nil, move: String? = nil, workspace: String? = nil,
        opacity: Double? = nil, pin: Bool? = nil, keepAspectRatio: Bool? = nil, noBorder: Bool? = nil,
        noRounding: Bool? = nil, rounding: Double? = nil, noGaps: Bool? = nil, noAnim: Bool? = nil,
        noInitialFocus: Bool? = nil, noFocus: Bool? = nil, idleInhibit: Bool? = nil, tag: String? = nil
    ) {
        self.float = float
        self.center = center
        self.sizeW = sizeW
        self.sizeH = sizeH
        self.sizePointsW = sizePointsW
        self.sizePointsH = sizePointsH
        self.move = move
        self.workspace = workspace
        self.opacity = opacity
        self.pin = pin
        self.keepAspectRatio = keepAspectRatio
        self.noBorder = noBorder
        self.noRounding = noRounding
        self.rounding = rounding
        self.noGaps = noGaps
        self.noAnim = noAnim
        self.noInitialFocus = noInitialFocus
        self.noFocus = noFocus
        self.idleInhibit = idleInhibit
        self.tag = tag
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case float, center, sizeW, sizeH, sizePointsW, sizePointsH, move, workspace, opacity, pin, keepAspectRatio
        case noBorder, noRounding, rounding, noGaps, noAnim, noInitialFocus, noFocus, idleInhibit, tag
    }

    /// True when the rule sets nothing.
    public var isEmpty: Bool { self == RuleEffects() }

    /// The tags named by ``tag`` (comma-separated), as a set.
    public var tags: Set<String> {
        guard let tag else { return [] }
        return Set(tag.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// `sizeW`/`sizeH` as a size (fractions of the area), when both are set.
    public var sizeFraction: CGSize? {
        guard let sizeW, let sizeH else { return nil }
        return CGSize(width: sizeW, height: sizeH)
    }

    /// `sizePointsW`/`sizePointsH` as a size, when both are set.
    public var sizePoints: CGSize? {
        guard let sizePointsW, let sizePointsH else { return nil }
        return CGSize(width: sizePointsW, height: sizePointsH)
    }

    /// Returns `self` with every field set in `other` overriding ours; tags are unioned.
    public func merging(_ other: RuleEffects) -> RuleEffects {
        var result = self
        if let v = other.float { result.float = v }
        if let v = other.center { result.center = v }
        if let v = other.sizeW { result.sizeW = v }
        if let v = other.sizeH { result.sizeH = v }
        if let v = other.sizePointsW { result.sizePointsW = v }
        if let v = other.sizePointsH { result.sizePointsH = v }
        if let v = other.move { result.move = v }
        if let v = other.workspace { result.workspace = v }
        if let v = other.opacity { result.opacity = v }
        if let v = other.pin { result.pin = v }
        if let v = other.keepAspectRatio { result.keepAspectRatio = v }
        if let v = other.noBorder { result.noBorder = v }
        if let v = other.noRounding { result.noRounding = v }
        if let v = other.rounding { result.rounding = v }
        if let v = other.noGaps { result.noGaps = v }
        if let v = other.noAnim { result.noAnim = v }
        if let v = other.noInitialFocus { result.noInitialFocus = v }
        if let v = other.noFocus { result.noFocus = v }
        if let v = other.idleInhibit { result.idleInhibit = v }
        let union = tags.union(other.tags)
        result.tag = union.isEmpty ? nil : union.sorted().joined(separator: ",")
        return result
    }

    /// Where a floating window matched by these effects should go; see ``resolvedFloatingFrame(effects:in:windowSize:)``.
    public func floatingFrame(in area: CGRect, windowSize: CGSize) -> CGRect? {
        resolvedFloatingFrame(effects: self, in: area, windowSize: windowSize)
    }
}

/// One `[[rule]]` entry: a match, its effects and a stable id (used to override or disable it from
/// the user's `rules.toml`).
public struct WindowRule: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var match: RuleMatch
    public var effects: RuleEffects
    public var enabled: Bool

    public init(id: String, match: RuleMatch = RuleMatch(), effects: RuleEffects = RuleEffects(), enabled: Bool = true) {
        self.id = id
        self.match = match
        self.effects = effects
        self.enabled = enabled
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case id, match, effects, enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        match = try c.decodeIfPresent(RuleMatch.self, forKey: .match) ?? RuleMatch()
        effects = try c.decodeIfPresent(RuleEffects.self, forKey: .effects) ?? RuleEffects()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// The result of running a window through a ``RuleSet``.
public struct RuleResolution: Sendable, Equatable {
    /// Merged effects (later rules override earlier ones); `effects.tag` lists every tag.
    public let effects: RuleEffects
    /// Tags assigned by rules plus the `extraTags` passed in.
    public let tags: Set<String>
    /// Ids of the rules that matched, in evaluation order.
    public let matchedRuleIDs: [String]

    public init(effects: RuleEffects, tags: Set<String>, matchedRuleIDs: [String]) {
        self.effects = effects
        self.tags = tags
        self.matchedRuleIDs = matchedRuleIDs
    }
}

/// An ordered list of window rules. Evaluation is a single pass in order: a rule whose `match.tag` is
/// set only applies when an earlier rule (or the caller's `extraTags`) assigned that tag, exactly like
/// Caelestia's rules.lua, where the tag definitions come after every tagging rule.
public struct RuleSet: Codable, Sendable, Equatable {
    public var rules: [WindowRule]
    /// When a user file sets `replaceDefaults = true` its rules replace the built-in ones instead of
    /// being merged after them.
    public var replaceDefaults: Bool

    public init(rules: [WindowRule], replaceDefaults: Bool = false) {
        self.rules = rules
        self.replaceDefaults = replaceDefaults
    }

    public enum CodingKeys: String, CodingKey, CaseIterable {
        case rules = "rule"
        case replaceDefaults
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decodeIfPresent([WindowRule].self, forKey: .rules) ?? []
        replaceDefaults = try c.decodeIfPresent(Bool.self, forKey: .replaceDefaults) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rules, forKey: .rules)
        if replaceDefaults { try c.encode(true, forKey: .replaceDefaults) }
    }

    /// The rule with the given id, if any.
    public func rule(id: String) -> WindowRule? {
        rules.first { $0.id == id }
    }

    /// Runs every enabled rule in order and merges the effects of those that match.
    public func effects(for window: WindowDescriptor, extraTags: Set<String> = []) -> RuleEffects {
        resolve(for: window, extraTags: extraTags).effects
    }

    /// Like ``effects(for:extraTags:)`` but also reports the final tag set and the matching rule ids.
    public func resolve(for window: WindowDescriptor, extraTags: Set<String> = []) -> RuleResolution {
        var tags = extraTags
        var merged = RuleEffects()
        var matched: [String] = []
        for rule in rules where rule.enabled {
            guard RuleSet.matches(rule, window, tags: tags) else { continue }
            matched.append(rule.id)
            merged = merged.merging(rule.effects)
            tags.formUnion(rule.effects.tags)
        }
        merged.tag = tags.isEmpty ? nil : tags.sorted().joined(separator: ",")
        return RuleResolution(effects: merged, tags: tags, matchedRuleIDs: matched)
    }

    /// Whether `rule` matches `window`, given the tags the window has accumulated so far. The rule's
    /// `enabled` flag is ignored here (callers filter on it).
    public static func matches(_ rule: WindowRule, _ window: WindowDescriptor, tags: Set<String> = []) -> Bool {
        matches(rule.match, window, tags: tags)
    }

    /// Whether `match` matches `window`.
    public static func matches(_ match: RuleMatch, _ window: WindowDescriptor, tags: Set<String> = []) -> Bool {
        if let tag = match.tag, !tags.contains(tag) { return false }
        if let p = match.bundleID, !RulePatterns.glob(p, matches: window.bundleID) { return false }
        if let p = match.appName, !RulePatterns.glob(p, matches: window.appName) { return false }
        if let p = match.role, !RulePatterns.glob(p, matches: window.role) { return false }
        if let p = match.subrole, !RulePatterns.glob(p, matches: window.subrole) { return false }
        if let p = match.category, !RulePatterns.glob(p, matches: window.category) { return false }
        if let p = match.titleRegex, !RulePatterns.regex(p, matches: window.title) { return false }
        return true
    }

    /// `matches(rule, window, tags:)` as an instance method, for call sites that prefer it.
    public func matches(_ rule: WindowRule, _ window: WindowDescriptor, tags: Set<String> = []) -> Bool {
        RuleSet.matches(rule, window, tags: tags)
    }

    /// Returns `self` followed by `other`'s rules. A rule in `other` whose id already exists replaces
    /// the existing rule in place (so a user file can tweak or disable a default by id).
    public func merging(_ other: RuleSet) -> RuleSet {
        var result = rules
        var index: [String: Int] = [:]
        for (i, rule) in result.enumerated() { index[rule.id] = i }
        for rule in other.rules {
            if let i = index[rule.id] {
                result[i] = rule
            } else {
                index[rule.id] = result.count
                result.append(rule)
            }
        }
        return RuleSet(rules: result, replaceDefaults: replaceDefaults)
    }
}

// MARK: - Patterns

/// Compiles and caches the globs and regular expressions used by rules.
enum RulePatterns {
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression?] = [:]
    private static let lock = NSLock()

    /// Converts a glob (`*`, `?`, `|`, leading `!`) into an anchored, case-insensitive regex pattern.
    static func globPattern(_ glob: String) -> (pattern: String, negated: Bool) {
        var body = glob
        var negated = false
        if body.hasPrefix("!") {
            negated = true
            body.removeFirst()
        }
        let alternatives = body.split(separator: "|", omittingEmptySubsequences: false).map { part -> String in
            var escaped = NSRegularExpression.escapedPattern(for: String(part))
            escaped = escaped.replacingOccurrences(of: "\\*", with: ".*")
            escaped = escaped.replacingOccurrences(of: "\\?", with: ".")
            return escaped
        }
        return ("^(?:" + alternatives.joined(separator: "|") + ")$", negated)
    }

    /// Whether `value` matches the glob (see ``RuleMatch`` for the syntax).
    static func glob(_ glob: String, matches value: String) -> Bool {
        let (pattern, negated) = globPattern(glob)
        guard let regex = compiled(pattern, options: [.caseInsensitive]) else { return false }
        let hit = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
        return negated ? !hit : hit
    }

    /// Whether `value` contains a match of the regular expression (search semantics).
    static func regex(_ pattern: String, matches value: String) -> Bool {
        guard let regex = compiled(pattern, options: []) else { return false }
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    /// Compiles a pattern, throwing on syntax errors (used by the loader to validate rule files).
    static func validate(regex pattern: String) throws {
        _ = try NSRegularExpression(pattern: pattern, options: [])
    }

    private static func compiled(_ pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression? {
        let key = "\(options.rawValue):\(pattern)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let regex = try? NSRegularExpression(pattern: pattern, options: options)
        if regex == nil {
            Log.config.error("invalid rule pattern \(pattern, privacy: .public)")
        }
        cache[key] = regex
        return regex
    }
}

// MARK: - Floating placement

/// One axis of a `move` expression: `fraction * areaExtent + windowFactor * windowExtent + points`.
public struct AxisExpression: Equatable, Sendable {
    public var fraction: Double
    public var windowFactor: Double
    public var points: Double

    public init(fraction: Double = 0, windowFactor: Double = 0, points: Double = 0) {
        self.fraction = fraction
        self.windowFactor = windowFactor
        self.points = points
    }

    /// Parses terms like `98%-w`, `50%`, `100`, `100%-h-20`, `+w`. Returns `nil` on malformed input.
    public static func parse(_ text: String, windowSymbol: Character) -> AxisExpression? {
        var result = AxisExpression()
        var sign = 1.0
        var number = ""
        var sawTerm = false
        var sawSignWithoutTerm = false

        func flushNumber(percent: Bool) -> Bool {
            guard !number.isEmpty, let value = Double(number) else { return false }
            if percent { result.fraction += sign * value / 100 } else { result.points += sign * value }
            number = ""
            sawTerm = true
            sawSignWithoutTerm = false
            return true
        }

        for ch in text.lowercased() where !ch.isWhitespace {
            switch ch {
            case "+", "-":
                if !number.isEmpty { guard flushNumber(percent: false) else { return nil } }
                if sawSignWithoutTerm { return nil }
                sign = ch == "-" ? -1 : 1
                sawSignWithoutTerm = true
            case "%":
                guard flushNumber(percent: true) else { return nil }
            case "w", "h":
                guard number.isEmpty, ch == windowSymbol else { return nil }
                result.windowFactor += sign
                sawTerm = true
                sawSignWithoutTerm = false
            case "0"..."9", ".":
                number.append(ch)
            default:
                return nil
            }
        }
        if !number.isEmpty { guard flushNumber(percent: false) else { return nil } }
        return sawTerm && !sawSignWithoutTerm ? result : nil
    }

    /// Evaluates the expression for an area extent and a window extent.
    public func evaluate(areaExtent: Double, windowExtent: Double) -> Double {
        fraction * areaExtent + windowFactor * windowExtent + points
    }
}

/// A parsed `move` effect.
public enum FloatingMove: Equatable, Sendable {
    case center
    /// Bottom-right corner: `(area.w * 0.98 - w, area.h * 0.97 - h)` relative to the area origin
    /// (rules.lua picture-in-picture rule).
    case pip
    case expression(x: AxisExpression, y: AxisExpression)

    /// Parses `"center"`, `"pip"` or `"<xexpr> <yexpr>"`.
    public static func parse(_ text: String) -> FloatingMove? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed == "center" || trimmed == "centre" { return .center }
        if trimmed == "pip" { return .pip }
        let parts = trimmed.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2,
              let x = AxisExpression.parse(String(parts[0]), windowSymbol: "w"),
              let y = AxisExpression.parse(String(parts[1]), windowSymbol: "h")
        else { return nil }
        return .expression(x: x, y: y)
    }
}

/// Computes the frame a floating window should get from merged rule effects.
///
/// - Size: `sizePointsW/H` win over `sizeW/H` (fractions of `area`, floored like Caelestia's
///   `resize_by_screen`); unspecified dimensions keep `windowSize`. Sizes are clamped to the area.
/// - Position: `move` wins over `center`; a size without either is centered (spec 4.5: floating windows
///   are centered when they first appear).
/// - Returns `nil` when the effects say nothing about size or position.
public func resolvedFloatingFrame(effects: RuleEffects, in area: CGRect, windowSize: CGSize) -> CGRect? {
    var size = windowSize
    if let w = effects.sizeW { size.width = w > 0 ? floor(area.width * w) : area.width }
    if let h = effects.sizeH { size.height = h > 0 ? floor(area.height * h) : area.height }
    if let w = effects.sizePointsW { size.width = w }
    if let h = effects.sizePointsH { size.height = h }
    size.width = max(0, min(size.width, area.width))
    size.height = max(0, min(size.height, area.height))

    let hasSize = effects.sizeW != nil || effects.sizeH != nil || effects.sizePointsW != nil || effects.sizePointsH != nil
    let move = effects.move.flatMap(FloatingMove.parse)
    guard move != nil || effects.center == true || hasSize else { return nil }

    let origin: CGPoint
    switch move {
    case .pip:
        origin = CGPoint(x: area.minX + area.width * 0.98 - size.width, y: area.minY + area.height * 0.97 - size.height)
    case .expression(let x, let y):
        origin = CGPoint(
            x: area.minX + x.evaluate(areaExtent: area.width, windowExtent: size.width),
            y: area.minY + y.evaluate(areaExtent: area.height, windowExtent: size.height))
    case .center, .none:
        origin = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
    }
    return CGRect(origin: origin, size: size)
}

// MARK: - Defaults (spec 4.5, ported from hypr/hyprland/rules.lua + execs.lua)

extension RuleSet {
    /// The built-in rules; identical to `Resources/rules.default.toml` (a test asserts it).
    ///
    /// Structure follows rules.lua: global rules, then tagging rules, per-app rules and finally the tag
    /// definitions (which must come after every use of a tag). Linux classes are kept as harmless
    /// examples next to their Mac bundle ids. The two workspace rules (`w[tv1]s[false]`, `f[1]s[false]`
    /// → gaps_out 20) and the "center every floating window" / global opacity rules are handled by the
    /// layout engine and `wm.gapsOutSingle` / `wm.windowOpacity`, not here.
    public static let defaults = RuleSet(rules: [
        // Global
        WindowRule(
            id: "pip",
            match: RuleMatch(titleRegex: "^Picture(-| )in(-| )[Pp]icture$"),
            effects: RuleEffects(float: true, move: "pip", pin: true, keepAspectRatio: true)),

        // Opaque apps (tag opaque)
        WindowRule(
            id: "tag-opaque-linux-apps",
            match: RuleMatch(appName: "foot|equibop|org.quickshell|feh|imv|swappy|krita|gimp*|inkscape|darktable|*resolve*|kdenlive|shotcut|blender|godot*"),
            effects: RuleEffects(tag: "opaque")),
        WindowRule(
            id: "tag-opaque-mac-media",
            match: RuleMatch(bundleID: "io.mpv|mpv|org.videolan.vlc|com.apple.Preview|com.colliderli.iina|com.apple.QuickTimePlayerX|com.apple.Photos|org.gimp.GIMP*|org.inkscape.Inkscape|org.kde.krita|org.blenderfoundation.blender|org.godotengine.godot|com.blackmagic-design.DaVinciResolve*|org.kde.kdenlive|org.shotcut.Shotcut"),
            effects: RuleEffects(tag: "opaque")),
        WindowRule(
            id: "tag-opaque-video",
            match: RuleMatch(tag: "video"),
            effects: RuleEffects(tag: "opaque")),

        // Floating apps (tag float)
        WindowRule(
            id: "tag-float-linux-apps",
            match: RuleMatch(appName: "guifetch|yad|zenity|wev|org.gnome.FileRoller|file-roller|blueman-manager|com.github.GradienceTeam.Gradience|feh|imv|swappy|org.quickshell"),
            effects: RuleEffects(tag: "float")),
        WindowRule(
            id: "tag-float-progress-titles",
            match: RuleMatch(titleRegex: "^File (Operation|Upload)( Progress)?$"),
            effects: RuleEffects(tag: "float")),
        WindowRule(
            id: "tag-float-properties-titles",
            match: RuleMatch(titleRegex: "^.* Properties$"),
            effects: RuleEffects(tag: "float")),
        WindowRule(
            id: "tag-float-rename-titles",
            match: RuleMatch(titleRegex: "^Rename \".*\"$"),
            effects: RuleEffects(tag: "float")),

        // Sized floaters: 60% x 70%
        WindowRule(
            id: "tag-60-70-file-dialog-titles",
            match: RuleMatch(titleRegex: "^(Select|Open)( a)? (File|Folder)(s)?$"),
            effects: RuleEffects(tag: "float_60_70")),
        WindowRule(
            id: "tag-60-70-save-as",
            match: RuleMatch(titleRegex: "^Save As$"),
            effects: RuleEffects(tag: "float_60_70")),
        WindowRule(
            id: "tag-60-70-library",
            match: RuleMatch(titleRegex: "^Library$"),
            effects: RuleEffects(tag: "float_60_70"),
            enabled: false),
        WindowRule(
            id: "tag-60-70-mac-file-dialogs",
            match: RuleMatch(titleRegex: "^(Open( File)?|Save( As)?|Choose Files?|Select (File|Folder)s?)$", subrole: "AXDialog"),
            effects: RuleEffects(tag: "float_60_70")),
        WindowRule(
            id: "tag-60-70-gimp-dialogs",
            match: RuleMatch(appName: "gimp*", titleRegex: "^(Save|Export) Image$"),
            effects: RuleEffects(tag: "float_60_70")),
        WindowRule(
            id: "tag-60-70-blender-file-view",
            match: RuleMatch(appName: "blender", titleRegex: "^Blender File View$"),
            effects: RuleEffects(tag: "float_60_70")),
        WindowRule(
            id: "tag-60-70-audio-control",
            match: RuleMatch(appName: "org.pulseaudio.pavucontrol|com.saivert.pwvucontrol|pavucontrol|pwvucontrol|yad-icon-browser"),
            effects: RuleEffects(tag: "float_60_70")),

        // Sized floaters: 70% x 80%
        WindowRule(
            id: "tag-70-80-settings-apps",
            match: RuleMatch(appName: "org.gnome.Settings|qt5ct|qt6ct|nm-connection-editor"),
            effects: RuleEffects(tag: "float_70_80")),
        WindowRule(
            id: "tag-70-80-mac-settings",
            match: RuleMatch(bundleID: "com.apple.systempreferences|com.caelestia.mac.settings"),
            effects: RuleEffects(tag: "float_70_80")),
        WindowRule(
            id: "tag-70-80-settings-titles",
            match: RuleMatch(titleRegex: "^(Settings|Preferences)$"),
            effects: RuleEffects(tag: "float_70_80")),

        // Sized floaters: 50% x 60%
        WindowRule(
            id: "tag-50-60-utility-apps",
            match: RuleMatch(appName: "nwg-look|system-config-printer|blueman*|gnome-calculator"),
            effects: RuleEffects(tag: "float_50_60")),
        WindowRule(
            id: "tag-50-60-mac-utilities",
            match: RuleMatch(bundleID: "com.apple.ActivityMonitor"),
            effects: RuleEffects(tag: "float_50_60")),

        // Games (tag game)
        WindowRule(
            id: "tag-game-category",
            match: RuleMatch(category: "public.app-category.games|public.app-category.*-games"),
            effects: RuleEffects(tag: "game")),
        WindowRule(
            id: "tag-game-linux-classes",
            match: RuleMatch(appName: "steam_app_*|gamescope"),
            effects: RuleEffects(tag: "game")),

        // Popups (tag popup; rules.lua xwl_popup)
        WindowRule(
            id: "tag-popup-xwayland-titles",
            match: RuleMatch(titleRegex: "^win[0-9]+$"),
            effects: RuleEffects(tag: "popup")),
        WindowRule(
            id: "tag-popup-nonstandard",
            match: RuleMatch(subrole: "!AXStandardWindow"),
            effects: RuleEffects(tag: "popup")),
        WindowRule(
            id: "tag-popup-steam-untitled",
            match: RuleMatch(appName: "steam", titleRegex: "^$"),
            effects: RuleEffects(tag: "popup")),

        // Special workspaces
        WindowRule(
            id: "tag-sysmon-btop",
            match: RuleMatch(bundleID: "net.kovidgoyal.kitty*", titleRegex: "^btop"),
            effects: RuleEffects(tag: "sysmon")),
        WindowRule(
            id: "tag-sysmon-btop-app",
            match: RuleMatch(appName: "btop"),
            effects: RuleEffects(tag: "sysmon")),
        WindowRule(
            id: "tag-music-apps",
            match: RuleMatch(bundleID: "com.spotify.client|com.apple.Music|com.github.th-ch.youtube-music|*feishin*|*supersonic*|*plexamp*|*cider*|*simpmusic*"),
            effects: RuleEffects(tag: "music")),
        WindowRule(
            id: "tag-music-app-names",
            match: RuleMatch(appName: "Spotify|Spotify Free|feishin|Supersonic|Plexamp|Cider|YouTube Music|com.github.th-ch.youtube-music|com-maxrave-simpmusic-MainKt"),
            effects: RuleEffects(tag: "music")),
        WindowRule(
            id: "tag-communication-apps",
            match: RuleMatch(bundleID: "com.hnc.Discord|com.apple.MobileSMS|net.whatsapp.WhatsApp|ru.keepcoder.Telegram|org.telegram.desktop|*vesktop*|*equibop*"),
            effects: RuleEffects(tag: "communication")),
        WindowRule(
            id: "tag-communication-app-names",
            match: RuleMatch(appName: "discord|equibop|vesktop|whatsapp|Telegram|Messages"),
            effects: RuleEffects(tag: "communication")),
        WindowRule(
            id: "tag-todo-apps",
            match: RuleMatch(bundleID: "com.todoist.mac.Todoist|com.apple.reminders|com.culturedcode.ThingsMac"),
            effects: RuleEffects(tag: "todo")),
        WindowRule(
            id: "tag-todo-app-names",
            match: RuleMatch(appName: "todoist|Things|Reminders"),
            effects: RuleEffects(tag: "todo")),

        // Per-app rules
        WindowRule(
            id: "steam-friends-list",
            match: RuleMatch(appName: "steam", titleRegex: "^Friends List$"),
            effects: RuleEffects(tag: "float")),
        WindowRule(
            id: "ueberzugpp",
            match: RuleMatch(appName: "ueberzugpp_*"),
            effects: RuleEffects(float: true, noInitialFocus: true)),
        WindowRule(
            id: "atlauncher-console",
            match: RuleMatch(appName: "com-atlauncher-App|ATLauncher", titleRegex: "^ATLauncher Console$"),
            effects: RuleEffects(tag: "float")),
        WindowRule(
            id: "pandora-launcher-console",
            match: RuleMatch(appName: "PandoraLauncher", titleRegex: "^Minecraft Game Output$"),
            effects: RuleEffects(tag: "float")),
        WindowRule(
            id: "bitwarden-app",
            match: RuleMatch(bundleID: "com.bitwarden.desktop"),
            effects: RuleEffects(float: true, center: true, sizeW: 0.2, sizeH: 0.54)),
        WindowRule(
            id: "bitwarden-firefox-extension",
            match: RuleMatch(titleRegex: "^Extension: \\(Bitwarden Password Manager\\) - Bitwarden"),
            effects: RuleEffects(float: true, center: true, sizeW: 0.2, sizeH: 0.54)),
        WindowRule(
            id: "bitwarden-chromium-extension",
            match: RuleMatch(bundleID: "*nngceckbapebfimnlniiiahkandclblb*"),
            effects: RuleEffects(float: true, center: true, sizeW: 0.2, sizeH: 0.54)),

        // Tag definitions (after every use of a tag, as in rules.lua)
        WindowRule(id: "tag-opaque", match: RuleMatch(tag: "opaque"), effects: RuleEffects(opacity: 1)),
        WindowRule(id: "tag-float", match: RuleMatch(tag: "float"), effects: RuleEffects(float: true)),
        WindowRule(
            id: "tag-float-50-60", match: RuleMatch(tag: "float_50_60"),
            effects: RuleEffects(float: true, center: true, sizeW: 0.5, sizeH: 0.6)),
        WindowRule(
            id: "tag-float-60-70", match: RuleMatch(tag: "float_60_70"),
            effects: RuleEffects(float: true, center: true, sizeW: 0.6, sizeH: 0.7)),
        WindowRule(
            id: "tag-float-70-80", match: RuleMatch(tag: "float_70_80"),
            effects: RuleEffects(float: true, center: true, sizeW: 0.7, sizeH: 0.8)),
        WindowRule(
            id: "tag-game", match: RuleMatch(tag: "game"),
            effects: RuleEffects(opacity: 1, noAnim: true, idleInhibit: true)),
        WindowRule(
            id: "tag-popup", match: RuleMatch(tag: "popup"),
            effects: RuleEffects(opacity: 1, noBorder: true, rounding: 10, noAnim: true, noFocus: true)),
        WindowRule(id: "tag-sysmon", match: RuleMatch(tag: "sysmon"), effects: RuleEffects(workspace: "special:sysmon")),
        WindowRule(id: "tag-music", match: RuleMatch(tag: "music"), effects: RuleEffects(workspace: "special:music")),
        WindowRule(
            id: "tag-communication", match: RuleMatch(tag: "communication"),
            effects: RuleEffects(workspace: "special:communication")),
        WindowRule(id: "tag-todo", match: RuleMatch(tag: "todo"), effects: RuleEffects(workspace: "special:todo")),
    ])
}

// MARK: - Loader

/// Errors raised while reading `rules.toml`.
public enum RulesError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    case syntax(String)
    case typeMismatch(path: String, expected: String, found: String)
    case missingKey(path: String)
    case duplicateID(String)
    case invalidRegex(ruleID: String, pattern: String, message: String)
    case invalid(ruleID: String, path: String, message: String)
    case resourceMissing(String)
    case io(path: String, message: String)

    public var description: String {
        switch self {
        case .syntax(let message): return "rules syntax error: \(message)"
        case .typeMismatch(let path, let expected, let found): return "\(path): expected \(expected), found \(found)"
        case .missingKey(let path): return "\(path): required key is missing"
        case .duplicateID(let id): return "rule id \"\(id)\" is used more than once"
        case .invalidRegex(let id, let pattern, let message): return "rule \"\(id)\": invalid regex \"\(pattern)\": \(message)"
        case .invalid(let id, let path, let message): return "rule \"\(id)\": \(path): \(message)"
        case .resourceMissing(let name): return "bundled resource \"\(name)\" is missing"
        case .io(let path, let message): return "\(path): \(message)"
        }
    }

    public var errorDescription: String? { description }
}

/// Reads and writes `rules.toml`:
///
/// ```toml
/// replaceDefaults = false   # optional: true = ignore the built-in rules entirely
///
/// [[rule]]
/// id = "bitwarden-app"
/// enabled = true            # optional
/// [rule.match]
/// bundleID = "com.bitwarden.desktop"
/// [rule.effects]
/// float = true
/// center = true
/// sizeW = 0.2
/// sizeH = 0.54
/// ```
///
/// A user file is merged after the defaults: rules with a new id are appended, rules whose id matches
/// a default replace it (so `enabled = false` disables a default).
public enum RulesLoader {
    /// File name of the default rule set shipped in the module resources.
    public static let defaultResourceName = "rules.default.toml"

    /// Parses a rule file (warnings dropped; see ``parseDetailed(toml:)``).
    public static func parse(toml: String) throws -> RuleSet {
        try parseDetailed(toml: toml).ruleSet
    }

    /// Parses a rule file, validating ids, regexes, `move` expressions and ranges; unknown keys are
    /// returned as warnings.
    public static func parseDetailed(toml: String) throws -> (ruleSet: RuleSet, warnings: [String]) {
        let root: TOMLTable
        do {
            root = try TOMLTable(string: toml)
        } catch let error as TOMLParseError {
            throw RulesError.syntax(error.debugDescription)
        } catch {
            throw RulesError.syntax(String(describing: error))
        }
        var warnings: [String] = []
        for key in root.keys where key != "rule" && key != RuleSet.CodingKeys.replaceDefaults.rawValue {
            warnings.append("unknown key \"\(key)\" (ignored)")
        }
        let replaceDefaults = try TOMLReader(table: root, path: "").bool("replaceDefaults") ?? false
        var rules: [WindowRule] = []
        var ids: Set<String> = []
        if let entries = root["rule"] {
            guard let array = entries.array else {
                throw RulesError.typeMismatch(path: "rule", expected: "array of tables ([[rule]])", found: entries.type.description)
            }
            for (index, element) in array.enumerated() {
                let path = "rule[\(index)]"
                guard let table = element.table else {
                    throw RulesError.typeMismatch(path: path, expected: "table", found: element.type.description)
                }
                let rule = try readRule(table, path: path, warnings: &warnings)
                guard ids.insert(rule.id).inserted else { throw RulesError.duplicateID(rule.id) }
                try validate(rule)
                rules.append(rule)
            }
        }
        return (RuleSet(rules: rules, replaceDefaults: replaceDefaults), warnings)
    }

    /// Serializes a rule set as `[[rule]]` blocks (only the fields that are set).
    public static func serialize(_ ruleSet: RuleSet) -> String {
        var out = "# Caelestia for Mac window rules (written by RulesLoader.serialize)\n"
        if ruleSet.replaceDefaults { out += "\nreplaceDefaults = true\n" }
        for rule in ruleSet.rules {
            out += "\n[[rule]]\n"
            out += "id = \(tomlString(rule.id))\n"
            if !rule.enabled { out += "enabled = false\n" }
            let match = matchFields(rule.match)
            if !match.isEmpty {
                out += "[rule.match]\n"
                for (key, value) in match { out += "\(key) = \(value)\n" }
            }
            let effects = effectFields(rule.effects)
            if !effects.isEmpty {
                out += "[rule.effects]\n"
                for (key, value) in effects { out += "\(key) = \(value)\n" }
            }
        }
        return out
    }

    /// Loads and parses a rule file.
    public static func load(from url: URL) throws -> RuleSet {
        try loadDetailed(from: url).ruleSet
    }

    /// Loads and parses a rule file, returning warnings as well.
    public static func loadDetailed(from url: URL) throws -> (ruleSet: RuleSet, warnings: [String]) {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw RulesError.io(path: url.path, message: error.localizedDescription)
        }
        return try parseDetailed(toml: text)
    }

    /// The built-in rules merged with `~/.config/caelestia-mac/rules.toml` when it exists (or replaced
    /// by it when it sets `replaceDefaults = true`). A broken user file yields the defaults plus a warning.
    public static func loadUserOrDefault(url: URL = Paths.rulesFile) -> (RuleSet, [String]) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (RuleSet.defaults, []) }
        do {
            let (user, warnings) = try loadDetailed(from: url)
            if user.replaceDefaults { return (user, warnings) }
            return (RuleSet.defaults.merging(user), warnings)
        } catch {
            let message = "\(url.path): \(error); using built-in rules"
            Log.config.error("\(message, privacy: .public)")
            return (RuleSet.defaults, [message])
        }
    }

    /// Saves a rule set atomically, creating parent directories.
    public static func save(_ ruleSet: RuleSet, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(serialize(ruleSet).utf8).write(to: url, options: .atomic)
        } catch {
            throw RulesError.io(path: url.path, message: error.localizedDescription)
        }
    }

    /// Location of the bundled `rules.default.toml`, if present.
    public static func defaultResourceURL() -> URL? {
        CoreResources.url(forResource: "rules.default", withExtension: "toml")
    }

    /// Parses the bundled `rules.default.toml`. Tests assert it equals `RuleSet.defaults`.
    public static func loadDefaultResource() throws -> RuleSet {
        let text: String
        do {
            text = try CoreResources.string(forResource: "rules.default", withExtension: "toml")
        } catch {
            throw RulesError.resourceMissing(defaultResourceName)
        }
        return try parse(toml: text)
    }

    // MARK: Reading

    private static func readRule(_ table: TOMLTable, path: String, warnings: inout [String]) throws -> WindowRule {
        let known = Set(WindowRule.CodingKeys.allCases.map(\.rawValue))
        for key in table.keys where !known.contains(key) {
            warnings.append("unknown key \"\(path).\(key)\" (ignored)")
        }
        let reader = TOMLReader(table: table, path: path)
        guard let id = try reader.string("id"), !id.isEmpty else { throw RulesError.missingKey(path: "\(path).id") }
        let enabled = try reader.bool("enabled") ?? true

        var match = RuleMatch()
        if let matchTable = try reader.subtable("match") {
            let known = Set(RuleMatch.CodingKeys.allCases.map(\.rawValue))
            for key in matchTable.table.keys where !known.contains(key) {
                warnings.append("unknown key \"\(path).match.\(key)\" (ignored)")
            }
            match.bundleID = try matchTable.string("bundleID")
            match.appName = try matchTable.string("appName")
            match.titleRegex = try matchTable.string("titleRegex")
            match.role = try matchTable.string("role")
            match.subrole = try matchTable.string("subrole")
            match.category = try matchTable.string("category")
            match.tag = try matchTable.string("tag")
        }

        var effects = RuleEffects()
        if let e = try reader.subtable("effects") {
            let known = Set(RuleEffects.CodingKeys.allCases.map(\.rawValue))
            for key in e.table.keys where !known.contains(key) {
                warnings.append("unknown key \"\(path).effects.\(key)\" (ignored)")
            }
            effects.float = try e.bool("float")
            effects.center = try e.bool("center")
            effects.sizeW = try e.double("sizeW")
            effects.sizeH = try e.double("sizeH")
            effects.sizePointsW = try e.double("sizePointsW")
            effects.sizePointsH = try e.double("sizePointsH")
            effects.move = try e.string("move")
            effects.workspace = try e.string("workspace")
            effects.opacity = try e.double("opacity")
            effects.pin = try e.bool("pin")
            effects.keepAspectRatio = try e.bool("keepAspectRatio")
            effects.noBorder = try e.bool("noBorder")
            effects.noRounding = try e.bool("noRounding")
            effects.rounding = try e.double("rounding")
            effects.noGaps = try e.bool("noGaps")
            effects.noAnim = try e.bool("noAnim")
            effects.noInitialFocus = try e.bool("noInitialFocus")
            effects.noFocus = try e.bool("noFocus")
            effects.idleInhibit = try e.bool("idleInhibit")
            effects.tag = try e.string("tag")
        }
        return WindowRule(id: id, match: match, effects: effects, enabled: enabled)
    }

    /// Checks regexes, `move` syntax, ranges and the workspace format.
    public static func validate(_ rule: WindowRule) throws {
        if let pattern = rule.match.titleRegex {
            do {
                try RulePatterns.validate(regex: pattern)
            } catch {
                throw RulesError.invalidRegex(ruleID: rule.id, pattern: pattern, message: error.localizedDescription)
            }
        }
        let e = rule.effects
        if let move = e.move, FloatingMove.parse(move) == nil {
            throw RulesError.invalid(ruleID: rule.id, path: "effects.move", message: "expected \"center\", \"pip\" or \"<x> <y>\" (got \"\(move)\")")
        }
        for (key, value) in [("sizeW", e.sizeW), ("sizeH", e.sizeH), ("opacity", e.opacity)] {
            if let value, !(0...1).contains(value) {
                throw RulesError.invalid(ruleID: rule.id, path: "effects.\(key)", message: "must be between 0 and 1 (got \(value))")
            }
        }
        for (key, value) in [("sizePointsW", e.sizePointsW), ("sizePointsH", e.sizePointsH), ("rounding", e.rounding)] {
            if let value, value < 0 {
                throw RulesError.invalid(ruleID: rule.id, path: "effects.\(key)", message: "must be >= 0 (got \(value))")
            }
        }
        if let workspace = e.workspace {
            let ok = workspace == "special" || (workspace.hasPrefix("special:") && workspace.count > 8) || (Int(workspace).map { $0 >= 1 } ?? false)
            if !ok {
                throw RulesError.invalid(ruleID: rule.id, path: "effects.workspace", message: "expected \"special:<name>\", \"special\" or a workspace number (got \"\(workspace)\")")
            }
        }
        if let tag = e.tag, e.tags.isEmpty {
            throw RulesError.invalid(ruleID: rule.id, path: "effects.tag", message: "tag must not be empty (got \"\(tag)\")")
        }
    }

    // MARK: Writing

    private static func matchFields(_ m: RuleMatch) -> [(String, String)] {
        var out: [(String, String)] = []
        if let v = m.bundleID { out.append(("bundleID", tomlString(v))) }
        if let v = m.appName { out.append(("appName", tomlString(v))) }
        if let v = m.titleRegex { out.append(("titleRegex", tomlString(v))) }
        if let v = m.role { out.append(("role", tomlString(v))) }
        if let v = m.subrole { out.append(("subrole", tomlString(v))) }
        if let v = m.category { out.append(("category", tomlString(v))) }
        if let v = m.tag { out.append(("tag", tomlString(v))) }
        return out
    }

    private static func effectFields(_ e: RuleEffects) -> [(String, String)] {
        var out: [(String, String)] = []
        if let v = e.float { out.append(("float", "\(v)")) }
        if let v = e.center { out.append(("center", "\(v)")) }
        if let v = e.sizeW { out.append(("sizeW", tomlDouble(v))) }
        if let v = e.sizeH { out.append(("sizeH", tomlDouble(v))) }
        if let v = e.sizePointsW { out.append(("sizePointsW", tomlDouble(v))) }
        if let v = e.sizePointsH { out.append(("sizePointsH", tomlDouble(v))) }
        if let v = e.move { out.append(("move", tomlString(v))) }
        if let v = e.workspace { out.append(("workspace", tomlString(v))) }
        if let v = e.opacity { out.append(("opacity", tomlDouble(v))) }
        if let v = e.pin { out.append(("pin", "\(v)")) }
        if let v = e.keepAspectRatio { out.append(("keepAspectRatio", "\(v)")) }
        if let v = e.noBorder { out.append(("noBorder", "\(v)")) }
        if let v = e.noRounding { out.append(("noRounding", "\(v)")) }
        if let v = e.rounding { out.append(("rounding", tomlDouble(v))) }
        if let v = e.noGaps { out.append(("noGaps", "\(v)")) }
        if let v = e.noAnim { out.append(("noAnim", "\(v)")) }
        if let v = e.noInitialFocus { out.append(("noInitialFocus", "\(v)")) }
        if let v = e.noFocus { out.append(("noFocus", "\(v)")) }
        if let v = e.idleInhibit { out.append(("idleInhibit", "\(v)")) }
        if let v = e.tag { out.append(("tag", tomlString(v))) }
        return out
    }

    static func tomlDouble(_ v: Double) -> String {
        if v == v.rounded(), abs(v) < 1e15 { return String(format: "%.1f", v) }
        return "\(v)"
    }

    /// Prefers a literal string (`'...'`) for patterns with backslashes; otherwise a basic string with escapes.
    static func tomlString(_ s: String) -> String {
        let hasControl = s.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
        if s.contains("\\"), !s.contains("'"), !hasControl { return "'\(s)'" }
        return SchemeLoader.tomlString(s)
    }
}

/// Typed, path-aware access to a `TOMLTable` for hand-written readers (accepts integers for floats).
struct TOMLReader {
    let table: TOMLTable
    let path: String

    private func located(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    func string(_ key: String) throws -> String? {
        guard let value = table[key] else { return nil }
        guard let s = value.string else {
            throw RulesError.typeMismatch(path: located(key), expected: "string", found: value.type.description)
        }
        return s
    }

    func bool(_ key: String) throws -> Bool? {
        guard let value = table[key] else { return nil }
        guard let b = value.bool else {
            throw RulesError.typeMismatch(path: located(key), expected: "boolean", found: value.type.description)
        }
        return b
    }

    func double(_ key: String) throws -> Double? {
        guard let value = table[key] else { return nil }
        if let d = value.double { return d }
        if let i = value.int { return Double(i) }
        throw RulesError.typeMismatch(path: located(key), expected: "number", found: value.type.description)
    }

    func subtable(_ key: String) throws -> TOMLReader? {
        guard let value = table[key] else { return nil }
        guard let t = value.table else {
            throw RulesError.typeMismatch(path: located(key), expected: "table", found: value.type.description)
        }
        return TOMLReader(table: t, path: located(key))
    }
}
