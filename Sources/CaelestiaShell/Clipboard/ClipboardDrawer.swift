import AppKit
import CaelestiaCore
import ImageIO
import SwiftUI

/// Watches the pasteboard and holds the Super+V history. The drawer is the launcher's shape on the
/// shell's surface: same size rules, row style, motion and colours. Nothing leaves this Mac.
@MainActor
public final class ClipboardSession: ObservableObject {
    public static let width: Double = 600
    public static let maxRows = 7
    public static let rowHeight = LauncherModel.itemHeight
    public static let previewHeight: Double = 150
    public static let footerHeight: Double = 30

    public static var listHeight: Double {
        Double(maxRows) * rowHeight + Double(maxRows - 1) * LauncherModel.itemSpacing
    }

    public static var bodySize: CGSize {
        CGSize(width: width, height: LauncherModel.padding * 2 + listHeight + 2 * LauncherModel.gap + footerHeight + LauncherModel.searchHeight)
    }

    @Published public var history: ClipboardHistory
    @Published public var shown = false
    @Published public var query = "" { didSet { if query != oldValue { selected = 0 } } }
    @Published public var selected = 0

    public var directory: URL
    /// Closes the drawer through the shell, so it leaves on the same motion as every other one.
    public var onClose: () -> Void = {}
    /// Types ⌘V into the app that was focused. Tests replace it.
    var typePaste: () -> Void = { ClipboardSession.typeV() }

    private let board: NSPasteboard
    private var timer: Timer?
    private var lastChange: Int
    private var ignoreChange = 0
    private var thumbnails: [UUID: NSImage] = [:]
    private var previews: [UUID: NSImage] = [:]

    public init(directory: URL = Paths.appSupport.appendingPathComponent("clipboard", isDirectory: true),
                maxEntries: Int = 50, maxBytes: Int = 32 * 1024 * 1024, board: NSPasteboard = .general) {
        self.directory = directory
        self.board = board
        lastChange = board.changeCount
        history = ClipboardArchive.load(from: directory, maxEntries: maxEntries, maxBytes: maxBytes)
    }

    public func start() {
        lastChange = board.changeCount
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() { timer?.invalidate(); timer = nil }

    /// Newest first with no search, best match first with one.
    public var rows: [ClipboardEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return history.entries }
        let scored = history.entries.enumerated().compactMap { index, entry -> (entry: ClipboardEntry, score: Int, index: Int)? in
            guard let match = FuzzyMatcher.match(q, in: entry.text ?? entry.preview) else { return nil }
            return (entry, match.score, index)
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }.map(\.entry)
    }

    /// Called as the drawer opens.
    public func prepare() {
        query = ""
        selected = 0
    }

    public func move(_ delta: Int) {
        let count = rows.count
        guard count > 0 else { return }
        selected = max(0, min(count - 1, selected + delta))
    }

    public func deleteSelected() {
        let list = rows
        guard list.indices.contains(selected) else { return }
        let id = list[selected].id
        history.remove(id: id)
        thumbnails[id] = nil
        previews[id] = nil
        persist()
        selected = min(selected, max(0, rows.count - 1))
    }

    public func clear() {
        history.clear()
        thumbnails = [:]
        previews = [:]
        selected = 0
        persist()
    }

    public func togglePause() {
        history.paused.toggle()
        persist()
    }

    /// Return pastes into the previous app, Shift+Return only copies.
    public func activateSelected(alsoPaste: Bool) {
        let list = rows
        guard list.indices.contains(selected) else { return }
        paste(list[selected], alsoType: alsoPaste)
    }

    public func pasteNewest() {
        guard let entry = history.entries.first else { return }
        paste(entry, alsoType: true)
    }

