import CaelestiaCore
import CaelestiaIPC
import CaelestiaLayout
import CaelestiaPlatform
import CoreGraphics
import Foundation

/// IPC (spec 4.8): WM commands and `hyprctl -j`-style queries. Shell targets answer with an error
/// until the shell exists.
extension WindowManager {
    /// Handles one request. `wm.quit`/`wm.panic` restore every window synchronously; the caller
    /// should exit (`onQuit`) only after the response is written, so they return
    /// `quitRequested = true` instead of calling `onQuit`.
    public func respond(to request: IPCRequest) -> (response: IPCResponse, quitRequested: Bool) {
        guard let command = request.knownCommand else {
            return (.failure(for: request, error: "Unknown command \(request.command)"), false)
        }
        func ok(_ value: JSONValue? = nil) -> (IPCResponse, Bool) { (.success(for: request, result: value), false) }
        func encoded<T: Encodable>(_ value: T) -> (IPCResponse, Bool) { (.success(for: request, encoding: value), false) }
        func refused(_ what: String) -> (IPCResponse, Bool) { (.failure(for: request, error: what), false) }
        if let shell = shellResponder?(request, command) { return (shell, false) }

        switch command {
        case .hello:
            return ok(IPCHello().jsonValue)

        case .wsFocus:
            guard let n = request.int("index"), n >= 1 else { return refused("index must be a workspace number ≥ 1") }
            guard isManaging else { return refused("the WM is not managing windows") }
            state.focusWorkspace(.numbered(n))
            setNeedsLayout()
            return ok()
        case .wsMove:
            guard let n = request.int("index"), n >= 1 else { return refused("index must be a workspace number ≥ 1") }
            guard isManaging, let f = state.focusedWindow else { return refused("no focused window") }
            let moved = state.moveWindow(f, to: .numbered(n), follow: !(request.bool("silent") ?? false), env: environment)
            setNeedsLayout()
            return moved ? ok() : refused("the window cannot move to workspace \(n)")
        case .action:
            guard let name = request.string("action"), let kind = ActionKind(rawValue: name) else {
                return refused("unknown action \(request.string("action") ?? "")")
            }
            let args = request.args["args"]?.objectValue?.argValues ?? [:]
            if kind == .wmPanic { return (.success(for: request), panicFromIPC()) }
            perform(Action(kind, args: args))
            return ok()

        case .queryWindows: return encoded(windowEntries())
        case .queryWorkspaces: return encoded(workspaceEntries())
        case .queryMonitors: return encoded(monitorEntries())
        case .queryBinds, .keysList: return encoded(bindEntries())
        case .queryState: return encoded(stateEntry())
        case .queryOverlays: return encoded(decorations?.overlayEntries() ?? [])
        case .debugOverlay:
            let on = request.bool("on") ?? !debugOverlayEnabled
            setDebugOverlay(on)
            return ok(.object(["on": .bool(on)]))

        case .configReload:
            return ok(.object(["warnings": .array((onConfigReload?() ?? []).map(JSONValue.string))]))
        case .configGet:
            let raw = ConfigAPI(file: configFileURL).load()
            let path = request.string("path") ?? ""
            guard let value = ConfigAPI.value(at: path, in: raw), let json = try? JSONValue(any: value) else {
                return refused("no config key \(path)")
            }
            return ok(json)
        case .configSet, .configReset:
            guard let path = request.string("path"), !path.isEmpty else { return refused("path is required") }
            do {
                let api = ConfigAPI(file: configFileURL)
                if command == .configReset {
                    try api.reset(path)
                } else {
                    guard let v = request.args["value"], let value = Self.configValue(v) else { return refused("value is required") }
                    try api.set(path, value)
                }
            } catch {
                return refused(String(describing: error))
            }
            // Apply now instead of waiting for the file watcher (it sees the same text and skips).
            return ok(.object(["warnings": .array((onConfigReload?() ?? []).map(JSONValue.string))]))
        case .keysPause:
            let seconds = request.args["seconds"]?.doubleValue ?? 10
            onPauseHotkeys?(seconds)
            return ok(.object(["paused": .bool(seconds > 0 && onPauseHotkeys != nil)]))
        case .rulesReload:
            return ok(.object(["warnings": .array((onRulesReload?() ?? []).map(JSONValue.string))]))
        case .rulesApps:
            return encoded(appRuleEntries())
        case .rulesFocused:
            guard let e = focusedAppRule() else { return ok(.null) }
            return encoded(e)
        case .rulesSet:
            guard let bundle = request.string("bundleID"), !bundle.isEmpty else { return refused("bundleID is required") }
            guard let mode = request.string("mode").flatMap({ AppLayoutMode(rawValue: $0.lowercased()) }) else {
                return refused("mode must be tile, float or auto")
            }
            do {
                return encoded(try setAppRule(mode, for: bundle))
            } catch {
                return refused(String(describing: error))
            }

        case .wmPanic:
            return (.success(for: request), panicFromIPC())
        case .wmQuit:
            restoreEverything()
            return (.success(for: request), true)
        case .wmRestoreAll:
            restoreAllKeepingManagement()
            return ok()
        case .permissionsRequest:
            guard let name = request.string("kind"), let kind = Permissions.Kind(rawValue: name) else {
                return refused("kind must be accessibility, inputMonitoring or screenRecording")
            }
            let granted = Permissions.request(kind)
            if request.bool("open") ?? true, !granted { Permissions.openSettings(for: kind) }
            return ok(.object(["granted": .bool(granted)]))
        case .permissionsStatus:
            let s = permissionSnapshot()
            return encoded(PermissionsStatusEntry(
                accessibility: s.accessibility, inputMonitoring: s.inputMonitoring, screenRecording: s.screenRecording
            ))
        case .doctor:
            return ok(.object([
                "mode": .string(enhanced?.active == true ? "enhanced" : "standard"),
                "sipOff": .string(enhanced?.status ?? "off"),
                "managing": .bool(isManaging),
                "windows": JSONValue(managedWindowIDs.count),
                "parked": JSONValue(parked.count),
                "journalRecords": JSONValue(journal.records().count),
                "displays": .array(displays.map { .string("\($0.name) \($0.id)") }),
                "counters": .object(counters.dictionary.mapValues { JSONValue($0) }),
            ]))

        default:
            if let kind = command.equivalentAction {
                var args = request.args.argValues
                if kind == .specialToggle, args["name"] == nil { args["name"] = .string("special") }
                if kind == .wmPanic { return (.success(for: request), panicFromIPC()) }
                if perform(Action(kind, args: args)) || isWMAction(kind) { return ok() }
            }
            return refused("\(command.rawValue) is not available yet: the shell is not part of this build")
        }
    }

