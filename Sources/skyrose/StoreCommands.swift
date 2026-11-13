import Foundation
import CaelestiaCore
import CaelestiaIPC

/// `skyrose store …` (docs/SKYSTORE.md). Installs are verified against the signed index; new
/// permissions need `--yes` or a "y" at the prompt.
extension LocalCommands {
    static func store(_ verb: StoreVerb, invocation: CLIInvocation, client: IPCClient) -> Int32 {
        let config = ConfigLoader.loadUserOrDefault().config.store
        let addons = AddonStore()
        addons.seedBuiltinFeatures()
        let creatorVerb: Bool
        switch verb {
        case .new, .validate, .pack, .submit: creatorVerb = true
        default: creatorVerb = false
        }
        if creatorVerb, !config.creatorMode {
            Console.error("creator mode is off. Turn it on in Settings › SkyStore › Creator mode (or: skyrose config set store.creatorMode true)")
            return ExitCode.failed
        }
        do {
            switch verb {
            case .list:
                let list = addons.installed()
                if invocation.json {
                    let rows: [JSONValue] = list.map {
                        .object(["id": .string($0.id), "name": .string($0.name), "version": .string($0.version), "kind": .string($0.kind.rawValue),
                                 "status": .string($0.status), "permissions": .array($0.permissions.map { .string($0) })])
                    }
                    Console.out(JSONValue.array(rows).prettyJSON)
                } else if list.isEmpty {
                    Console.out("No addons installed. Browse them with: skyrose store")
                } else {
                    for a in list {
                        Console.out([a.id.padding(toLength: 34, withPad: " ", startingAt: 0), a.version.padding(toLength: 10, withPad: " ", startingAt: 0),
                                     a.kind.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0), a.status].joined(separator: " "))
                    }
                }
            case .refresh:
                let index = try StoreSource.from(config).loadIndex()
                for a in addons.applyRevocations(index) { Console.out("revoked, switched off: \(a.name) (\(a.status))") }
                let updates = addons.updates(index)
                Console.out("\(index.addons.count) addon\(index.addons.count == 1 ? "" : "s") in the index; \(updates.count) update\(updates.count == 1 ? "" : "s")")
                for u in updates { Console.out("  \(u.installed.id) \(u.installed.version) → \(u.version.version)") }
            case .install(let id) where BuiltinFeature.named(id) != nil:
                let a = try addons.installBuiltin(id)
                Console.out("Installed \(a.name) (built into SkyRose, nothing downloaded).")
                reload(client)
            case .install(let id):
                let index = try StoreSource.from(config).loadIndex()
                guard let entry = index.entry(id) else { throw StoreError.notFound(id) }
                let a = try install(entry, addons: addons, config: config, yes: invocation.yes)
                Console.out("Installed \(a.name) \(a.version).\(hint(a.kind))")
                if a.kind == .app { try setup(a.id, addons: addons, json: invocation.json) }
                reload(client)
            case .update(let id):
                let index = try StoreSource.from(config).loadIndex()
                addons.applyRevocations(index)
                let updates = addons.updates(index).filter { id == nil || $0.installed.id == id }
                if updates.isEmpty { Console.out(id.map { "\($0) is up to date." } ?? "Everything is up to date.") }
                for u in updates {
                    let a = try install(u.entry, addons: addons, config: config, yes: invocation.yes)
                    Console.out("Updated \(a.name) \(u.installed.version) → \(a.version).")
                    if a.kind == .app { try setup(a.id, addons: addons, json: invocation.json) }
                }
                if !updates.isEmpty { reload(client) }
            case .uninstall(let id), .purge(let id):
                let purge = { if case .purge = verb { return true } else { return false } }()
                try addons.uninstall(id, purge: purge)
                Console.out("Removed \(id)\(purge ? " and its data" : "").")
                reload(client)
            case .setup(let id):
                try setup(id, addons: addons, json: invocation.json)
            case .enable(let id), .disable(let id):
                let on = { if case .enable = verb { return true } else { return false } }()
                try addons.setEnabled(id, on)
                Console.out("\(id) is \(on ? "on" : "off").")
                reload(client)
            case .new(let id, let kind):
                let dir = try AddonCreator.scaffold(id: id, kind: AddonKind(rawValue: kind) ?? .scheme,
                                                    in: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                Console.out("Created \(dir.path)")
                Console.out("Fill in author and summary in manifest.json, add your files, then: skyrose store validate \(dir.lastPathComponent)")
            case .validate(let path):
                let issues = AddonCreator.validate(folder(path))
                if issues.isEmpty { Console.out("OK: ready to pack."); return ExitCode.ok }
                for i in issues { Console.out("✗ \(i)") }
                return ExitCode.failed
            case .pack(let path):
                let p = try AddonCreator.pack(folder(path))
                Console.out("Packed \(p.bundle.path) (\(p.size) bytes)")
                Console.out("SHA-256 \(p.sha256)")
            case .submit(let path, let repo):
                guard let repo else {
                    Console.error("store submit needs --repo <owner/name>: your GitHub repo that will hold the bundle as a release asset")
                    return ExitCode.usage
                }
                let p = try AddonCreator.pack(folder(path))
                let s = try AddonCreator.submission(p, repo: repo)
                Console.out("1. Upload the bundle with your own gh login:")
                Console.out("   " + s.releaseCommand.map(shellQuote).joined(separator: " "))
                Console.out("2. Open the pre-filled pull request to \(AddonCreator.indexRepo) (GitHub forks it for you):")
                Console.out("   " + s.pullRequestURL.absoluteString)
                Console.out("A maintainer reviews every submission by hand before it is published.")
                guard invocation.yes else { Console.out("Run again with --yes to do both now."); return ExitCode.ok }
                guard let gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first(where: FileManager.default.isExecutableFile) else {
                    Console.error("gh not found: run step 1 yourself, or upload the two files on GitHub's release page")
                    return ExitCode.failed
                }
                let r = Environment.run(gh, Array(s.releaseCommand.dropFirst()), timeout: 300)
                guard r.status == 0 else { Console.error("gh release create failed: \(r.stderr.isEmpty ? r.stdout : r.stderr)"); return ExitCode.failed }
                _ = Environment.run("/usr/bin/open", [s.pullRequestURL.absoluteString])
            }
            return ExitCode.ok
        } catch {
            Console.error((error as? LocalizedError)?.errorDescription ?? "\(error)")
            return ExitCode.failed
        }
    }