    func poll() {
        let change = board.changeCount
        guard change != lastChange, change != ignoreChange else { return }
        lastChange = change
        let types = Set((board.types ?? []).map(\.rawValue))
        let files = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.map(\.path)
        let text = board.string(forType: .string)
        var image = board.data(forType: .png)
        if image == nil, let tiff = board.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) {
            image = rep.representation(using: .png, properties: [:])
        }
        if history.record(text: text, imagePNG: image, types: types, at: Date(), files: files) { persist() }
    }

    func paste(_ entry: ClipboardEntry, alsoType: Bool) {
        board.clearContents()
        if let files = entry.files {
            board.writeObjects(files.map { URL(fileURLWithPath: $0) as NSURL })
        } else {
            if let text = entry.text { board.setString(text, forType: .string) }
            if let png = entry.imagePNG { board.setData(png, forType: .png) }
        }
        ignoreChange = board.changeCount
        lastChange = board.changeCount
        onClose()
        guard alsoType else { return }
        // The drawer gives up the keyboard as it closes. ⌘V has to arrive after that.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [typePaste] in typePaste() }
    }

    /// The drawer's keys, taken before the search field sees them.
    func key(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: onClose(); return true // esc
        case 125, 48: move(1); return true // down, tab
        case 126: move(-1); return true // up
        case 36, 76: // return, keypad enter
            activateSelected(alsoPaste: !event.modifierFlags.contains(.shift))
            return true
        case 51: // delete: with text in the field it is still ordinary typing
            guard query.isEmpty else { return false }
            deleteSelected()
            return true
        default: return false
        }
    }

    public func setLimits(maxEntries: Int, maxBytes: Int) {
        if history.setLimits(maxEntries: maxEntries, maxBytes: maxBytes) { persist() }
    }

    func persist() { try? ClipboardArchive.save(history, to: directory) }

    func thumbnail(for entry: ClipboardEntry) -> NSImage? {
        cached(entry, in: &thumbnails, maxPixels: 96)
    }

    func preview(for entry: ClipboardEntry) -> NSImage? {
        cached(entry, in: &previews, maxPixels: 900)
    }

    private func cached(_ entry: ClipboardEntry, in store: inout [UUID: NSImage], maxPixels: Int) -> NSImage? {
        if let image = store[entry.id] { return image }
        guard let png = entry.imagePNG, let image = Self.scaled(png, maxPixels: maxPixels) else { return nil }
        store[entry.id] = image
        return image
    }

    /// Decodes a small copy, so a large screenshot is not decoded in full for its row.
    nonisolated static func scaled(_ png: Data, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
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
    @ObservedObject var session: ClipboardSession
    let fillet: Double
    @Environment(\.shellTheme) var theme
    @FocusState private var focused: Bool

    var body: some View {
        let size = ClipboardSession.bodySize
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                DrawerBackground(edge: .bottom, fillet: fillet, radius: theme.frameRounding, shown: session.shown, depth: size.height)
                VStack(spacing: LauncherModel.gap) {
                    list
                    footer
                    search
                }
                .padding(LauncherModel.padding)
                .frame(width: size.width)
                .liquidContent(edge: .bottom, shown: session.shown, depth: size.height, theme: theme)
            }
            .frame(width: size.width + 2 * fillet, height: size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onChange(of: session.shown) { _, shown in if shown { focused = true } }
        .onAppear { focused = true }
    }

    @ViewBuilder private var list: some View {
        let rows = session.rows
        if rows.isEmpty {
            VStack(spacing: 6) {
                MaterialIcon("content_paste", size: 30, weight: .light)
                Text(session.history.entries.isEmpty ? "Nothing copied yet" : "No results").font(theme.sans(14, weight: .medium))
                if session.history.paused {
                    Text("History is paused").font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant].opacity(0.8))
                }
            }
            .foregroundStyle(theme[.onSurfaceVariant])
            .frame(maxWidth: .infinity)
            .frame(height: ClipboardSession.listHeight)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: LauncherModel.itemSpacing) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                            ClipboardRow(session: session, entry: entry, selected: index == session.selected)
                                .id(entry.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    session.selected = index
                                    session.activateSelected(alsoPaste: true)
                                }
                                .onHover { if $0 { session.selected = index } }
                        }
                    }
                }
                .frame(height: ClipboardSession.listHeight)
                .onChange(of: session.selected) { _, new in
                    guard rows.indices.contains(new) else { return }
                    withAnimation(theme.spatial) { proxy.scrollTo(rows[new].id) }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            pill(session.history.paused ? "Resume" : "Pause", icon: session.history.paused ? "play_arrow" : "pause") { session.togglePause() }
            pill("Clear history", icon: "delete") { session.clear() }
            Spacer(minLength: 0)
            Text("Return pastes · Shift+Return copies · Delete removes")
                .font(theme.sans(11)).foregroundStyle(theme[.onSurfaceVariant]).lineLimit(1)
        }
        .frame(height: ClipboardSession.footerHeight)
    }

    private func pill(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                MaterialIcon(icon, size: 13, weight: .medium)
                Text(title).font(theme.sans(12, weight: .medium))
            }
            .foregroundStyle(theme[.onSecondaryContainer])
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(theme[.secondaryContainer].opacity(0.7)))
        }
        .buttonStyle(.plain)
    }

    private var search: some View {
        HStack(spacing: 10) {
            MaterialIcon("magnifyingglass", size: 15, weight: .medium)
                .foregroundStyle(theme[.onSurfaceVariant])
            TextField("", text: $session.query, prompt: Text("Search your clipboard").foregroundColor(theme[.onSurfaceVariant]))
                .textFieldStyle(.plain)
                .font(theme.sans(16))
                .foregroundStyle(theme[.onSurface])
                .focused($focused)
                .accessibilityIdentifier("clipboard.search")
        }
        .padding(.horizontal, 20)
        .frame(height: LauncherModel.searchHeight)
        .background(Capsule().fill(theme[.secondaryContainer].opacity(0.7)))
    }
}

private struct ClipboardRow: View {
    @ObservedObject var session: ClipboardSession
    var entry: ClipboardEntry
    var selected: Bool
    @Environment(\.shellTheme) var theme

    private var showsPreview: Bool { selected && entry.imagePNG != nil }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                icon.frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.preview)
                        .font(theme.sans(20))
                        .foregroundStyle(theme[.onSurface])
                        .lineLimit(1)
                    Text(detail)
                        .font(theme.sans(16))
                        .foregroundStyle(theme[.outline])
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(height: ClipboardSession.rowHeight)
            if showsPreview, let image = session.preview(for: entry) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: ClipboardSession.previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(theme[.secondaryContainer].opacity(selected ? 0.6 : 0))
        )
        .animation(theme.small, value: selected)
        .animation(theme.spatial, value: showsPreview)
    }

    private var detail: String {
        let kind: String
        if entry.files != nil {
            kind = (entry.files?.count ?? 0) > 1 ? "Files" : "File"
        } else if entry.imagePNG != nil {
            kind = "Image"
        } else {
            kind = "Text"
        }
        return "\(kind) · \(entry.date.formatted(.relative(presentation: .named)))"
    }

    @ViewBuilder private var icon: some View {
        if let image = session.thumbnail(for: entry) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            MaterialIcon(entry.files != nil ? "draft" : "notes", size: 20, weight: .medium)
                .foregroundStyle(theme[.onSurfaceVariant])
        }
    }
}
