import Darwin
import Foundation
import CaelestiaCore
import CaelestiaIPC
import CaelestiaPlatform

/// `skyrose doctor`: environment, versions, SIP (read-only), config/keymap parse results,
/// conflicts, socket state and — when the WM answers — its permission status.
/// `--fix` repairs a missing config, a Dock or menu bar SkyRose hid that came back, an empty
/// cursor setting, and a stale socket. Permissions are explained: macOS will not let SkyRose tick them.
struct Doctor {
    let client: IPCClient
    let json: Bool
    var fix: Bool = false

    enum Status: String {
        case ok, info, warn, fail

        var mark: String {
            switch self {
            case .ok: return "✓"
            case .info: return "·"
            case .warn: return "!"
            case .fail: return "✗"
            }
        }
    }

    struct Item {
        var status: Status
        var name: String
        var detail: String
        var data: JSONValue
    }

    func run() -> Int32 {
        let notes = fix ? apply(DoctorFix.plan(world())) : []
        var items: [Item] = []
        items.append(cli())
        items.append(system())
        items.append(developerTools())
        items.append(sip())
        items.append(config())
        let (keymapItem, keymap) = self.keymap()
        items.append(keymapItem)
        items.append(conflicts(keymap))
        items.append(app())
        items.append(socket())
        let (wmItem, running) = wm()
        items.append(wmItem)
        if running {
            items.append(contentsOf: permissions())
            items.append(tiling())
        }

        if json {
            var o: [String: JSONValue] = [:]
            for i in items { o[i.name] = ["status": .string(i.status.rawValue), "detail": .string(i.detail), "data": i.data] }
            if !notes.isEmpty { o["repairs"] = .array(notes.map(JSONValue.string)) }
            Console.out(JSONValue.object(o).prettyJSON)
        } else {
            Console.out("SkyRose — doctor")
            if !notes.isEmpty { Console.out(notes.joined(separator: "\n")) }
            var t = TextTable(["", "ITEM", "DETAIL"], showsHeader: false)
            for i in items { t.addRow([i.status.mark, i.name, i.detail]) }
            Console.out(t.render(), terminator: "")
            let fails = items.filter { $0.status == .fail }.count
            let warns = items.filter { $0.status == .warn }.count
            Console.out(fails == 0 && warns == 0 ? "Everything looks fine." : "\(fails) problem(s), \(warns) warning(s).")
        }
        return items.contains { $0.status == .fail } ? ExitCode.failed : ExitCode.ok
    }

    func world() -> DoctorWorld {
        let configURL = Paths.configFile
        let exists = FileManager.default.fileExists(atPath: configURL.path)
        var broken = false
        if exists { broken = (try? ConfigLoader.loadDetailed(from: configURL)) == nil }
        let journal = BackupJournal(url: Paths.restoreManifest)
        let dockJournaled = (try? journal.firstEntry(domain: DockRemoval.domain, key: DockRemoval.delayKey)) != nil
            || (try? journal.firstEntry(domain: DockRemoval.domain, key: "autohide")) != nil
        let menuJournaled = (try? journal.firstEntry(domain: SystemTweaks.globalDomain, key: "_HIHideMenuBar")) != nil
        let cursor = ConfigLoader.loadUserOrDefault().config.appearance.cursor
        let library = CursorCapeLibrary()
        let capeExists = library.url(for: cursor.isEmpty ? RecommendedSetup.cursorName : cursor) != nil
        var st = stat()
        let socketPresent = lstat(client.path.path, &st) == 0
        let socketHealthy = socketPresent && (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK) && Int(st.st_mode & 0o777) == 0o600
        let running = (try? client.hello(timeout: 1)) != nil
        var missing: [String] = []
        if running, let object = try? client.call(.permissionsStatus, timeout: 3).objectValue {
            for (key, title) in [("accessibility", "Accessibility"), ("inputMonitoring", "Input Monitoring"), ("screenRecording", "Screen Recording")] {
                if object[key]?.lenientBoolValue == false { missing.append(title) }
            }
        }
        return DoctorWorld(
            configExists: exists, configBroken: broken,
            dockHidden: DockRemoval().isHidden(), dockJournaled: dockJournaled,
            menuBarHidden: SystemTweaks().isOn(.menuBarAutoHide), menuBarJournaled: menuJournaled,
            cursor: cursor, cursorCapeExists: capeExists,
            socketPresent: socketPresent, socketHealthy: socketHealthy || !socketPresent, wmRunning: running,
            missingPermissions: missing
        )
    }

