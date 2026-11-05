import AppKit
import Foundation
import CaelestiaCore
import CaelestiaIPC
import CaelestiaPlatform

/// Verbs that run inside the CLI process.
enum LocalCommands {
    static func run(_ command: CLILocalCommand, invocation: CLIInvocation, client: IPCClient) -> Int32 {
        switch command {
        case .keysCheck:
            return keysCheck(json: invocation.json)
        case .keysList:
            return keysList(json: invocation.json)
        case .doctor:
            return Doctor(client: client, json: invocation.json).run()
        case .uninstall:
            return Uninstaller(assumeYes: invocation.yes, client: client).run()
        case .shellStart:
            return ShellStarter(client: client, timeout: invocation.timeout ?? 15).run()
        case .shellTargets(let target):
            Console.out(CLIParser.shellTargetsHelp(target: target), terminator: "")
            return ExitCode.ok
        case .migrate:
            return migrate(json: invocation.json)
        case .openSettings(let onboarding):
            return openSettings(onboarding: onboarding)
        case .cursor(let verb):
            return cursor(verb, json: invocation.json)
        }
    }

    // MARK: version

    /// `skyrose version`: CLI version, plus the WM's when it answers.
    static func version(client: IPCClient, json: Bool) -> Int32 {
        let hello = try? client.hello(timeout: 1)
        if json {
            var o: [String: JSONValue] = [
                "cli": ["version": .string(CaelestiaVersion.string), "protocolVersion": .number(Double(CaelestiaVersion.protocolVersion))],
            ]
            if let h = hello {
                o["wm"] = ["version": .string(h.version), "protocolVersion": .number(Double(h.protocolVersion)), "pid": .number(Double(h.pid))]
            } else {
                o["wm"] = .null
            }
            Console.out(JSONValue.object(o).prettyJSON)
            return ExitCode.ok
        }
        Console.out("skyrose \(CaelestiaVersion.string) (protocol \(CaelestiaVersion.protocolVersion))")
        if let h = hello {
            let match = h.protocolVersion == CaelestiaVersion.protocolVersion ? "" : "  (protocol mismatch: restart the WM)"
            Console.out("SkyRose WM \(h.version) (protocol \(h.protocolVersion), pid \(h.pid))\(match)")
        } else {
            Console.out("SkyRose WM not running")
        }
        return ExitCode.ok
    }

    // MARK: keys check

    /// `skyrose keys check`: the section 3.3 conflict checker on the user keymap. Exit 1 when
    /// any error-severity item exists.
    static func keysCheck(json: Bool) -> Int32 {
        let (keymap, warnings) = KeymapLoader.loadUserOrDefault()
        let report = ConflictChecker(keymap: keymap, isLaptop: Environment.isLaptop).check()
        if json {
            do {
                var object = try JSONValue(encoding: report).objectValue ?? [:]
                object["warnings"] = .array(warnings.map(JSONValue.string))
                object["preset"] = .string(keymap.modifiers.preset.rawValue)
                object["bindCount"] = .number(Double(keymap.binds.count))
                Console.out(JSONValue.object(object).prettyJSON)
            } catch {
                Console.error("cannot encode report: \(error.localizedDescription)")
                return ExitCode.failed
            }
        } else {
            for w in warnings { Console.err("warning: \(w)") }
            let table = report.formattedTable()
            if !table.isEmpty { Console.out(table, terminator: table.hasSuffix("\n") ? "" : "\n") }
            Console.out("\(keymap.binds.count) binds, preset \(keymap.modifiers.preset.rawValue): \(report.errorCount) error(s), \(report.warnCount) warning(s), \(report.infoCount) info")
        }
        return report.errorCount > 0 ? ExitCode.failed : ExitCode.ok
    }

    // MARK: keys list

