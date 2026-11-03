import Foundation
import CaelestiaCore
import CaelestiaIPC

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
        }
    }

    // MARK: version

    /// `caelestia version`: CLI version, plus the WM's when it answers.
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
        Console.out("caelestia \(CaelestiaVersion.string) (protocol \(CaelestiaVersion.protocolVersion))")
        if let h = hello {
            let match = h.protocolVersion == CaelestiaVersion.protocolVersion ? "" : "  (protocol mismatch: restart the WM)"
            Console.out("Caelestia WM \(h.version) (protocol \(h.protocolVersion), pid \(h.pid))\(match)")
        } else {
            Console.out("Caelestia WM not running")
        }
        return ExitCode.ok
    }

    // MARK: keys check

    /// `caelestia keys check`: the section 3.3 conflict checker on the user keymap. Exit 1 when
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

    /// `caelestia keys list`: every bind in the user keymap with its Mac chord.
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

/// `caelestia shell -d`: start the WM app (which hosts the shell) and wait for its socket.
struct ShellStarter {
    let client: IPCClient
    let timeout: TimeInterval

    func run() -> Int32 {
        if let h = try? client.hello(timeout: 1) {
            Console.out("Caelestia WM already running (pid \(h.pid), version \(h.version))")
            return ExitCode.ok
        }
        guard let app = Environment.wmAppURL else {
            Console.error("Caelestia WM is not installed (no app with bundle id \(Environment.wmBundleID)).")
            Console.err("")
            Console.err("Install it from a clone of the repository:")
            Console.err("    ./scripts/install.sh          # builds, copies the apps to ~/Applications, sets up the login item")
            Console.err("or build without installing:")
            Console.err("    ./scripts/build.sh && open .build/release/CaelestiaWM.app")
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
                Console.out("Caelestia WM \(h.version) running (pid \(h.pid))\(mismatch)")
                return ExitCode.ok
            }
            usleep(200_000)
        }
        Console.error("the app launched but no IPC socket appeared at \(Environment.tilde(client.path)) within \(Int(timeout)) s.")
        Console.err("Check Console.app for 'com.caelestia.mac' messages, or run `caelestia doctor`.")
        return ExitCode.failed
    }
}

/// `caelestia uninstall` (spec 10.5): runs `scripts/uninstall.sh` when it can be found, otherwise
/// prints the manual steps. The script is the single source of truth so it also works when the app
/// is already gone.
struct Uninstaller {
    let assumeYes: Bool
    let client: IPCClient

    func run() -> Int32 {
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
        Console.err("  1. Quit the WM: `caelestia wm quit` (restores every window first), or Caelestia Settings > Backup & uninstall.")
        Console.err("  2. Restore backed-up settings from \(Environment.tilde(Paths.backupJournal)) (each entry lists domain, key and old value;")
        Console.err("     `defaults write`/`defaults delete` them back, and copy the saved symbolichotkeys plist over ~/Library/Preferences/).")
        Console.err("  3. Remove key remaps: `hidutil property --set '{\"UserKeyMapping\":[]}'`.")
        Console.err("  4. Remove the login item in System Settings > General > Login Items.")
        Console.err("  5. Delete ~/Applications/CaelestiaWM.app, ~/Applications/Caelestia Settings.app and the `caelestia` symlink in ~/.local/bin or /usr/local/bin.")
        Console.err("  6. Move \(Environment.tilde(Paths.configDir)) and \(Environment.tilde(Paths.appSupport)) to the Trash.")
        Console.err("  7. Enhanced mode only: unload the scripting addition as described in docs/ENHANCED_MODE.md.")
    }
}