    private static func install(_ entry: StoreEntry, addons: AddonStore, config: StoreConfig, yes: Bool) throws -> InstalledAddon {
        try addons.install(entry, source: StoreSource.from(config), approve: { diff in
            Console.out("\(entry.name) asks for:")
            for p in diff.added { Console.out("  + \(p.summary)") }
            for p in diff.removed { Console.out("  − \(p.summary) (no longer)") }
            if yes { return true }
            guard Console.stdinIsTerminal else { Console.err("Run again with --yes to allow."); return false }
            Console.out("Allow? [y/N] ", terminator: "")
            return readLine()?.lowercased().hasPrefix("y") == true
        }, progress: { p in if p.step != .done { Console.err("\(p.step.rawValue)…") } })
    }

    /// Runs `AppInstaller` here, in the CLI process (never in the WM). `json`: one
    /// `AppSetupEvent` per line on stdout, for the Store drawer.
    private static func setup(_ id: String, addons: AddonStore, json: Bool) throws {
        var last = ""
        let installer = AppInstaller(store: addons) { e in
            if json { Console.out(e.jsonLine); return }
            let line = "\(e.title)\(e.detail.map { " · \($0)" } ?? "")"
            guard line != last else { return }
            last = line
            if e.step == .download, e.bytes != nil, Console.stdinIsTerminal {
                FileHandle.standardError.write(Data("\r\u{1B}[2K  \(line)".utf8))
            } else {
                Console.err("  \(line)")
            }
        }
        let app = try installer.setup(id)
        if !json { Console.out("Ready: \(app.path)") }
    }

    private static func hint(_ kind: AddonKind) -> String {
        switch kind {
        case .scheme: return " Pick it in Settings › Appearance."
        case .wallpaper: return " It is in the wallpaper picker."
        case .app: return " Setting it up (checks, pinned downloads, build)…"
        default: return ""
        }
    }

    private static func folder(_ path: String?) -> URL {
        URL(fileURLWithPath: CLIParser.absolutePath(path ?? "."), isDirectory: true)
    }

    /// The running SkyRose re-reads its config, so a changed scheme addon shows at once.
    private static func reload(_ client: IPCClient) {
        _ = try? client.send(IPCRequest(.configReload), timeout: 2)
    }

    static func shellQuote(_ s: String) -> String {
        s.allSatisfy({ $0.isLetter || $0.isNumber || "-_./:=@".contains($0) }) ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