    /// `skyrose keys list`: every bind in the user keymap with its Mac chord.
    static func keysList(json: Bool) -> Int32 {
        let (keymap, warnings) = KeymapLoader.loadUserOrDefault()
        let entries = keymap.binds.map { BindQueryEntry(bind: $0, modifiers: keymap.modifiers) }
        if json {
            do {
                Console.out(try JSONValue(encoding: entries).prettyJSON)
            } catch {
                Console.error("cannot encode binds: \(error.localizedDescription)")
                return ExitCode.failed
            }
            return ExitCode.ok
        }
        for w in warnings { Console.err("warning: \(w)") }
        Console.out(QueryFormatter.binds(entries), terminator: "")
        let disabled = entries.filter { !$0.enabled }.count
        Console.out("\(entries.count) binds (\(disabled) disabled), preset \(keymap.modifiers.preset.rawValue)")
        return ExitCode.ok
    }
}

/// `skyrose shell -d`: start the WM app (which hosts the shell) and wait for its socket.
struct ShellStarter {
    let client: IPCClient
    let timeout: TimeInterval

    func run() -> Int32 {
        if let h = try? client.hello(timeout: 1) {
            Console.out("SkyRose WM already running (pid \(h.pid), version \(h.version))")
            return ExitCode.ok
        }
        guard let app = Environment.wmAppURL else {
            Console.error("SkyRose WM is not installed (no app with bundle id \(Environment.wmBundleID)).")
            Console.err("")
            Console.err("Install it from a clone of the repository:")
            Console.err("    ./scripts/install.sh          # builds, copies the apps to ~/Applications, sets up the login item")
            Console.err("or build without installing:")
            Console.err("    ./scripts/build.sh && open dist/SkyRose.app")
            return ExitCode.failed
        }
        Console.out("Starting \(Environment.tilde(app)) …")
        let launch = Environment.run("/usr/bin/open", ["-b", Environment.wmBundleID, "--background"], timeout: 30)
        guard launch.status == 0 else {
            Console.error("`open -b \(Environment.wmBundleID)` failed (\(launch.status)): \(launch.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
            return ExitCode.failed
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let h = try? client.hello(timeout: 1) {
                let mismatch = h.protocolVersion == CaelestiaVersion.protocolVersion ? "" : "  (protocol mismatch: CLI \(CaelestiaVersion.protocolVersion), WM \(h.protocolVersion))"
                Console.out("SkyRose WM \(h.version) running (pid \(h.pid))\(mismatch)")
                return ExitCode.ok
            }
            usleep(200_000)
        }
        Console.error("the app launched but no IPC socket appeared at \(Environment.tilde(client.path)) within \(Int(timeout)) s.")
        Console.err("Check Console.app for 'com.skyrose.mac' messages, or run `skyrose doctor`.")
        return ExitCode.failed
    }
}

/// `skyrose uninstall` (spec 10.5): runs `scripts/uninstall.sh` when it can be found, otherwise
/// prints the manual steps. The script is the single source of truth so it also works when the app
/// is already gone.
struct Uninstaller {
    let assumeYes: Bool
    let client: IPCClient

    func run() -> Int32 {
        // Decided before anything is removed (the script moves Application Support to the Trash).
        let sipReminder = RestoreManifest().mustShowSIPReminder(csrutilStatus: SIPStatus.readCSRUtil())
        defer { if sipReminder { showSIPReminder() } }
        guard let script = locateScript() else {
            printManualSteps()
            return ExitCode.failed
        }
        Console.out("Uninstall script: \(Environment.tilde(script))")
        Console.out("It stops the WM, restores every window and every backed-up setting, removes the login item,")
        Console.out("hidutil mappings, apps and CLI, and moves the config to the Trash (it asks about fonts/config).")
        if !assumeYes {
            guard Console.stdinIsTerminal else {
                Console.error("not a terminal; re-run with --yes to proceed without confirmation.")
                return ExitCode.failed
            }
            Console.out("Run it now? [y/N] ", terminator: "")
            let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            guard answer == "y" || answer == "yes" else {
                Console.out("Cancelled.")
                return ExitCode.ok
            }
        }
        var args = [script.path]
        if assumeYes { args.append("--yes") }
        let status = Environment.runInteractive("/bin/sh", args)
        if status != 0 { Console.error("uninstall script exited with status \(status)") }
        return status == 0 ? ExitCode.ok : ExitCode.failed
    }

