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
            return Doctor(client: client, json: invocation.json, fix: invocation.fix).run()
        case .uninstall(let flags):
            return Uninstaller(assumeYes: invocation.yes, flags: flags, client: client).run()
        case .shellStart:
            return ShellStarter(client: client, timeout: invocation.timeout ?? 15).run()
        case .restart:
            return Restarter(client: client, timeout: invocation.timeout ?? 15).run()
        case .shellTargets(let target):
            Console.out(CLIParser.shellTargetsHelp(target: target), terminator: "")
            return ExitCode.ok
        case .migrate:
            return migrate(json: invocation.json)
        case .openSettings(let onboarding):
            return openSettings(onboarding: onboarding)
        case .cursor(let verb):
            return cursor(verb, json: invocation.json)
        case .dock(let verb):
            return dock(verb)
        case .update(let checkOnly):
            return update(checkOnly: checkOnly || !invocation.yes)
        case .kitty(let verb):
            return kitty(verb, json: invocation.json)
        case .fonts(let verb):
            return fonts(verb, json: invocation.json)
        case .sa(let verb):
            return sa(verb, json: invocation.json)
        case .store(let verb):
            return store(verb, invocation: invocation, client: client)
        }
    }

    // MARK: SIP-off scripting addition

    /// The loader inside the SkyRose.app this CLI belongs to (else the installed one).
    static var saLoader: URL? {
        let exe = Bundle.main.executableURL?.resolvingSymlinksInPath()
        let app = exe?.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return SAClient.bundledLoader(appBundle: app?.pathExtension == "app" ? app : Environment.wmAppURL)
    }

    /// `skyrose sa status | load-command | reload | reset`.
    static func sa(_ verb: SAVerb, json: Bool) -> Int32 {
        let client = SAClient()
        let hello = client.connect()
        switch verb {
        case .status:
            let sip = SIPOffReadiness.current()
            let config = ConfigLoader.loadUserOrDefault().config
            var rows: [(String, String)] = [
                ("scripting addition", hello.map { "loaded (v\($0.version): \($0.capabilities.names.joined(separator: ", ")))" } ?? "not loaded"),
                ("sipOff.enabled", config.sipOff.enabled ? "true" : "false (Settings › SIP-off mode)"),
                ("SIP", sip.summary),
                ("socket", SAClient.socketPath()),
            ]
            if hello == nil, let loader = saLoader { rows.append(("load with", SAProtocol.loadCommand(loader: loader))) }
            var boot = SAClient.daemonInstalled ? "installed" : "not installed"
            if SAClient.daemonInstalled, let loader = saLoader,
               !FileManager.default.contentsEqual(atPath: loader.path, andPath: SAClient.daemonLoader.path) {
                boot += " (older than this SkyRose: run its install command again)"
            }
            rows.append(("boot daemon", boot))
            if json {
                Console.out(JSONValue.object(Dictionary(rows.map { ($0.0, JSONValue.string($0.1)) }, uniquingKeysWith: { a, _ in a })).prettyJSON)
            } else {
                for (k, v) in rows { Console.out("\(k.padding(toLength: 20, withPad: " ", startingAt: 0)) \(v)") }
            }
            return ExitCode.ok
        case .loadCommand:
            guard let loader = saLoader else {
                Console.error("skyrose-sa-loader not found in SkyRose.app (rebuild with scripts/build.sh)")
                return ExitCode.failed
            }
            Console.out(SAProtocol.loadCommand(loader: loader))
            return ExitCode.ok
        case .reload:
            let loader = SAClient.daemonInstalled ? SAClient.daemonLoader : saLoader
            guard let loader else {
                Console.error("skyrose-sa-loader not found in SkyRose.app (rebuild with scripts/build.sh)")
                return ExitCode.failed
            }
            if hello != nil { Console.err("scripting addition is already loaded; loading it twice is not safe") ; return ExitCode.failed }
            Console.err("Run this to load the helper again without a reboot:")
            Console.out(SAProtocol.loadCommand(loader: loader))
            return ExitCode.ok
        case .reset:
            guard hello != nil else {
                Console.out("scripting addition not loaded: nothing to reset")
                return ExitCode.ok
            }
            return client.reset() ? ExitCode.ok : ExitCode.failed
        }
    }

    /// `wm panic` also talks to the SA directly (works when the WM hangs or is gone): undo every
    /// window change and close its socket.
    static func neutraliseScriptingAddition() {
        FileManager.default.createFile(atPath: SAClient.pausePath(), contents: nil)
        let client = SAClient()
        guard client.connect() != nil else { return }
        _ = client.reset()
        _ = client.stop()
        Console.err("scripting addition: every window change undone, socket closed")
    }

    // MARK: fonts

    /// `skyrose fonts status | download | install | uninstall`.
    static func fonts(_ verb: FontsVerb, json: Bool) -> Int32 {
        let store = FontStore()
        var notes: [String] = []
        do {
            switch verb {
            case .status: break
            case .download:
                let box = ResultBox()
                let sem = DispatchSemaphore(value: 0)
                Task.detached {
                    do { box.set(.success(try await store.download())) } catch { box.set(.failure(error)) }
                    sem.signal()
                }
                sem.wait()
                notes = try box.get().map { "downloaded \($0)" }
                if notes.isEmpty { notes = ["already downloaded"] }
                notes.append("the WM picks them up on its next start or `skyrose config reload`")
            case .install:
                notes = try store.installForUser(journal: BackupJournal())
            case .uninstall:
                notes = try store.uninstallUser()
            }
        } catch {
            Console.error((error as? LocalizedError)?.errorDescription ?? String(describing: error))
            return ExitCode.failed
        }
        let status = store.status()
        if json {
            let families: [JSONValue] = status.map { s in
                .object(["name": .string(s.name), "downloaded": .bool(s.downloaded), "installedBySkyRose": .bool(s.installedBySkyRose),
                         "availableSystemWide": .bool(s.availableSystemWide)])
            }
            Console.out(JSONValue.object(["families": .array(families), "notes": .array(notes.map { .string($0) }),
                                          "cache": .string(store.cacheDirectory.path)]).prettyJSON)
        } else {
            for n in notes { Console.out(n) }
            for (s, f) in zip(status, FontPack.families) {
                let state = s.installedBySkyRose ? "installed by SkyRose (~/Library/Fonts)"
                    : s.availableSystemWide ? "installed (not by SkyRose)" : s.downloaded ? "downloaded (SkyRose only)" : "not downloaded"
                Console.out(s.name.padding(toLength: 26, withPad: " ", startingAt: 0) + f.licence.padding(toLength: 13, withPad: " ", startingAt: 0) + state)
            }
        }
        return ExitCode.ok
    }

    /// Hands an async result back to the synchronous CLI.
    final class ResultBox: @unchecked Sendable {
        private var value: Result<[String], Error> = .success([])
        private let lock = NSLock()
        func set(_ v: Result<[String], Error>) { lock.withLock { value = v } }
        func get() throws -> [String] { try lock.withLock { value }.get() }
    }

    // MARK: kitty

    /// `skyrose kitty status | install | uninstall`.
    static func kitty(_ verb: KittyVerb, json: Bool) -> Int32 {
        let setup = KittySetup()
        do {
            var notes: [String] = []
            switch verb {
            case .status: break
            case .install:
                let scheme = (try? SchemeLoader.load(from: Paths.currentScheme))
                    ?? SchemeLoader.builtIn(named: "skyrose-dynamic") ?? SchemeLoader.builtIn(named: "skyrose-default")
                guard let scheme else { Console.error("no colour scheme to write"); return ExitCode.failed }
                let apps = ConfigLoader.loadUserOrDefault().config.apps
                notes = try setup.install(scheme: scheme, options: apps.kittyOptions, journal: BackupJournal())
            case .uninstall:
                notes = try setup.uninstall()
            }
            if verb != .status, !notes.isEmpty {
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: TerminalChoice.kittyBundleID) where app.processIdentifier > 0 {
                    kill(app.processIdentifier, SIGUSR1)
                }
            }
            let s = setup.status()
            if json {
                let o: [String: JSONValue] = [
                    "included": .bool(s.included), "kittyConf": .bool(s.kittyConfExists), "profile": .bool(s.profileWritten),
                    "theme": .bool(s.themeWritten), "foreignFile": s.foreignFile.map { .string($0) } ?? .null,
                    "directory": .string(setup.directory.path), "notes": .array(notes.map { .string($0) }),
                ]
                Console.out(JSONValue.object(o).prettyJSON)
            } else {
                for n in notes { Console.out(n) }
                Console.out("kitty profile: \(s.included ? "in use (kitty.conf includes \(KittyProfile.fileName))" : "not in use")")
                Console.out("  \(setup.profileFile.path): \(s.profileWritten ? "written by SkyRose" : "missing")")
                Console.out("  \(setup.themeFile.path): \(s.themeWritten ? "written by SkyRose (follows the scheme)" : "missing")")
                if let f = s.foreignFile { Console.out("  \(f) was not written by SkyRose: install refuses to overwrite it") }
            }
            return ExitCode.ok
        } catch {
            Console.err((error as? LocalizedError)?.errorDescription ?? String(describing: error))
            return ExitCode.failed
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
        // By path: `open -b` may pick another account's copy.
        let launch = Environment.run("/usr/bin/open", ["--background", app.path], timeout: 30)
        guard launch.status == 0 else {
            Console.error("`open \(app.path)` failed (\(launch.status)): \(launch.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
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

/// `skyrose restart`: quit the WM (it restores every window first), wait until every SkyRose
/// process is gone, then start this CLI's own SkyRose.app. Not running: just start it. The SIP-off
/// helper lives in the Dock, so it stays loaded and the new WM reconnects to it.
struct Restarter {
    let client: IPCClient
    let timeout: TimeInterval

    func run() -> Int32 {
        guard Environment.wmAppURL != nil else { return ShellStarter(client: client, timeout: timeout).run() }
        let running = { NSRunningApplication.runningApplications(withBundleIdentifier: SkyRoseApp.bundleID).filter { !$0.isTerminated } }
        if !running().isEmpty {
            Console.out("Stopping SkyRose …")
            if (try? client.send(IPCRequest(.wmQuit), timeout: 5)) == nil {
                // No answer (hung or IPC gone): ask politely; never force-kill, its windows need restoring.
                running().forEach { $0.terminate() }
            }
            let deadline = Date().addingTimeInterval(20)
            while !running().isEmpty, Date() < deadline { usleep(200_000) }
            if let left = running().first {
                Console.error("SkyRose (pid \(left.processIdentifier)) did not quit within 20 s.")
                Console.err("Run `skyrose wm panic`, then `skyrose restart` again.")
                return ExitCode.failed
            }
        }
        return ShellStarter(client: client, timeout: timeout).run()
    }
}

/// `skyrose uninstall` (spec 10.5): runs `scripts/uninstall.sh` when it can be found, otherwise
/// prints the manual steps. The script is the single source of truth so it also works when the app
/// is already gone.
struct Uninstaller {
    let assumeYes: Bool
    var flags: [String] = []
    let client: IPCClient

    func run() -> Int32 {
        guard let script = locateScript() else {
            // Without the script the reminder is shown here (the script shows it itself, before it
            // moves Application Support to the Trash).
            if RestoreManifest().mustShowSIPReminder(csrutilStatus: SIPStatus.readCSRUtil()) { showSIPReminder() }
            printManualSteps()
            return ExitCode.failed
        }
        Console.out("Uninstall script: \(Environment.tilde(script))")
        let dryRun = flags.contains("--dry-run")
        if !assumeYes, !dryRun, !Console.stdinIsTerminal {
            Console.error("not a terminal; re-run with --yes to proceed without questions (or --dry-run to look first).")
            return ExitCode.failed
        }
        // The script asks for confirmation itself (and about fonts, config and the certificate).
        var args = [script.path] + flags
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
        // The app this CLI runs from (…/SkyRose.app/Contents/MacOS/skyrose), then the installed one.
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            candidates.append(exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/scripts/uninstall.sh"))
        }
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
        Console.err("     Remove the kitty profile (the include line in kitty.conf and our two files): `skyrose kitty uninstall`.")
        Console.err("     Remove the fonts SkyRose copied into ~/Library/Fonts: `skyrose fonts uninstall`.")
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
    /// `skyrose update`: compare with the latest GitHub release. Without `--yes` it only reports.
    /// A bad checksum or no network keeps the current install. Never downgrades.
    static func update(checkOnly: Bool) -> Int32 {
        let json: Data
        if let path = ProcessInfo.processInfo.environment["SKYROSE_UPDATE_JSON"], !path.isEmpty {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                Console.error("offline: the release list could not be read. Keeping SkyRose \(CaelestiaVersion.string).")
                return ExitCode.failed
            }
            json = data
        } else {
            var request = URLRequest(url: Updater.releaseAPI)
            request.timeoutInterval = 20
            let box = UpdateBox()
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: request) { data, _, _ in box.data = data; sem.signal() }.resume()
            if sem.wait(timeout: .now() + 25) == .timedOut || box.data == nil {
                Console.error("offline: no network. Keeping SkyRose \(CaelestiaVersion.string).")
                return ExitCode.failed
            }
            json = box.data ?? Data()
        }
        switch Updater.plan(current: CaelestiaVersion.string, json: json) {
        case .upToDate:
            Console.out("SkyRose \(CaelestiaVersion.string) is up to date.")
            return ExitCode.ok
        case .newerInstalled(let tag):
            Console.out("SkyRose \(CaelestiaVersion.string) is newer than \(tag). Not downgrading.")
            return ExitCode.ok
        case .unreadable(let why):
            Console.error("\(why) Keeping SkyRose \(CaelestiaVersion.string).")
            return ExitCode.failed
        case .update(let tag, let zipURL, let shaURL):
            Console.out("SkyRose \(tag) is available (installed: \(CaelestiaVersion.string)).")
            if checkOnly { return ExitCode.ok }
            return installUpdate(tag: tag, zip: zipURL, checksum: shaURL)
        }
    }

    private static func installUpdate(tag: String, zip: URL, checksum: URL) -> Int32 {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("skyrose-update-\(UUID().uuidString)", isDirectory: true)
        let zipFile = work.appendingPathComponent("SkyRose.zip")
        let shaFile = work.appendingPathComponent("SkyRose.zip.sha256")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try fetch(zip, to: zipFile)
            try fetch(checksum, to: shaFile)
        } catch {
            Console.error("The download failed (\(error.localizedDescription)). Keeping SkyRose \(CaelestiaVersion.string).")
            return ExitCode.failed
        }
        guard Updater.checksumMatches(file: zipFile, shaFile: shaFile) else {
            Console.error("SHA-256 did not match. Keeping SkyRose \(CaelestiaVersion.string).")
            return ExitCode.failed
        }
        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        let unpack = Process()
        unpack.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unpack.arguments = ["-x", "-k", zipFile.path, unpacked.path]
        do { try unpack.run() } catch {
            Console.error("Could not open the zip. Keeping SkyRose \(CaelestiaVersion.string).")
            return ExitCode.failed
        }
        unpack.waitUntilExit()
        guard unpack.terminationStatus == 0 else {
            Console.error("Could not open the zip. Keeping SkyRose \(CaelestiaVersion.string).")
            return ExitCode.failed
        }
        let script = unpacked.appendingPathComponent("install.sh")
        guard FileManager.default.isReadableFile(atPath: script.path) else {
            Console.error("The release has no install.sh. Keeping SkyRose \(CaelestiaVersion.string).")
            return ExitCode.failed
        }
        // The release's own install.sh, in update mode: keep config, the journal and wallpapers.
        let status = Environment.run("/bin/sh", [script.path, "--update", "--payload", unpacked.path, "--yes"], timeout: 180)
        if status.status != 0 {
            let why = status.stderr.isEmpty ? status.stdout : status.stderr
            Console.error(why.isEmpty ? "The update did not finish. Keeping SkyRose \(CaelestiaVersion.string)." : why)
        }
        return status.status == 0 ? ExitCode.ok : ExitCode.failed
    }

    private static func fetch(_ url: URL, to dest: URL) throws {
        if url.isFileURL {
            try FileManager.default.copyItem(at: url, to: dest)
            return
        }
        let box = UpdateBox()
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: url) { data, _, _ in box.data = data; sem.signal() }.resume()
        guard sem.wait(timeout: .now() + 120) == .success, let data = box.data, !data.isEmpty else {
            throw CocoaError(.fileReadUnknown)
        }
        try data.write(to: dest, options: .atomic)
    }

    /// `skyrose dock …`: hide the Dock without unloading it. `hide` journals the old values first.
    static func dock(_ verb: DockVerb) -> Int32 {
        let removal = DockRemoval()
        switch verb {
        case .status:
            Console.out(removal.isHidden() ? "hidden (the Dock process is still running)" : "shown")
            return ExitCode.ok
        case .hide:
            do { try removal.hide() } catch {
                Console.error("could not hide the Dock: \(error)")
                return ExitCode.failed
            }
            Console.out("Dock hidden. Mission Control and Spaces still work. `skyrose dock show` puts your old Dock back.")
            return ExitCode.ok
        case .show:
            do { try removal.show() } catch {
                Console.error("could not show the Dock: \(error)")
                return ExitCode.failed
            }
            Console.out("Dock shown again.")
            return ExitCode.ok
        }
    }

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

private final class UpdateBox: @unchecked Sendable {
    var data: Data?
}
