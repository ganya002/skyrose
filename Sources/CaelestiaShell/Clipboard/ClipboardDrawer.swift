import AppKit
import CaelestiaCore
import SwiftUI

/// Watches the general pasteboard and shows the Super+V history.
@MainActor
public final class ClipboardSession {
    public var history: ClipboardHistory
    public var directory: URL
    public var query = ""
    public var selected = 0
    private var panel: ShellPanel?
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private var ignoreChange = 0

    public init(directory: URL = Paths.appSupport.appendingPathComponent("clipboard", isDirectory: true),
                maxEntries: Int = 50, maxBytes: Int = 32 * 1024 * 1024) {
        self.directory = directory
        history = ClipboardArchive.load(from: directory, maxEntries: maxEntries, maxBytes: maxBytes)
    }

    public func start() {
        lastChange = NSPasteboard.general.changeCount
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() { timer?.invalidate(); timer = nil }

    public var shown: [ClipboardEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return history.entries }
        return history.entries.filter { $0.preview.lowercased().contains(q) }
    }

    public func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    public func show() {
        selected = 0
        let host = ShellHostingView(rootView: ClipboardDrawerView(session: self))
        let frame = NSRect(x: 0, y: 0, width: 420, height: 520)
        let panel = ShellPanel(frame: frame, level: ShellLevel.drawer, name: "clipboard")
        panel.acceptsKey = true
        panel.contentView = host
        panel.onKeyDown = { [weak self] event in
            MainActor.assumeIsolated { self?.key(event) ?? false }
        }
        panel.center()
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
    }

    public func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    public func deleteSelected() {
        let rows = shown
        guard rows.indices.contains(selected) else { return }
        history.remove(id: rows[selected].id)
        persist()
        if selected >= shown.count { selected = max(0, shown.count - 1) }
        refresh()
    }

    public func pasteNewest() {
        guard let entry = history.entries.first else { return }
        paste(entry, alsoType: true)
    }

    func poll() {
        let board = NSPasteboard.general
        let change = board.changeCount
        guard change != lastChange, change != ignoreChange else { return }
        lastChange = change
        let types = Set((board.types ?? []).map(\.rawValue))
        let text = board.string(forType: .string)
        var image = board.data(forType: .png)
        if image == nil, let tiff = board.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) {
            image = rep.representation(using: .png, properties: [:])
        }
        if history.record(text: text, imagePNG: image, types: types, at: Date()) {
            persist()
            refresh()
        }
    }

    func paste(_ entry: ClipboardEntry, alsoType: Bool) {
        let board = NSPasteboard.general
        board.clearContents()
        if let text = entry.text { board.setString(text, forType: .string) }
        if let png = entry.imagePNG { board.setData(png, forType: .png) }
        ignoreChange = board.changeCount
        lastChange = board.changeCount
        hide()
        guard alsoType else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Self.typeV() }
    }

    func key(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: hide(); return true // esc
        case 125: selected = min(shown.count - 1, selected + 1); refresh(); return true // down
        case 126: selected = max(0, selected - 1); refresh(); return true // up
        case 36, 76: // return, keypad enter
            let rows = shown
            guard rows.indices.contains(selected) else { return true }
            paste(rows[selected], alsoType: !event.modifierFlags.contains(.shift))
            return true
        case 51: deleteSelected(); return true // delete
        default: return false
        }
    }

    func persist() { try? ClipboardArchive.save(history, to: directory) }

    func refresh() {
        guard let host = panel?.contentView as? ShellHostingView<ClipboardDrawerView> else { return }
        host.rootView = ClipboardDrawerView(session: self)
    }

    static func typeV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

struct ClipboardDrawerView: View {
    @ObservedObject private var box: Box
    init(session: ClipboardSession) { box = Box(session) }

    var body: some View {
        let session = box.session
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search", text: Binding(get: { session.query }, set: { session.query = $0; session.selected = 0; box.objectWillChange.send() }))
                .textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(session.shown.enumerated()), id: \.element.id) { index, entry in
                        HStack(alignment: .top, spacing: 8) {
                            if let png = entry.imagePNG, let image = NSImage(data: png) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 44, height: 44)
                            }
                            Text(entry.preview).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(index == session.selected ? Color.accentColor.opacity(0.25) : Color.clear))
                        .onTapGesture {
                            session.selected = index
                            box.objectWillChange.send()
                        }
                    }
                }
            }
            HStack {
                Button(session.history.paused ? "Resume" : "Pause") {
                    session.history.paused.toggle()
                    session.persist()
                    box.objectWillChange.send()
                }
                Button("Clear") { session.history.clear(); session.persist(); box.objectWillChange.send() }
                Spacer()
                Text("Return pastes · Shift+Return copies").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

extension ClipboardDrawerView {
    final class Box: ObservableObject {
        let session: ClipboardSession
        init(_ session: ClipboardSession) { self.session = session }
    }
}
