import AppKit
import ApplicationServices
import CoreBluetooth
import CoreGraphics
import CoreLocation
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
        /// Wi-Fi network names (macOS hides SSIDs without it). Optional.
        case location
        /// The Bluetooth panel (paired devices, pairing). Optional.
        case bluetooth

        public var isRequired: Bool { self == .accessibility || self == .inputMonitoring }

        /// System Settings pane for this permission.
        public var settingsURL: URL {
            let anchor: String
            switch self {
            case .accessibility: anchor = "Privacy_Accessibility"
            case .inputMonitoring: anchor = "Privacy_ListenEvent"
            case .screenRecording: anchor = "Privacy_ScreenCapture"
            case .location: anchor = "Privacy_LocationServices"
            case .bluetooth: anchor = "Privacy_Bluetooth"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        }
    }

    public struct Status: Equatable, Sendable {
        public var accessibility: Bool
        public var inputMonitoring: Bool
        public var screenRecording: Bool
        public var location: Bool
        public var bluetooth: Bool

        public init(accessibility: Bool, inputMonitoring: Bool, screenRecording: Bool, location: Bool = false, bluetooth: Bool = false) {
            self.accessibility = accessibility
            self.inputMonitoring = inputMonitoring
            self.screenRecording = screenRecording
            self.location = location
            self.bluetooth = bluetooth
        }

        public func isGranted(_ kind: Kind) -> Bool {
            switch kind {
            case .accessibility: return accessibility
            case .inputMonitoring: return inputMonitoring
            case .screenRecording: return screenRecording
            case .location: return location
            case .bluetooth: return bluetooth
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
            screenRecording: CGPreflightScreenCaptureAccess(),
            location: locationGranted,
            bluetooth: CBManager.authorization == .allowedAlways
        )
    }

    public static var locationGranted: Bool {
        let s = CLLocationManager().authorizationStatus
        return s == .authorizedAlways || s == .authorized
    }

    /// Location and Bluetooth only prompt from a live manager, and the answer comes later: the
    /// managers stay alive here so the prompt is not torn down.
    nonisolated(unsafe) private static var askers: [AnyObject] = []

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
        case .location:
            guard !locationGranted else { return true }
            onMain {
                let m = CLLocationManager()
                askers.append(m)
                m.requestWhenInUseAuthorization()
            }
            return false
        case .bluetooth:
            guard CBManager.authorization != .allowedAlways else { return true }
            onMain { askers.append(CBCentralManager(delegate: nil, queue: nil)) }
            return false
        }
    }

    /// Whether macOS will still show `kind`'s prompt (Location and Bluetooth only).
    public static func undecided(_ kind: Kind) -> Bool {
        switch kind {
        case .location: return CLLocationManager().authorizationStatus == .notDetermined
        case .bluetooth: return CBManager.authorization == .notDetermined
        default: return false
        }
    }

    /// Opens the System Settings pane where the user grants `kind`.
    public static func openSettings(for kind: Kind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }
}