    /// SIP-off mode was used and SIP is not fully back on: say so here and open the reminder
    /// window (SkyRose Settings `--sip-reminder`). Never shown otherwise.
    func showSIPReminder() {
        Console.out("")
        Console.out("You used SkyRose's SIP-off mode. Turn System Integrity Protection back on from Recovery:")
        Console.out("  shut down, hold the power button, Options › Utilities › Terminal, `csrutil enable`, restart.")
        guard let url = Environment.settingsAppURL else { return }
        _ = Environment.run("/usr/bin/open", ["-n", "-a", url.path, "--args", "--sip-reminder"], timeout: 10)
    }

    /// Looks next to the app bundle first, then in the repository the CLI was built from.
    func locateScript() -> URL? {
        var candidates: [URL] = []
        if let app = Environment.wmAppURL {
            candidates.append(app.appendingPathComponent("Contents/Resources/scripts/uninstall.sh"))
            candidates.append(app.appendingPathComponent("Contents/Resources/uninstall.sh"))
        }
        if let repo = Environment.repositoryRoot {
            candidates.append(repo.appendingPathComponent("scripts/uninstall.sh"))
        }
        candidates.append(Paths.appSupport.appendingPathComponent("uninstall.sh"))
        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    func printManualSteps() {
        Console.error("scripts/uninstall.sh was not found next to the app or in a repository checkout.")
        Console.err("")
        Console.err("Get it from the repository (scripts/uninstall.sh) and run it with /bin/sh, or undo by hand:")
        Console.err("  1. Quit the WM: `skyrose wm quit` (restores every window first), or SkyRose Settings > Backup & uninstall.")
        Console.err("  2. Put back the macOS cursors: `skyrose cursor reset` (logging out also does it).")
        Console.err("  3. Restore backed-up settings from \(Environment.tilde(Paths.backupJournal)) (each entry lists domain, key and old value;")
        Console.err("     `defaults write`/`defaults delete` them back, and copy the saved symbolichotkeys plist over ~/Library/Preferences/).")
        Console.err("  4. Remove key remaps: `hidutil property --set '{\"UserKeyMapping\":[]}'`.")
        Console.err("  5. Remove the login item in System Settings > General > Login Items.")
        Console.err("  6. Delete ~/Applications/SkyRose.app, ~/Applications/SkyRose Settings.app and the `skyrose` symlink in ~/.local/bin or /usr/local/bin.")
        Console.err("  7. Move \(Environment.tilde(Paths.configDir)) and \(Environment.tilde(Paths.appSupport)) to the Trash.")
        Console.err("  8. Enhanced mode only: unload the scripting addition as described in docs/ENHANCED_MODE.md.")
    }
}

// MARK: migrate / settings

extension LocalCommands {
    /// `skyrose migrate`: the one-time move from the pre-rename folders (normally done by the WM
    /// on its first launch).
    static func migrate(json: Bool) -> Int32 {
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.caelestia.mac.wm" }
        let report = LegacyMigration().run(legacyWMRunning: running)
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            Console.out(String(decoding: (try? encoder.encode(report)) ?? Data(), as: UTF8.self))
        } else {
            switch report.outcome {
            case .nothingToDo: Console.out("Nothing to migrate: no Caelestia for Mac folders found.")
            case .alreadyDone: Console.out("Already migrated (see \(Environment.tilde(LegacyMigration().markerURL))).")
            case .skippedLegacyRunning: Console.out("CaelestiaWM is still running. Quit it first (caelestia wm quit), then run skyrose migrate.")
            case .migrated:
                Console.out("Migrated to SkyRose:")
                for m in report.moved { Console.out("  moved  \(m)") }
                for k in report.keptAside { Console.out("  kept   \(k)") }
                for n in report.notes { Console.out("  note   \(n)") }
            }
        }
        return report.outcome == .skippedLegacyRunning ? ExitCode.failed : ExitCode.ok
    }

