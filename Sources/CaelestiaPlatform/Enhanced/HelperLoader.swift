import Foundation
import Security

/// Loads the SIP-off helper behind the standard macOS administrator prompt (no Terminal).
///
/// The password goes to macOS (`do shell script … with administrator privileges`), never to
/// SkyRose. Root never runs a file the user can change: the whole app is copied into a fresh
/// root-only folder, that copy's signature is checked against the running app's own designated
/// requirement, and only then is the copied loader run. With `installDaemon` the boot daemon's
/// installer runs from the same verified copy.
public enum HelperLoader {
    public enum Outcome: Equatable, Sendable {
        case loaded
        /// The user closed the password prompt.
        case cancelled
        case failed(String)
    }

    /// The shell script root runs. Pure, so tests can check every path is quoted and validated.
    public static func script(app: URL, uid: uid_t, requirement: String, installDaemon: Bool) -> String {
        let q = SAProtocol.shellQuote
        let socket = SAClient.socketPath(uid: uid)
        let lines = [
            "set -eu",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
            "APP=\(q(app.path))",
            "case \"$APP\" in /*.app) ;; *) echo 'not an app bundle' >&2; exit 64 ;; esac",
            "[ -d \"$APP\" ] && [ ! -L \"$APP\" ] || { echo 'SkyRose.app is missing' >&2; exit 66; }",
            // A root-owned folder the user can read (the Dock runs as the user and must open the
            // dylib) but not write. ditto as root keeps the user as owner, so take the copy over.
            "STAGE=$(mktemp -d /private/var/tmp/skyrose-helper.XXXXXX)",
            "trap 'rm -rf \"$STAGE\"' EXIT",
            "ditto \"$APP\" \"$STAGE/SkyRose.app\"",
            "chown -R root:wheel \"$STAGE\"",
            "chmod -R go-w \"$STAGE\"",
            "chmod 755 \"$STAGE\"",
            "codesign --verify --strict -R=\(q(requirement)) \"$STAGE/SkyRose.app\" || { echo 'the app signature does not match the running SkyRose' >&2; exit 65; }",
            "SA=\"$STAGE/SkyRose.app/Contents/Resources/sa\"",
            "if nc -z -U \(q(socket)) 2>/dev/null; then echo 'already loaded'; else SUDO_UID=\(uid) \"$SA/skyrose-sa-loader\"; fi",
            // The loader returns once the Dock's thread starts; keep the staged dylib until it answers.
            "i=0; until nc -z -U \(q(socket)) 2>/dev/null; do i=$((i + 1)); [ $i -lt 50 ] || { echo 'the helper did not answer within 5 seconds' >&2; exit 70; }; sleep 0.1; done",
        ] + (installDaemon ? ["SUDO_UID=\(uid) /bin/sh \"$SA/install-sa-daemon.sh\""] : [])
        return lines.joined(separator: "\n")
    }

    /// AppleScript source for `script`: the text as one string literal, escaped for AppleScript.
    public static func appleScript(_ shell: String, prompt: String) -> String {
        func lit(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return "do shell script \(lit(shell)) with prompt \(lit(prompt)) with administrator privileges"
    }

    /// The running app's designated requirement, e.g. `identifier "com.skyrose.mac" and certificate root = H"…"`.
    public static func ownRequirement() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var req: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &req) == errSecSuccess, let req else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(req, [], &text) == errSecSuccess, let text else { return nil }
        return text as String
    }

    /// Shows the admin prompt and runs the script. Blocks: call it off the main thread.
    public static func run(app: URL, installDaemon: Bool) -> Outcome {
        guard let req = ownRequirement() else { return .failed("SkyRose could not read its own signature.") }
        let source = appleScript(script(app: app, uid: getuid(), requirement: req, installDaemon: installDaemon),
                                 prompt: "SkyRose wants to load its SIP-off helper into the Dock.")
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return .loaded }
        if (error[NSAppleScript.errorNumber] as? Int) == -128 { return .cancelled }
        let message = (error[NSAppleScript.errorMessage] as? String) ?? "The helper did not load."
        return .failed(humanReason(message))
    }

    /// The last line of the script's error output, without AppleScript's prefix.
    public static func humanReason(_ raw: String) -> String {
        let line = raw.split(whereSeparator: \.isNewline).last.map(String.init) ?? raw
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "The helper did not load." : trimmed
    }
}