    /// The three permissions as this process has them, minus simulated losses.
    public func permissionSnapshot() -> PermissionSnapshot {
        let s = Permissions.status()
        return PermissionSnapshot(accessibility: s.accessibility, inputMonitoring: s.inputMonitoring, screenRecording: s.screenRecording)
            .simulatingMissing(simulatedMissingPermissions)
    }

    /// IPC value → config value: integral numbers are integers (TOML ints are valid floats too,
    /// not the other way round); a string starting with `[` or `{` is a TOML literal.
    static func configValue(_ v: JSONValue) -> ConfigValue? {
        switch v {
        case .bool(let b): return .bool(b)
        case .number(let d): return d.isFinite && d == d.rounded() && abs(d) < 1e15 ? .int(Int(d)) : .number(d)
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("[") || t.hasPrefix("{") ? .literal(t) : .string(s)
        default: return nil
        }
    }

    private func panicFromIPC() -> Bool {
        Log.wm.notice("panic via IPC: restoring every window and quitting")
        onPanic?()
        restoreEverything()
        return true
    }

    private func isWMAction(_ kind: ActionKind) -> Bool {
        kind.rawValue.hasPrefix("window.") || kind.rawValue.hasPrefix("workspace.") || kind.rawValue.hasPrefix("special.")
            || kind.rawValue.hasPrefix("group.")
    }

    // MARK: - Query entries

    /// Hyprland ids: numbered workspaces keep their number; `special:special` is −99 and named
    /// specials count up from −98 in name order.
    public func workspaceRef(_ id: WorkspaceID) -> WorkspaceRef {
        switch id {
        case .numbered(let n):
            return WorkspaceRef(id: n, name: String(n))
        case .special(let name):
            guard name != "special" else { return WorkspaceRef(id: -99, name: id.description) }
            let names = Set(config.wm.specialWorkspaces.keys).union(state.workspaces.keys.compactMap(\.specialName))
                .subtracting(["special"]).sorted()
            return WorkspaceRef(id: -98 + (names.firstIndex(of: name) ?? names.count), name: id.description)
        }
    }