    /// Performs the safe repairs and returns one plain sentence each.
    func apply(_ repairs: [DoctorRepair]) -> [String] {
        repairs.map { repair in
            switch repair {
            case .writeDefaultConfig:
                do {
                    let text = try ConfigLoader.defaultResourceText()
                    let url = Paths.configFile
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(text.utf8).write(to: url, options: .atomic)
                    return "Wrote a config file at \(Environment.tilde(url))."
                } catch {
                    return "Could not write the config file: \(error.localizedDescription)"
                }
            case .rehideDock:
                do { try DockRemoval().hide(); return "The Dock was showing again. It is hidden once more." }
                catch { return "Could not hide the Dock: \(error.localizedDescription)" }
            case .rehideMenuBar:
                do { try SystemTweaks().apply(.menuBarAutoHide); return "The menu bar was showing again. It hides automatically once more." }
                catch { return "Could not hide the menu bar: \(error.localizedDescription)" }
            case .restoreDefaultCursor:
                do {
                    try ConfigFileEditor.set("cursor", to: ConfigFileEditor.string(RecommendedSetup.cursorName), inTable: "appearance", file: Paths.configFile)
                    return "The cursor setting was empty. It is \(RecommendedSetup.cursorName) again. Restart SkyRose if the pointer has not changed."
                } catch {
                    return "Could not restore the cursor setting: \(error.localizedDescription)"
                }
            case .removeStaleSocket:
                do {
                    try FileManager.default.removeItem(at: client.path)
                    return "Removed a leftover socket at \(Environment.tilde(client.path))."
                } catch {
                    return "Could not remove the leftover socket: \(error.localizedDescription)"
                }
            case .explain(let text):
                return text
            }
        }
    }

    // MARK: Items

    private func cli() -> Item {
        let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path ?? "?"
        return Item(
            status: .info, name: "cli",
            detail: "skyrose \(CaelestiaVersion.string), protocol \(CaelestiaVersion.protocolVersion), \(path)",
            data: ["version": .string(CaelestiaVersion.string), "protocolVersion": .number(Double(CaelestiaVersion.protocolVersion)), "path": .string(path)]
        )
    }

    private func system() -> Item {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let supported = v.majorVersion >= 14
        let arch = Environment.architecture
        let laptop = Environment.isLaptop
        return Item(
            status: supported ? (arch == "arm64" ? .ok : .warn) : .fail, name: "macos",
            detail: "macOS \(Environment.macOSVersion), \(arch), \(Environment.model)\(laptop ? " (laptop)" : "")"
                + (supported ? "" : " — macOS 14 or newer is required") + (arch == "arm64" ? "" : " — Apple Silicon is the supported platform"),
            data: ["version": .string(Environment.macOSVersion), "arch": .string(arch), "model": .string(Environment.model), "laptop": .bool(laptop)]
        )
    }

    private func developerTools() -> Item {
        if let dir = Environment.developerDirectory {
            let xcode = dir.contains("Xcode.app")
            return Item(status: .info, name: "developerTools", detail: "\(dir)\(xcode ? "" : " (Command Line Tools; Xcode 16+ is needed only to build)")", data: .string(dir))
        }
        return Item(status: .info, name: "developerTools", detail: "none selected (only needed to build from source)", data: .null)
    }

    private func sip() -> Item {
        guard let status = Environment.sipStatus else {
            return Item(status: .info, name: "sip", detail: "csrutil status unavailable", data: .null)
        }
        let detail = status.hasPrefix("enabled") ? "\(status) — Standard mode (recommended)" : "\(status) — Enhanced mode possible; see docs/ENHANCED_MODE.md"
        return Item(status: .info, name: "sip", detail: detail, data: .string(status))
    }