    /// `skyrose settings` / `skyrose onboarding`.
    static func openSettings(onboarding: Bool) -> Int32 {
        guard let url = Environment.settingsAppURL else {
            Console.error("SkyRose Settings is not installed (no app with bundle id \(Environment.settingsBundleID)).")
            return ExitCode.failed
        }
        let launchArgs = onboarding ? OnboardingRequest.firstRun.arguments : []
        // Already running: `open --args` would drop the arguments, so ask the running app (the
        // same notification the WM uses), then bring it forward.
        if !NSRunningApplication.runningApplications(withBundleIdentifier: Environment.settingsBundleID).isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.skyrose.mac.settings.show"), object: nil,
                userInfo: ["arguments": launchArgs], deliverImmediately: true)
            return ExitCode.ok
        }
        var args = ["-a", url.path]
        if onboarding { args += ["--args"] + launchArgs }
        let r = Environment.run("/usr/bin/open", args, timeout: 10)
        if r.status != 0 { Console.error(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return r.status == 0 ? ExitCode.ok : ExitCode.failed
    }
}

// MARK: cursor

extension LocalCommands {
    /// `skyrose cursor …`: the session cursor theme. `set` writes `appearance.cursor` (the WM
    /// applies it); `reset` clears it and puts the macOS cursors back right here, so it also
    /// works when the WM is not running (uninstall).
    static func cursor(_ verb: CursorVerb, json: Bool) -> Int32 {
        let library = CursorCapeLibrary()
        switch verb {
        case .list:
            let capes = library.available()
            if capes.isEmpty { Console.out("No cursor capes found (looked in \(Environment.tilde(library.ownFolder)) and Mousecape's capes folder).") }
            for c in capes { Console.out("\(c.identifier)\t\(c.name)\t\(Environment.tilde(c.url))") }
            return ExitCode.ok
        case .status:
            let configured = ConfigLoader.loadUserOrDefault().config.appearance.cursor
            let backup = CursorBackupStore()
            Console.out("appearance.cursor: \(configured.isEmpty ? "\"\" (macOS cursors)" : configured)")
            Console.out("SkyRose cursors active this session: \(backup.exists ? "yes (reset restores the originals)" : "no")")
            Console.out("Wait (spinning) cursor: always macOS's; SkyRose never replaces it.")
            return ExitCode.ok
        case .set(let raw):
            let id = raw.lowercased() == "default" || raw.lowercased() == "macos" ? "" : raw
            if !id.isEmpty, library.url(for: id) == nil {
                Console.error("no cape named \(id); see `skyrose cursor list`.")
                return ExitCode.failed
            }
            do {
                try ConfigFileEditor.set("cursor", to: ConfigFileEditor.string(id), inTable: "appearance", file: Paths.configFile)
            } catch {
                Console.error("could not write \(Environment.tilde(Paths.configFile)): \(error.localizedDescription)")
                return ExitCode.failed
            }
            Console.out(id.isEmpty ? "appearance.cursor cleared; the WM puts the macOS cursors back." : "appearance.cursor = \(id); the WM applies it (not the wait cursor).")
            return ExitCode.ok
        case .reset:
            try? ConfigFileEditor.set("cursor", to: ConfigFileEditor.string(""), inTable: "appearance", file: Paths.configFile)
            let report = CursorThemeManager().reset()
            if report.ok {
                Console.out("macOS cursors restored (\(report.restored.count) put back).")
                return ExitCode.ok
            }
            Console.error("could not restore: \(report.failed.joined(separator: ", ")). Logging out restores every cursor.")
            return ExitCode.failed
        }
    }
}
