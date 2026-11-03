import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// TCC permission checks and requests (spec 10.8). Checks never prompt; `request` shows the
/// system prompt once (macOS only prompts the first time) and the wizard then deep-links into
/// System Settings.
public enum Permissions {
    public enum Kind: String, CaseIterable, Sendable {
        /// Window control (AX). Required.
        case accessibility
        /// The keyboard/mouse event tap. Required for hotkeys.
        case inputMonitoring
        /// Workspace-slide snapshots and the recorder/screenshots. Optional (a fade replaces the slide).
        case screenRecording

        public var isRequired: Bool { self != .screenRecording }

        /// System Settings pane for this permission.
        public var settingsURL: URL {
            let anchor: String
            switch self {
            case .accessibility: anchor = "Privacy_Accessibility"
            case .inputMonitoring: anchor = "Privacy_ListenEvent"
            case .screenRecording: anchor = "Privacy_ScreenCapture"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        }
    }

    public struct Status: Equatable, Sendable {
        public var accessibility: Bool
        public var inputMonitoring: Bool
        public var screenRecording: Bool

        public init(accessibility: Bool, inputMonitoring: Bool, screenRecording: Bool) {
            self.accessibility = accessibility
            self.inputMonitoring = inputMonitoring
            self.screenRecording = screenRecording
        }

        public func isGranted(_ kind: Kind) -> Bool {
            switch kind {
            case .accessibility: return accessibility
            case .inputMonitoring: return inputMonitoring
            case .screenRecording: return screenRecording
            }
        }

        /// Required permissions still missing, in wizard order.
        public var missingRequired: [Kind] { Kind.allCases.filter { $0.isRequired && !isGranted($0) } }
        public var canManageWindows: Bool { missingRequired.isEmpty }
    }

    /// Current status without prompting.
    public static func status() -> Status {
        Status(
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess(),
            screenRecording: CGPreflightScreenCaptureAccess()
        )
    }

    /// Shows the system prompt for `kind` (first time only). Returns the status right after.
    @discardableResult
    public static func request(_ kind: Kind) -> Bool {
        switch kind {
        case .accessibility:
            // The value of kAXTrustedCheckOptionPrompt (a mutable C global, not concurrency-safe).
            return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .inputMonitoring:
            return CGRequestListenEventAccess()
        case .screenRecording:
            return CGRequestScreenCaptureAccess()
        }
    }

    /// Opens the System Settings pane where the user grants `kind`.
    public static func openSettings(for kind: Kind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }
}