    private func config() -> Item {
        let url = Paths.configFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Item(status: .info, name: "config", detail: "\(Environment.tilde(url)) not present; built-in defaults in use", data: ["present": false])
        }
        do {
            let result = try ConfigLoader.loadDetailed(from: url)
            let w = result.warnings
            return Item(
                status: w.isEmpty ? .ok : .warn, name: "config",
                detail: "\(Environment.tilde(url)) ok" + (w.isEmpty ? "" : "; \(w.count) warning(s): " + w.joined(separator: " | ")),
                data: ["present": true, "ok": true, "warnings": .array(w.map(JSONValue.string))]
            )
        } catch {
            return Item(status: .fail, name: "config", detail: "\(Environment.tilde(url)): \(error.localizedDescription) — defaults in use", data: ["present": true, "ok": false, "error": .string(error.localizedDescription)])
        }
    }

    private func keymap() -> (Item, Keymap) {
        let url = Paths.keymapFile
        let (keymap, warnings) = KeymapLoader.loadUserOrDefault()
        let present = FileManager.default.fileExists(atPath: url.path)
        let source = present ? Environment.tilde(url) : "bundled default (\(Environment.tilde(url)) not present)"
        let summary = "\(keymap.binds.count) binds, preset \(keymap.modifiers.preset.rawValue)"
        let failed = warnings.contains { $0.contains("using the default keymap") }
        let status: Status = failed ? .fail : (warnings.isEmpty ? (present ? .ok : .info) : .warn)
        let detail = "\(source): \(summary)" + (warnings.isEmpty ? "" : "; " + warnings.joined(separator: " | "))
        return (
            Item(status: status, name: "keymap", detail: detail, data: [
                "present": .bool(present), "binds": .number(Double(keymap.binds.count)),
                "preset": .string(keymap.modifiers.preset.rawValue), "warnings": .array(warnings.map(JSONValue.string)),
            ]),
            keymap
        )
    }

    private func conflicts(_ keymap: Keymap) -> Item {
        let report = ConflictChecker(keymap: keymap, isLaptop: Environment.isLaptop).check()
        let status: Status = report.errorCount > 0 ? .fail : (report.warnCount > 0 ? .warn : .ok)
        return Item(
            status: status, name: "keysCheck",
            detail: "\(report.errorCount) error(s), \(report.warnCount) warning(s), \(report.infoCount) info — `skyrose keys check` for details",
            data: ["errors": .number(Double(report.errorCount)), "warnings": .number(Double(report.warnCount)), "infos": .number(Double(report.infoCount))]
        )
    }

    private func app() -> Item {
        guard let url = Environment.wmAppURL else {
            return Item(status: .warn, name: "app", detail: "\(Environment.wmBundleID) not installed (run scripts/install.sh)", data: .null)
        }
        let version = Environment.bundleVersion(url) ?? "?"
        return Item(status: .ok, name: "app", detail: "\(Environment.tilde(url)) version \(version)", data: ["path": .string(url.path), "version": .string(version)])
    }

    private func socket() -> Item {
        let path = client.path.path
        var st = stat()
        guard lstat(path, &st) == 0 else {
            return Item(status: .info, name: "socket", detail: "\(Environment.tilde(client.path)) absent", data: ["present": false])
        }
        let isSocket = (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK)
        let mode = Int(st.st_mode & 0o777)
        let modeText = String(mode, radix: 8)
        let good = isSocket && mode == 0o600
        return Item(
            status: good ? .ok : .warn, name: "socket",
            detail: "\(Environment.tilde(client.path)) present, mode 0\(modeText)" + (isSocket ? "" : " — not a socket") + (mode == 0o600 ? "" : " — expected 0600"),
            data: ["present": true, "socket": .bool(isSocket), "mode": .string("0" + modeText)]
        )
    }

    private func wm() -> (Item, Bool) {
        do {
            let h = try client.hello(timeout: 2)
            let match = h.protocolVersion == CaelestiaVersion.protocolVersion
            return (
                Item(
                    status: match ? .ok : .fail, name: "wm",
                    detail: "running, pid \(h.pid), version \(h.version), protocol \(h.protocolVersion)" + (match ? "" : " — mismatch with CLI protocol \(CaelestiaVersion.protocolVersion); restart the WM"),
                    data: ["running": true, "pid": .number(Double(h.pid)), "version": .string(h.version), "protocolVersion": .number(Double(h.protocolVersion)), "protocolMatch": .bool(match)]
                ),
                match
            )
        } catch let error as IPCError {
            let detail: String
            switch error {
            case .notRunning: detail = "not running (start with `skyrose shell -d`)"
            case .timeout: detail = "socket present but the WM does not answer (hung?) — `skyrose shell restart` or kill it"
            default: detail = error.localizedDescription
            }
            return (Item(status: .fail, name: "wm", detail: detail, data: ["running": false, "error": .string(error.localizedDescription)]), false)
        } catch {
            return (Item(status: .fail, name: "wm", detail: error.localizedDescription, data: ["running": false]), false)
        }
    }

    private func permissions() -> [Item] {
        do {
            let result = try client.call(.permissionsStatus, timeout: 5)
            guard let object = result.objectValue else {
                return [Item(status: .warn, name: "permissions", detail: "unexpected reply: \(result.compactJSON)", data: result)]
            }
            var items: [Item] = []
            let required: [(String, String, Bool)] = [
                ("accessibility", "Accessibility", true),
                ("inputMonitoring", "Input Monitoring", true),
                ("screenRecording", "Screen Recording", false),
            ]
            for (key, title, isRequired) in required {
                guard let v = object[key] else { continue }
                let granted = v.lenientBoolValue
                let status: Status = granted == true ? .ok : (isRequired ? .fail : .warn)
                let text = granted == true ? "granted" : (granted == false ? "not granted" : QueryFormatter.render(v, command: nil).trimmingCharacters(in: .whitespacesAndNewlines))
                let hint = granted == true ? "" : (isRequired ? " — required; System Settings > Privacy & Security > \(title)" : " — optional (snapshots, screenshots, recorder, colour picker)")
                items.append(Item(status: status, name: "permissions.\(key)", detail: "\(title): \(text)\(hint)", data: v))
            }
            if let automation = object["automation"]?.objectValue, !automation.isEmpty {
                let text = automation.keys.sorted().map { "\($0)=\(automation[$0]!.lenientBoolValue == true ? "yes" : "no")" }.joined(separator: ", ")
                items.append(Item(status: .info, name: "permissions.automation", detail: "Automation: \(text)", data: .object(automation)))
            }
            if let mode = object["mode"]?.stringValue {
                let loaded = object["enhancedLoaded"]?.lenientBoolValue ?? false
                items.append(Item(status: .info, name: "mode", detail: "\(mode)\(mode == "enhanced" ? (loaded ? " (scripting addition loaded)" : " (scripting addition NOT loaded)") : "")", data: .string(mode)))
            }
            return items
        } catch {
            return [Item(status: .warn, name: "permissions", detail: "permissions.status failed: \(error.localizedDescription)", data: .null)]
        }
    }

    /// Notes from the tiler: a window larger than the screen, a split flipped, a stack, a window
    /// put back on its tile. Empty means nothing had to be rescued.
    private func tiling() -> Item {
        do {
            let result = try client.call(.queryState, timeout: 2)
            let notes = result["tilingNotes"]?.arrayValue?.compactMap(\.stringValue) ?? []
            if notes.isEmpty {
                return Item(
                    status: .ok, name: "tiling",
                    detail: "tiled windows are in their slots (or explicitly floating)",
                    data: .array([])
                )
            }
            return Item(
                status: .warn, name: "tiling",
                detail: notes.joined(separator: " | "),
                data: .array(notes.map(JSONValue.string))
            )
        } catch {
            return Item(status: .info, name: "tiling", detail: "could not read tiling notes: \(error.localizedDescription)", data: .null)
        }
    }
}
