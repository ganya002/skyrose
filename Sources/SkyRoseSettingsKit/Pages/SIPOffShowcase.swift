import AppKit
import CaelestiaCore
import SwiftUI

/// "What changes with SIP off?": live side-by-side demos (SIP on today vs SIP off) and an honest
/// risks section. Reading it to the end ("I understand") unlocks the SIP-off switch.
enum SIPOffShowcase {
    static let seenKey = "sipOffShowcaseSeen"
    private static var window: NSWindow?

    @MainActor
    static func present(look: SettingsLook) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "What changes with SIP off?"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(look[.surface])
        w.contentView = NSHostingView(rootView: SIPOffShowcaseView(onDone: { [weak w] in w?.close() }).environment(\.look, look))
        w.center()
        window = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { window = nil }
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SIPOffShowcaseView: View {
    @Environment(\.look) var look
    @AppStorage(SIPOffShowcase.seenKey) private var seen = false
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What changes with SIP off?").font(look.font(30, .semibold)).foregroundStyle(look[.onSurface])
                    Text("Left: SkyRose today, with System Integrity Protection on. Right: the same with SIP partly off and SkyRose's helper loaded into the Dock. The demos run live.")
                        .font(look.font(13.5)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 18)
                demo("Window animations", "Today a window's open and move animations show a still picture of it (a snapshot), then swap to the real window. With SIP off the real window itself scales and springs, and its content keeps updating.") { off in
                    PopDemo(live: off)
                }
                demo("Window opacity and shadows", "macOS does not let one app change another app's windows. With SIP off, every window can be 95 % opaque like your Arch setup (fullscreen stays solid), and shadows can be turned off.") { off in
                    OpacityDemo(translucent: off)
                }
                demo("Instant workspaces", "Today a workspace switch slides. With SIP off it can switch instantly: windows are hidden while SkyRose moves them, so you never see them travel.") { off in
                    WorkspaceDemo(instant: off)
                }
                demo("Pinned windows on top", "Today a pinned window follows you to every workspace but another window can cover it. With SIP off it really stays on top.") { off in
                    PinDemo(onTop: off)
                }
                risks
                HStack(spacing: 12) {
                    Spacer()
                    PillButton(title: "Not now", kind: .outline, action: onDone)
                    PillButton(title: seen ? "Close" : "I understand the risks", icon: seen ? nil : "checkmark.shield", kind: .filled) {
                        seen = true
                        onDone()
                    }
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 34)
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(look[.surface])
    }

    private func demo<V: View>(_ title: String, _ text: String, @ViewBuilder _ content: @escaping (Bool) -> V) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(look.font(18, .semibold)).foregroundStyle(look[.onSurface])
            Text(text).font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                stage("SIP on · today", accent: false) { content(false) }
                stage("SIP off", accent: true) { content(true) }
            }
        }
    }

    private func stage<V: View>(_ label: String, accent: Bool, @ViewBuilder _ content: () -> V) -> some View {
        ZStack(alignment: .topLeading) {
            DemoWallpaper()
            content().frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(label).font(look.font(11, .semibold))
                .foregroundStyle(accent ? look[.onPrimary] : look[.onSurface])
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(accent ? look[.primary] : look[.surfaceContainerHighest].opacity(0.9)))
                .padding(10)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(accent ? look[.primary].opacity(0.6) : look[.outlineVariant], lineWidth: 1.5))
    }

    private var risks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The honest part: risks").font(look.font(18, .semibold)).foregroundStyle(look[.onSurface])
            risk("lock.open", "Security", "SIP stops any program, even one running as you or as administrator, from changing macOS itself or injecting code into Apple's apps. With Filesystem and Debugging protections off, malware that gets onto your Mac can do both. SkyRose's helper only listens to your own user, but SIP protects against everything else too.")
            risk("building.columns", "School and managed Macs", "If this Mac belongs to your school or is managed (MDM), turning SIP off may break their rules, and their tools can detect it. Ask IT first. A school Mac might not even let you into Recovery.")
            risk("arrow.triangle.2.circlepath", "macOS updates", "Updates can change the private parts of the Dock and SkyLight the helper uses, or clear the boot argument. SkyRose then quietly falls back to its normal behaviour until a new build fixes it. Nothing breaks, but the extras stop.")
            risk("exclamationmark.triangle", "Stability", "A bug in the helper can crash the Dock (it restarts by itself in a second; the helper is gone until you load it again). `skyrose wm panic` undoes every window change at once.")
            risk("arrow.uturn.backward", "Going back", "Recovery (hold the power button) › Options › Utilities › Terminal: csrutil enable. Then in Terminal: sudo nvram -d boot-args. Restart. SkyRose needs nothing else, and uninstalling SkyRose reminds you if SIP is still partly off.")
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(look[.errorContainer].opacity(0.35)))
    }

    private func risk(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(look[.error]).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(look.font(14, .semibold)).foregroundStyle(look[.onSurface])
                Text(text).font(look.font(12.5)).foregroundStyle(look[.onSurfaceVariant]).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Demo pieces

private struct DemoWallpaper: View {
    @Environment(\.look) var look
    var body: some View {
        LinearGradient(colors: [look[.primaryContainer], look[.tertiaryContainer], look[.secondaryContainer]],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Circle().fill(look[.primary].opacity(0.35)).frame(width: 140).offset(x: 90, y: 40).blur(radius: 6))
    }
}

/// A small window: title bar dots + a live clock (the content that a snapshot would freeze).
private struct MockWindow: View {
    @Environment(\.look) var look
    var title = "Notes"
    var time: Date
    var frozen: Date?
    var tint: ColorRole = .surfaceContainerHigh
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 7, height: 7) }
                Text(title).font(look.font(10, .medium)).foregroundStyle(look[.onSurfaceVariant]).padding(.leading, 4)
                Spacer()
            }
            .padding(.horizontal, 9).frame(height: 22)
            .background(look[.surfaceContainerHighest])
            VStack(alignment: .leading, spacing: 5) {
                Text((frozen ?? time).formatted(.dateTime.hour().minute().second()))
                    .font(look.mono(16)).foregroundStyle(look[.onSurface])
                RoundedRectangle(cornerRadius: 3).fill(look[.onSurfaceVariant].opacity(0.25)).frame(height: 6)
                RoundedRectangle(cornerRadius: 3).fill(look[.onSurfaceVariant].opacity(0.25)).frame(width: 70, height: 6)
            }
            .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(look[tint])
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Pop-in every 2.4 s. SIP on: a still pops (clock frozen), swaps to live at the end. SIP off: the
/// live window springs on LiquidMotion.windowPop.
private struct PopDemo: View {
    var live: Bool
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = t.truncatingRemainder(dividingBy: 2.4)
            let start = ctx.date.addingTimeInterval(-phase)
            let p = phase < 1.6 ? LiquidMotion.windowPop.position(at: phase, from: 0, to: 1) : 1 - min(1, (phase - 1.6) / 0.25)
            let scale = 0.8 + 0.2 * p
            let animating = phase < LiquidMotion.settle
            MockWindow(time: ctx.date, frozen: !live && animating ? start : nil)
                .frame(width: 190, height: 120)
                .scaleEffect(live ? scale : (animating ? 0.8 + 0.2 * min(1, phase / LiquidMotion.settle) : scale))
                .opacity(min(1, max(0, p * 1.6)))
                .overlay(alignment: .bottom) {
                    if !live && animating {
                        Text("snapshot").font(.system(size: 9, weight: .semibold)).padding(3).background(.black.opacity(0.4)).foregroundStyle(.white).offset(y: 14)
                    }
                }
        }
    }
}

