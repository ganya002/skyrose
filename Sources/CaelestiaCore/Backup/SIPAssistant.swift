import Foundation

/// One step of the SIP-off walkthrough. SkyRose never runs these. The user does, in Recovery or Terminal.
public struct SIPAssistantStep: Equatable, Sendable, Identifiable {
    public enum Place: String, Equatable, Sendable {
        case recovery, terminal, settings
    }

    public var id: String
    public var place: Place
    public var title: String
    public var detail: String
    /// A command the user copies. Nil when the step is a click or a key hold.
    public var command: String?

    public init(id: String, place: Place, title: String, detail: String, command: String? = nil) {
        self.id = id
        self.place = place
        self.title = title
        self.detail = detail
        self.command = command
    }
}

/// The steps for this Mac only. Apple Silicon includes the boot argument. Intel does not.
public enum SIPAssistant {
    public static let csrutilLower = "csrutil enable --without fs --without debug --without nvram"
    public static let csrutilFull = "csrutil enable"
    public static let bootArg = "sudo nvram boot-args=-arm64e_preview_abi"
    public static let clearBootArg = "sudo nvram -d boot-args"

    public static let risk = "This lowers the security of the Mac. With these protections off, other programs can inject code into Apple's apps. School and work Macs often forbid it. macOS updates can break the helper until it is rebuilt. SkyRose tiles, switches workspaces and draws its bar with SIP fully on. You do not need this."

    /// Enabling. `loader` is the sudo line Settings already shows, when the app is installed.
    public static func enable(appleSilicon: Bool, loader: String?) -> [SIPAssistantStep] {
        var steps = [
            SIPAssistantStep(id: "shutdown", place: .recovery, title: "Shut down", detail: "Shut the Mac down. Hold the power button until you see Loading startup options."),
            SIPAssistantStep(id: "options", place: .recovery, title: "Open Recovery", detail: "Choose Options, then Continue. In the menu bar: Utilities › Terminal."),
            SIPAssistantStep(id: "csrutil", place: .recovery, title: "Lower three protections", detail: "Paste this, press Return, then restart. It does not turn SIP all the way off.", command: csrutilLower),
        ]
        if appleSilicon {
            steps.append(SIPAssistantStep(id: "nvram", place: .terminal, title: "Allow the helper to run", detail: "After the Mac is back at the desktop, paste this in Terminal and restart again.", command: bootArg))
        }
        steps.append(SIPAssistantStep(id: "read", place: .settings, title: "Read what changes", detail: "Open SkyRose Settings › SIP-off mode and read “What changes with SIP off?” to the end."))
        if let loader {
            steps.append(SIPAssistantStep(id: "load", place: .terminal, title: "Load the helper", detail: "Once per boot, after you turn SIP-off mode on. It asks for your password and only loads SkyRose's helper into your Dock.", command: loader))
        }
        return steps
    }

    /// Putting SIP fully back on. The boot-argument step is only on Apple Silicon.
    public static func revert(appleSilicon: Bool) -> [SIPAssistantStep] {
        var steps = [
            SIPAssistantStep(id: "recovery", place: .recovery, title: "Turn the protections back on", detail: "Shut down, hold the power button, Options › Continue › Utilities › Terminal. Paste this and restart.", command: csrutilFull),
        ]
        if appleSilicon {
            steps.append(SIPAssistantStep(id: "clear", place: .terminal, title: "Remove the boot argument", detail: "At the desktop, paste this in Terminal and restart.", command: clearBootArg))
        }
        steps.append(SIPAssistantStep(id: "done", place: .settings, title: "SkyRose notices", detail: "This page turns the helper line off by itself. skyrose wm panic undoes any window change the helper made."))
        return steps
    }

    /// The commands, one per line, for a phone or a printout.
    public static func script(_ steps: [SIPAssistantStep]) -> String {
        steps.compactMap(\.command).joined(separator: "\n")
    }
}
