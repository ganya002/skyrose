import Foundation

/// One thing `skyrose doctor --fix` can do. Explained items are printed and left alone.
public enum DoctorRepair: Equatable, Sendable {
    case writeDefaultConfig
    case rehideDock
    case rehideMenuBar
    case restoreDefaultCursor
    case removeStaleSocket
    case explain(String)
}

/// The facts the doctor knows before it decides. The CLI fills this in; tests pass their own.
public struct DoctorWorld: Equatable, Sendable {
    public var configExists: Bool
    public var configBroken: Bool
    public var dockHidden: Bool
    public var dockJournaled: Bool
    public var menuBarHidden: Bool
    public var menuBarJournaled: Bool
    public var cursor: String
    public var cursorCapeExists: Bool
    public var socketPresent: Bool
    public var socketHealthy: Bool
    public var wmRunning: Bool
    public var missingPermissions: [String]

    public init(
        configExists: Bool = true, configBroken: Bool = false,
        dockHidden: Bool = false, dockJournaled: Bool = false,
        menuBarHidden: Bool = false, menuBarJournaled: Bool = false,
        cursor: String = RecommendedSetup.cursorName, cursorCapeExists: Bool = true,
        socketPresent: Bool = false, socketHealthy: Bool = true, wmRunning: Bool = true,
        missingPermissions: [String] = []
    ) {
        self.configExists = configExists
        self.configBroken = configBroken
        self.dockHidden = dockHidden
        self.dockJournaled = dockJournaled
        self.menuBarHidden = menuBarHidden
        self.menuBarJournaled = menuBarJournaled
        self.cursor = cursor
        self.cursorCapeExists = cursorCapeExists
        self.socketPresent = socketPresent
        self.socketHealthy = socketHealthy
        self.wmRunning = wmRunning
        self.missingPermissions = missingPermissions
    }
}

/// Decides the safe repairs. It does not touch the disk.
public enum DoctorFix {
    public static func plan(_ world: DoctorWorld) -> [DoctorRepair] {
        var actions: [DoctorRepair] = []
        if !world.configExists {
            actions.append(.writeDefaultConfig)
        } else if world.configBroken {
            actions.append(.explain("The config file has a problem, so SkyRose is using its built-in defaults. Fix the file, or move it aside and run doctor --fix to write a fresh one."))
        }
        if world.dockJournaled, !world.dockHidden { actions.append(.rehideDock) }
        if world.menuBarJournaled, !world.menuBarHidden { actions.append(.rehideMenuBar) }
        if world.cursor.isEmpty, world.cursorCapeExists {
            actions.append(.restoreDefaultCursor)
        } else if !world.cursor.isEmpty, world.cursor != RecommendedSetup.cursorName, !world.cursorCapeExists {
            actions.append(.explain("The cursor named \(world.cursor) is not installed. SkyRose keeps using the macOS pointer until you pick one in Settings › Appearance."))
        }
        if world.socketPresent, !world.socketHealthy, !world.wmRunning {
            actions.append(.removeStaleSocket)
        }
        if !world.missingPermissions.isEmpty {
            let list = world.missingPermissions.joined(separator: ", ")
            actions.append(.explain("\(list) is not allowed yet. SkyRose cannot tick that box for you. Open System Settings › Privacy & Security, or run skyrose onboarding."))
        }
        return actions
    }
}
