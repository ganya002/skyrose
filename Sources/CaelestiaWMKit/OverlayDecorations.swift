import AppKit
import CaelestiaCore
import CaelestiaLayout
import CaelestiaOverlay
import Foundation

/// The daemon's decorations: border overlays + group bars (`OverlayController`), the workspace
/// slide (`WorkspaceSlide`) and the debug overlay, configured from `config.toml` (animation
/// preset, Reduce Motion, game mode, border size/rounding) and the "current" color scheme.
@MainActor
public final class OverlayDecorations: WindowDecorations {
    public let borders: OverlayController
    public let slide: WorkspaceSlide
    public let debugOverlay = DebugOverlay()
    private var scheme: Scheme
    private var reduceMotionObserver: NSObjectProtocol?
    private var screensObserver: NSObjectProtocol?
    private var config: Config

    public init(config: Config, scheme: Scheme = SchemeLoader.builtIn(named: "caelestia-dynamic-dark") ?? OverlayStyle.gabbyScheme) {
        self.config = config
        self.scheme = scheme
        let style = OverlayStyle(scheme: scheme, wm: config.wm, fonts: [config.appearance.fontMono] + config.appearance.fontMonoFallbacks)
        let table = Self.table(for: config)
        borders = OverlayController(style: style, table: table)
        slide = WorkspaceSlide(style: style, table: table, gap: config.wm.gapsWorkspaces)
        borders.isEnabled = Self.bordersEnabled(config)
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply(config: self?.config ?? Config()) }
        }
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.slide.displaysChanged() }
        }
        slide.prewarm()
    }

    public func apply(config: Config) {
        self.config = config
        let style = OverlayStyle(scheme: scheme, wm: config.wm, fonts: [config.appearance.fontMono] + config.appearance.fontMonoFallbacks)
        let table = Self.table(for: config)
        borders.table = table
        borders.style = style
        borders.isEnabled = Self.bordersEnabled(config)
        slide.table = table
        slide.style = style
        slide.gap = config.wm.gapsWorkspaces
    }

    static func table(for config: Config) -> AnimationTable {
        if config.wm.gameMode { return .off }
        return AnimationTable.from(config: config.animations, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    static func bordersEnabled(_ config: Config) -> Bool { !config.wm.gameMode && config.wm.borderSize > 0 }

    // MARK: WindowDecorations

    public func apply(_ scene: OverlayScene) { borders.apply(scene) }

    public func externalMove(_ id: WindowID) { borders.noteExternalMove(id) }

    public func workspaceWillChange(_ transitions: [WorkspaceTransition], resume: @escaping () -> Void) -> Bool {
        slide.begin(transitions, resume: resume)
        return true
    }

    public func workspaceDidChange() { slide.laidOut() }

    public func removeAll() {
        slide.finish()
        borders.removeAll()
        debugOverlay.hide()
    }

    public func debug(_ snapshot: DebugSnapshot?) {
        guard let snapshot else { return debugOverlay.hide() }
        var s = snapshot
        s.lines.append("surfaces \(borders.surfaces.count)  ticks \(borders.ticks)")
        s.lines.append("slides \(slide.played)  skipped \(slide.skipped)  fade \(slide.fallbacks)  aborted \(slide.aborted)")
        debugOverlay.show(s)
    }

    public func overlayEntries() -> [OverlayQueryEntry] {
        let numbers = borders.windowNumbers
        let samples = borders.engine.samples(at: CACurrentMediaTime())
        return borders.engine.borders.keys.sorted().compactMap { id in
            guard let b = borders.engine.borders[id], let sample = samples[id] else { return nil }
            return OverlayQueryEntry(
                target: id, overlay: numbers[id] ?? 0, frame: sample.frame, alpha: sample.alpha, active: b.target.isActive,
                vanishing: b.phase == .vanishing, group: b.target.group != nil
            )
        }
    }
}

extension OverlayStyle {
    /// The built-in "current" scheme, or a minimal copy of its border colors.
    public static var gabbyScheme: Scheme {
        SchemeLoader.builtIn(named: "caelestia-dynamic-dark") ?? Scheme(name: "fallback", colors: [
            "primary": RGBA(r: 0xBA, g: 0xC5, b: 0xEE), "onSurfaceVariant": RGBA(r: 0xA9, g: 0xAA, b: 0xB5),
            "outline": RGBA(r: 0x73, g: 0x75, b: 0x7F), "secondary": RGBA(r: 0xC1, g: 0xC6, b: 0xDD),
            "onPrimary": RGBA(r: 0x33, g: 0x3F, b: 0x61), "surfaceContainer": RGBA(r: 0x18, g: 0x19, b: 0x20),
        ])
    }
}
