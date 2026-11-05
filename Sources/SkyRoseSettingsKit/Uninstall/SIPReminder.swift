import AppKit
import CaelestiaCore
import Combine
import SwiftUI

/// The countdown behind the SIP reminder: nothing can dismiss it before `minimumSeconds` have
/// passed since it appeared (no close button, Esc and ⌘W do nothing, the button stays disabled).
/// The clock is injected so tests do not wait.
@MainActor
public final class SIPReminderModel: ObservableObject {
    public static let minimumSeconds: TimeInterval = 5

    @Published public private(set) var remaining: Int
    @Published public private(set) var canDismiss = false
    public let shownAt: TimeInterval
    let now: () -> TimeInterval
    private var timer: Timer?
    public var onDismiss: () -> Void = {}

    public init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
        shownAt = now()
        remaining = Int(Self.minimumSeconds)
    }

    /// Re-reads the clock (the timer calls it 10× a second).
    public func tick() {
        let elapsed = now() - shownAt
        let left = max(0, Self.minimumSeconds - elapsed)
        let r = Int(left.rounded(.up))
        if r != remaining { remaining = r }
        if left <= 0, !canDismiss { canDismiss = true }
    }

    public func start() {
        tick()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The only way out. Ignored (returns false) until the minimum time has passed.
    @discardableResult
    public func dismiss() -> Bool {
        tick()
        guard canDismiss else { return false }
        timer?.invalidate()
        timer = nil
        onDismiss()
        return true
    }
}

/// "Turn System Integrity Protection back on": shown by the uninstaller when the restore manifest
/// says SIP-off mode was used (or the manifest cannot be read). Steps in plain words, at least
/// 5 s on screen before it can be closed.
public struct SIPReminderView: View {
    @ObservedObject var model: SIPReminderModel
    @Environment(\.look) var look

    public init(model: SIPReminderModel) {
        self.model = model
    }

    static let steps: [(String, String)] = [
        ("power", "Shut down your Mac."),
        ("power.circle", "Press and hold the power button until “Loading startup options” appears."),
        ("gearshape", "Click Options, then Continue. Sign in if asked."),
        ("terminal", "In the menu bar choose Utilities › Terminal."),
        ("keyboard", "Type  csrutil enable  and press Return, then type  y  if asked."),
        ("arrow.clockwise", "Choose Apple menu › Restart. SIP is on again."),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield").font(.system(size: 26, weight: .semibold)).foregroundStyle(look[.onPrimaryContainer])
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(look[.primaryContainer]))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Turn System Integrity Protection back on").font(look.font(20, .semibold)).foregroundStyle(look[.onSurface])
                    Text("You used SkyRose's SIP-off mode. Uninstalling SkyRose does not turn SIP back on: only you can, from Recovery. It takes about five minutes.")
                        .font(look.font(13)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)").font(look.font(12, .bold)).foregroundStyle(look[.onPrimary])
                            .frame(width: 22, height: 22).background(Circle().fill(look[.primary]))
                        Image(systemName: step.0).font(.system(size: 13)).foregroundStyle(look[.primary]).frame(width: 18)
                        Text(step.1).font(look.font(13.5)).foregroundStyle(look[.onSurface]).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: SettingsLook.cardRadius, style: .continuous).fill(look[.surfaceContainer]))
            HStack {
                Text("Apple's guide: support.apple.com/102149").font(look.font(12)).foregroundStyle(look[.onSurfaceVariant])
                Spacer()
                Button { model.dismiss() } label: {
                    Text(model.canDismiss ? "I understand" : "Please read (\(model.remaining))")
                        .font(look.font(13, .semibold))
                        .foregroundStyle(model.canDismiss ? look[.onPrimary] : look[.onSurfaceVariant])
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Capsule().fill(model.canDismiss ? look[.primary] : look[.surfaceContainerHighest]))
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .disabled(!model.canDismiss)
                .accessibilityIdentifier("sip.dismiss")
                .animation(look.motion.quick, value: model.remaining)
                .animation(look.motion.pop, value: model.canDismiss)
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(PanelBackground())
    }
}

/// A panel that refuses to close (Esc, ⌘W, the close button) until its model allows it.
final class GuardedPanel: NSPanel {
    var canClose: () -> Bool = { true }
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { if canClose() { close() } }
    override func performClose(_ sender: Any?) { if canClose() { super.performClose(sender) } }
    override func close() {
        guard canClose() else { NSSound.beep(); return }
        super.close()
    }
}

/// Shows the reminder as its own floating window, centred on the main screen.
@MainActor
public enum SIPReminderPresenter {
    private static var window: GuardedPanel?

    @discardableResult
    public static func show(look: SettingsLook, onDismiss: @escaping () -> Void = {}) -> SIPReminderModel {
        let model = SIPReminderModel()
        let panel = GuardedPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.isMovableByWindowBackground = true
        panel.canClose = { [weak model] in model?.canDismiss ?? true }
        panel.title = "Turn System Integrity Protection back on"
        let host = NSHostingView(rootView: SIPReminderView(model: model).environment(\.look, look))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.center()
        model.onDismiss = { [weak panel] in
            panel?.close()
            onDismiss()
        }
        window = panel
        panel.makeKeyAndOrderFront(nil)
        model.start()
        return model
    }
}