    public func windowEntries() -> [WindowQueryEntry] {
        managedWindowIDs.compactMap { id -> WindowQueryEntry? in
            guard let handle = handles[id], let wsID = state.workspace(of: id), let ws = state[wsID] else { return nil }
            // Where the window really is (read from AX), not where we asked it to go: an app or
            // another WM may have moved it, and the CLI must not report a tile that isn't there.
            let real = handle.frame
            let frame = real.isNull ? (applied[id] ?? .zero) : real
            let d = descriptors[id]
            let fullscreen = ws.fullscreen == id ? 2 : (ws.maximized == id ? 1 : 0)
            return WindowQueryEntry(
                address: WindowQueryEntry.address(for: id),
                at: [Int(frame.minX.rounded()), Int(frame.minY.rounded())],
                size: [Int(frame.width.rounded()), Int(frame.height.rounded())],
                workspace: workspaceRef(wsID), floating: ws.isFloating(id), pinned: ws.pinned.contains(id),
                fullscreen: fullscreen, class: handle.bundleID, title: handle.title, pid: Int(handle.pid),
                focusHistoryID: focusOrder.firstIndex(of: id) ?? focusOrder.count,
                monitor: display(id: ws.displayID)?.name ?? ws.displayID,
                mapped: true, hidden: parked[id] != nil,
                appName: d?.appName, role: d?.role, subrole: d?.subrole, minimized: false
            )
        }
    }

    public func workspaceEntries() -> [WorkspaceQueryEntry] {
        state.workspaces.keys.sorted().compactMap { id -> WorkspaceQueryEntry? in
            guard let ws = state[id] else { return nil }
            let last = ws.lastFocused
            return WorkspaceQueryEntry(
                id: workspaceRef(id).id, name: workspaceRef(id).name,
                monitor: display(id: ws.displayID)?.name ?? ws.displayID, monitorID: ws.displayID,
                windows: ws.windows.count, hasfullscreen: ws.fullscreen != nil,
                lastwindow: last.map(WindowQueryEntry.address(for:)) ?? "0x0",
                lastwindowtitle: last.flatMap { handles[$0]?.title },
                group: id.number.map { WorkspaceMath.group(of: $0, perGroup: config.wm.workspacesPerGroup) },
                active: state.isVisible(id)
            )
        }
    }

    public func monitorEntries() -> [MonitorQueryEntry] {
        displays.map { d in
            let area = usableArea(of: d)
            let reserved = [
                Int((area.minX - d.frame.minX).rounded()), Int((area.minY - d.frame.minY).rounded()),
                Int((d.frame.maxX - area.maxX).rounded()), Int((d.frame.maxY - area.maxY).rounded()),
            ]
            let active = state.activeNumberedWorkspace(forDisplay: d.id) ?? 1
            return MonitorQueryEntry(
                name: d.name, id: d.id, width: Int(d.frame.width), height: Int(d.frame.height),
                x: Int(d.frame.minX), y: Int(d.frame.minY), scale: d.scale, reserved: reserved,
                activeWorkspace: workspaceRef(.numbered(active)),
                specialWorkspace: SpecialWorkspaceRef(name: state.openSpecial(onDisplay: d.id).map { "special:\($0)" } ?? ""),
                focused: state.focusedDisplay == d.id, displayID: Int(d.displayID), primary: d.isPrimary
            )
        }
    }

    public func bindEntries() -> [BindQueryEntry] {
        guard let keymap else { return [] }
        return keymap.binds.map { BindQueryEntry(bind: $0, modifiers: keymap.modifiers) }
    }

    public func stateEntry() -> StateQueryEntry {
        StateQueryEntry(
            mode: enhanced?.active == true ? "enhanced" : "standard", uptimeSeconds: now().timeIntervalSince(startDate),
            focusedWindow: state.focusedWindow.map(WindowQueryEntry.address(for:)),
            focusedWorkspace: state.focusedWorkspace.map(workspaceRef),
            focusedMonitor: display(id: state.focusedDisplay)?.name,
            windowCount: managedWindowIDs.count, workspaceCount: state.workspaces.count, monitorCount: displays.count,
            gameMode: config.wm.gameMode, counters: counters.dictionary
        )
    }
}