private struct OpacityDemo: View {
    var translucent: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            ZStack {
                MockWindow(title: "Terminal", time: ctx.date).frame(width: 170, height: 110).offset(x: -55, y: 10)
                    .opacity(translucent ? 0.95 : 1)
                    .shadow(color: .black.opacity(translucent ? 0 : 0.35), radius: 10, y: 4)
                MockWindow(title: "Browser", time: ctx.date, tint: .surfaceContainerLow).frame(width: 170, height: 110).offset(x: 55, y: 30)
                    .opacity(translucent ? 0.95 : 1)
                    .shadow(color: .black.opacity(translucent ? 0.15 : 0.35), radius: 10, y: 4)
            }
        }
    }
}

private struct WorkspaceDemo: View {
    var instant: Bool
    @Environment(\.look) var look
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3)
            // Switch at 1.2 s, back at 2.6 s; the slide takes 320 ms (Arch snappy).
            let target: Double = (t > 1.2 && t < 2.6) ? 1 : 0
            let since = t > 2.6 ? t - 2.6 : (t > 1.2 ? t - 1.2 : t + 0.4)
            let progress = instant ? 1 : min(1, since / 0.32)
            let eased = 1 - pow(1 - progress, 3)
            let position = target == 1 ? eased : 1 - eased
            GeometryReader { geo in
                HStack(spacing: 20) {
                    workspace(1, ctx.date).frame(width: geo.size.width)
                    workspace(2, ctx.date).frame(width: geo.size.width)
                }
                .offset(x: -position * (geo.size.width + 20))
            }
        }
    }

    private func workspace(_ n: Int, _ date: Date) -> some View {
        HStack(spacing: 8) {
            MockWindow(title: n == 1 ? "Code" : "Music", time: date).frame(width: 120, height: 120)
            MockWindow(title: n == 1 ? "Terminal" : "Chat", time: date, tint: .surfaceContainerLow).frame(width: 120, height: 120)
        }
        .overlay(alignment: .top) {
            Text("workspace \(n)").font(.system(size: 9, weight: .semibold)).foregroundStyle(look[.onSurface]).offset(y: -16)
        }
    }
}

private struct PinDemo: View {
    var onTop: Bool
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3)
            // Another window is raised and slides over the pinned one.
            let x = -120 + 160 * min(1, max(0, (t - 0.6) / 0.5)) * (t < 2.4 ? 1 : max(0, 1 - (t - 2.4) / 0.4))
            ZStack {
                MockWindow(title: "Pinned video", time: ctx.date, tint: .surfaceContainerLow).frame(width: 120, height: 80).offset(x: 60, y: -20)
                    .zIndex(onTop ? 2 : 0)
                MockWindow(title: "Editor", time: ctx.date).frame(width: 190, height: 120).offset(x: x, y: 10)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    .zIndex(1)
            }
        }
    }
}
