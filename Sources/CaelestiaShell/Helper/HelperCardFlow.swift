import Foundation

/// The "Finish hiding the menu bar" card: when it shows and what it shows.
public struct HelperCardFlow: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case hidden
        case offer
        /// The macOS password prompt is up (or root is running the loader).
        case waitingForPassword
        /// Root finished; waiting for SkyRose to see the helper answer.
        case loading
        case success
        case failed(String)
        /// "Do it in Terminal instead": the command and a Copy button.
        case terminal
    }

    public enum Event: Equatable, Sendable {
        /// SIP-off mode is on and the helper is not loaded (or no longer needed).
        case needed(Bool)
        /// Settings or `skyrose sa enable` asked for the card, even after "Not now".
        case requested
        case enable
        case notNow
        case passwordCancelled
        case rootFinished
        case rootFailed(String)
        case helperActive
        case showTerminal
        case backFromTerminal
        /// The success checkmark has been seen; the card goes.
        case dismissAfterSuccess
    }

    public private(set) var phase: Phase = .hidden
    /// "Not now" holds until the app restarts or the card is asked for.
    public private(set) var snoozed = false
    /// "Do this automatically every restart" (off by default).
    public var installDaemon = false

    public init() {}

    public var isVisible: Bool { phase != .hidden }
    /// True while macOS or root is busy; the buttons are disabled.
    public var isBusy: Bool { phase == .waitingForPassword || phase == .loading }

    public mutating func handle(_ event: Event) {
        switch (event, phase) {
        case (.needed(true), .hidden):
            if !snoozed { phase = .offer }
        case (.needed(false), .offer), (.needed(false), .terminal), (.needed(false), .failed):
            phase = .hidden
        case (.needed, _):
            break
        case (.requested, .hidden), (.requested, .failed):
            snoozed = false
            phase = .offer
        case (.requested, _):
            break
        case (.enable, .offer), (.enable, .failed), (.enable, .terminal):
            phase = .waitingForPassword
        case (.enable, _):
            break
        case (.notNow, .offer), (.notNow, .failed), (.notNow, .terminal):
            snoozed = true
            phase = .hidden
        case (.notNow, _):
            break
        case (.passwordCancelled, .waitingForPassword):
            // Closing the prompt closes the card quietly, like "Not now".
            snoozed = true
            phase = .hidden
        case (.rootFinished, .waitingForPassword):
            phase = .loading
        case (.rootFailed(let why), .waitingForPassword), (.rootFailed(let why), .loading):
            phase = .failed(why)
        case (.passwordCancelled, _), (.rootFinished, _), (.rootFailed, _):
            break
        case (.helperActive, .hidden), (.helperActive, .success):
            break
        case (.helperActive, _):
            phase = .success
        case (.showTerminal, .offer), (.showTerminal, .failed):
            phase = .terminal
        case (.showTerminal, _):
            break
        case (.backFromTerminal, .terminal):
            phase = .offer
        case (.backFromTerminal, _):
            break
        case (.dismissAfterSuccess, .success):
            phase = .hidden
        case (.dismissAfterSuccess, _):
            break
        }
    }
}
