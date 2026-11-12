import Darwin
import Foundation
import CaelestiaIPC

/// `skyrose wifi …`: the WM does the Wi-Fi work (it has the Location permission); this asks it,
/// then polls until a scan, join or forget is done. Passwords come from stdin or a hidden prompt,
/// go to the WM once, and are never printed or kept.
struct WifiCommand {
    let client: IPCClient
    let json: Bool
    let timeout: TimeInterval?

    func run(_ verb: WifiVerb) -> Int32 {
        switch verb {
        case .status: return finish(call(["action": .string("status")]))
        case .on: return finish(call(["action": .string("on")]))
        case .off: return finish(call(["action": .string("off")]))
        case .disconnect: return finish(call(["action": .string("disconnect")]))
        case .scan:
            guard call(["action": .string("scan")]) != nil else { return ExitCode.failed }
            return finish(wait { $0["scanning"]?.boolValue != true }, networks: true)
        case .forget(let ssid):
            guard call(["action": .string("forget"), "ssid": .string(ssid)]) != nil else { return ExitCode.failed }
            Console.err("macOS asks for an administrator to change known networks…")
            let s = wait(limit: 120) { Self.jobState($0) != "forgetting" }
            return finish(s, failedIf: "failed")
        case .connect(let ssid, let fromStdin):
            var password: String?
            if fromStdin {
                password = readLine(strippingNewline: true)
                guard let p = password, !p.isEmpty else { Console.error("no password on stdin"); return ExitCode.usage }
            }
            var s = join(ssid, password)
            if password == nil, s.map(Self.jobState) == "failed", s?["job"]?["message"]?.stringValue == Self.needsPassword {
                guard isatty(STDIN_FILENO) == 1, let p = Self.prompt("Password for \(ssid): "), !p.isEmpty else {
                    Console.error("\(ssid) needs a password: use --password-stdin")
                    return ExitCode.failed
                }
                s = join(ssid, p)
            }
            return finish(s, failedIf: "failed")
        }
    }

    /// Same text as `NetworkService.needsPassword`.
    static let needsPassword = "This network needs a password."

    private func join(_ ssid: String, _ password: String?) -> JSONValue? {
        var args: [String: JSONValue] = ["action": .string("connect"), "ssid": .string(ssid)]
        if let password { args["password"] = .string(password) }
        guard call(args) != nil else { return nil }
        return wait(limit: 45) { Self.jobState($0) != "connecting" }
    }

    static func jobState(_ v: JSONValue) -> String { v["job"]?["state"]?.stringValue ?? "idle" }

    private func call(_ args: [String: JSONValue]) -> JSONValue? {
        do {
            let r = try client.send(IPCRequest(.wifi, args: args), timeout: timeout ?? 5)
            guard r.ok else { Console.error(r.error ?? "wifi failed"); return nil }
            return r.result
        } catch let e as IPCError {
            _ = CLIApp.report(e)
            return nil
        } catch {
            Console.error(error.localizedDescription)
            return nil
        }
    }

    /// Polls `status` (4×/s) until `done` or `limit` seconds.
    private func wait(limit: TimeInterval = 20, _ done: (JSONValue) -> Bool) -> JSONValue? {
        let end = Date().addingTimeInterval(limit)
        var last: JSONValue?
        repeat {
            usleep(250_000)
            last = call(["action": .string("status")])
            if let s = last, done(s) { return s }
        } while last != nil && Date() < end
        if last != nil { Console.error("timed out") }
        return last
    }

    private func finish(_ v: JSONValue?, networks: Bool = false, failedIf state: String? = nil) -> Int32 {
        guard let v else { return ExitCode.failed }
        if json {
            Console.out(v.prettyJSON)
        } else {
            Console.out(Self.render(v, networks: networks), terminator: "")
        }
        if let state, Self.jobState(v) == state { return ExitCode.failed }
        return ExitCode.ok
    }

    static func render(_ v: JSONValue, networks: Bool) -> String {
        var out = ""
        let on = v["enabled"]?.boolValue == true
        if v["ethernet"]?.boolValue == true { out += "Ethernet connected\n" }
        if !on {
            out += "Wi-Fi off\n"
        } else if v["connected"]?.boolValue == true {
            out += "Connected to: \(v["ssid"]?.stringValue ?? "(name hidden: Location)")\n"
            out += "Strength: \(Int(v["strength"]?.doubleValue ?? 0))/100\n"
            if let f = v["frequency"]?.doubleValue { out += "Frequency: \(Int(f)) MHz\n" }
        } else {
            out += "Wi-Fi on, not connected\n"
        }
        switch jobState(v) {
        case "connected": out += "Joined \(v["job"]?["ssid"]?.stringValue ?? "")\n"
        case "failed": out += "Failed: \(v["job"]?["message"]?.stringValue ?? "")\n"
        default: break
        }
        if networks {
            if let m = v["scanMessage"]?.stringValue { out += m + "\n" }
            for n in v["networks"]?.arrayValue ?? [] {
                let flags = [n["current"]?.boolValue == true ? "connected" : nil, n["known"]?.boolValue == true ? "known" : nil,
                             n["secured"]?.boolValue == true ? "secured" : "open"].compactMap { $0 }
                let name = n["ssid"]?.stringValue ?? ""
                out += "  " + name.padding(toLength: max(24, name.count), withPad: " ", startingAt: 0)
                    + String(format: " %3d/100  ", Int(n["strength"]?.doubleValue ?? 0)) + flags.joined(separator: ", ") + "\n"
            }
        }
        return out
    }

    /// Reads a line from the terminal without echo.
    static func prompt(_ text: String) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        guard let r = readpassphrase(text, &buf, buf.count, 0) else { return nil }
        let s = String(cString: r)
        buf.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) }
        return s
    }
}
