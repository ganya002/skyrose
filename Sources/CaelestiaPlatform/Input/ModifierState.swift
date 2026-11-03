import CaelestiaCore
import Foundation

/// The modifier family a physical modifier key belongs to.
public enum ModifierFamily: Hashable, Sendable, CaseIterable {
    case option, command, control, shift, fn, capsLock

    public init(_ physical: PhysicalModifier) {
        switch physical {
        case .lopt, .ropt, .opt: self = .option
        case .lcmd, .rcmd, .cmd: self = .command
        case .lctrl, .rctrl, .ctrl: self = .control
        case .lshift, .rshift, .shift: self = .shift
        case .fn: self = .fn
        case .capslock: self = .capsLock
        }
    }

    /// Device-independent CGEventFlags bit of the family (0 for Caps-Lock-as-F18, which is a key).
    public var familyFlag: UInt64 {
        switch self {
        case .option: return PhysicalModifier.opt.familyFlag
        case .command: return PhysicalModifier.cmd.familyFlag
        case .control: return PhysicalModifier.ctrl.familyFlag
        case .shift: return PhysicalModifier.shift.familyFlag
        case .fn: return PhysicalModifier.fn.familyFlag
        case .capsLock: return 0
        }
    }
}

extension PhysicalModifier {
    /// The family this key belongs to.
    public var family: ModifierFamily { ModifierFamily(self) }

    /// `true` for the left-hand key of a sided family (⌥L, ⌘L, ⌃L, ⇧L).
    public var isLeftKey: Bool {
        switch self {
        case .lopt, .lcmd, .lctrl, .lshift: return true
        default: return false
        }
    }

    /// `true` for the right-hand key of a sided family (⌥R, ⌘R, ⌃R, ⇧R).
    public var isRightKey: Bool {
        switch self {
        case .ropt, .rcmd, .rctrl, .rshift: return true
        default: return false
        }
    }

    /// Whether a mapping to `self` is satisfied by the held physical key `key`.
    ///
    /// A side-specific mapping (`.lopt`) is satisfied only by that key; a side-agnostic mapping
    /// (`.opt`) is satisfied by either side and by an unknown-side press (`.opt` itself).
    public func covers(_ key: PhysicalModifier) -> Bool {
        if key == self { return true }
        guard !isSideSpecific, family == key.family else { return false }
        switch family {
        case .fn, .capsLock: return false
        default: return true
        }
    }
}

/// Which physical modifier keys are held, derived from a `CGEventFlags` raw value.
///
/// Sides are told apart with the device-dependent NX_DEVICE*KEYMASK bits (⌥L 0x20, ⌥R 0x40,
/// ⌘L 0x08, ⌘R 0x10, ⌃L 0x01, ⌃R 0x2000, ⇧L 0x02, ⇧R 0x04). A family flag without any side bit
/// (some virtual keyboards and remote-desktop clients) is reported as "unknown side", which
/// matches side-agnostic mappings only, unless `treatUnknownSideAsLeft` is on (the default) in
/// which case it counts as the left key so those keyboards still drive the WM.
///
/// The Caps Lock *latch* (`maskAlphaShift`, 0x10000) and the numeric-pad / help / non-coalesced
/// bits are carried for information but never take part in matching. `fn` only matters when the
/// modifier map binds a logical modifier to it (laptops set the fn bit for arrow and F-keys).
public struct ModifierState: Equatable, Sendable {
    /// Which key(s) of a sided family are down.
    public enum Side: Equatable, Sendable {
        case left, right, unknown
    }

    /// Hold state of one sided family (option, command, control, shift).
    public struct Family: Equatable, Sendable {
        public var left: Bool
        public var right: Bool
        /// The family flag is set but no device-dependent side bit is (virtual keyboards).
        public var unknownSide: Bool

        public init(left: Bool = false, right: Bool = false, unknownSide: Bool = false) {
            self.left = left
            self.right = right
            self.unknownSide = unknownSide
        }

        public var isHeld: Bool { left || right || unknownSide }

        public var heldSides: [Side] {
            var s: [Side] = []
            if left { s.append(.left) }
            if right { s.append(.right) }
            if unknownSide { s.append(.unknown) }
            return s
        }

        /// Builds the family state from a flags word: the family flag gates everything, the
        /// device-dependent bits pick the side(s).
        init(flags: UInt64, familyFlag: UInt64, leftBit: UInt64, rightBit: UInt64) {
            guard flags & familyFlag != 0 else {
                self.init()
                return
            }
            let l = flags & leftBit != 0
            let r = flags & rightBit != 0
            self.init(left: l, right: r, unknownSide: !l && !r)
        }
    }

    public var option: Family
    public var command: Family
    public var control: Family
    public var shift: Family
    /// The fn / globe key (`maskSecondaryFn`).
    public var fn: Bool
    /// The Caps Lock latch (`maskAlphaShift`). Informational only; never part of a chord.
    public var capsLockOn: Bool
    /// Synthetic modifier: Caps Lock remapped to F18 (preset B) is currently held.
    public var f18: Bool
    /// Whether an unknown-side press counts as the left key.
    public var treatUnknownSideAsLeft: Bool
    /// The raw `CGEventFlags` value this state was built from.
    public var rawFlags: UInt64

    public init(flags: UInt64, f18Held: Bool = false, treatUnknownSideAsLeft: Bool = true) {
        rawFlags = flags
        option = Family(flags: flags, familyFlag: ModifierFamily.option.familyFlag,
                        leftBit: PhysicalModifier.lopt.sideFlag, rightBit: PhysicalModifier.ropt.sideFlag)
        command = Family(flags: flags, familyFlag: ModifierFamily.command.familyFlag,
                         leftBit: PhysicalModifier.lcmd.sideFlag, rightBit: PhysicalModifier.rcmd.sideFlag)
        control = Family(flags: flags, familyFlag: ModifierFamily.control.familyFlag,
                         leftBit: PhysicalModifier.lctrl.sideFlag, rightBit: PhysicalModifier.rctrl.sideFlag)
        shift = Family(flags: flags, familyFlag: ModifierFamily.shift.familyFlag,
                       leftBit: PhysicalModifier.lshift.sideFlag, rightBit: PhysicalModifier.rshift.sideFlag)
        fn = flags & ModifierFamily.fn.familyFlag != 0
        capsLockOn = flags & ModifierState.capsLockLatchFlag != 0
        f18 = f18Held
        self.treatUnknownSideAsLeft = treatUnknownSideAsLeft
    }

    /// `maskAlphaShift`: the Caps Lock latch bit.
    public static let capsLockLatchFlag: UInt64 = 0x1_0000

    /// Hold state of a sided family; `nil` for `.fn` and `.capsLock`, which have no sides.
    public func family(_ f: ModifierFamily) -> Family? {
        switch f {
        case .option: return option
        case .command: return command
        case .control: return control
        case .shift: return shift
        case .fn, .capsLock: return nil
        }
    }

    /// Whether any modifier that can take part in a chord is held (the Caps Lock latch is ignored).
    public var isEmpty: Bool {
        !option.isHeld && !command.isHeld && !control.isHeld && !shift.isHeld && !fn && !f18
    }

    /// Every held physical key, side-resolved: `.lopt`/`.ropt`/…, `.fn`, and `.capslock` for the
    /// synthetic F18 modifier. An unknown-side press yields the left key when
    /// `treatUnknownSideAsLeft` is on, otherwise the side-agnostic family key (`.opt`).
    public var heldKeys: [PhysicalModifier] {
        var keys: [PhysicalModifier] = []
        func add(_ fam: Family, left: PhysicalModifier, right: PhysicalModifier, any: PhysicalModifier) {
            if fam.left { keys.append(left) }
            if fam.right { keys.append(right) }
            if fam.unknownSide { keys.append(treatUnknownSideAsLeft ? left : any) }
        }
        add(option, left: .lopt, right: .ropt, any: .opt)
        add(command, left: .lcmd, right: .rcmd, any: .cmd)
        add(control, left: .lctrl, right: .rctrl, any: .ctrl)
        add(shift, left: .lshift, right: .rshift, any: .shift)
        if fn { keys.append(.fn) }
        if f18 { keys.append(.capslock) }
        return keys
    }

    /// Whether `key` is held. A side-agnostic key (`.opt`) is held when either side is; a sided
    /// key is also held by an unknown-side press when `treatUnknownSideAsLeft` makes it the left one.
    public func isHeld(_ key: PhysicalModifier) -> Bool {
        heldKeys.contains { key.covers($0) }
    }

    /// The same state with `key` lifted (used when a modifier key is itself the bound key).
    public func removing(_ key: PhysicalModifier) -> ModifierState {
        var s = self
        func clear(_ fam: inout Family) {
            if key.isLeftKey || !key.isSideSpecific { fam.left = false; fam.unknownSide = false }
            if key.isRightKey || !key.isSideSpecific { fam.right = false }
        }
        switch key.family {
        case .option: clear(&s.option)
        case .command: clear(&s.command)
        case .control: clear(&s.control)
        case .shift: clear(&s.shift)
        case .fn: s.fn = false
        case .capsLock: s.f18 = false
        }
        return s
    }

    /// The set of logical modifiers held under `map`, or `nil` when a held physical key is not
    /// part of the map, meaning this cannot be a WM chord and the event belongs to the app.
    ///
    /// Under preset A (Super = ⌥L) a held *right* Option returns `nil`, so Norwegian characters
    /// typed with ⌥R pass straight through. Shift is always allowed: either Shift key satisfies a
    /// Shift-family mapping. `fn` and the synthetic F18 are ignored unless the map uses them.
    public func logicalModifiers(under map: ModifierMap) -> Set<LogicalModifier>? {
        var result = Set<LogicalModifier>()
        for key in heldKeys {
            let covering = LogicalModifier.allCases.filter { map[$0].covers(key) }
            if !covering.isEmpty {
                result.formUnion(covering)
                continue
            }
            switch key.family {
            case .shift:
                let shiftMapped = LogicalModifier.allCases.filter { map[$0].family == .shift }
                guard !shiftMapped.isEmpty else { return nil }
                result.formUnion(shiftMapped)
            case .fn, .capsLock:
                continue
            case .option, .command, .control:
                return nil
            }
        }
        return result
    }

    /// The physical key a `flagsChanged` event's key code refers to (⌥L 0x3A, ⌥R 0x3D, ⌘L 0x37,
    /// ⌘R 0x36, ⌃L 0x3B, ⌃R 0x3E, ⇧L 0x38, ⇧R 0x3C, fn 0x3F); `nil` for Caps Lock and unknown codes.
    public static func physicalKey(forModifierKeyCode code: UInt16) -> PhysicalModifier? {
        modifierKeyCodes[code]
    }

    private static let modifierKeyCodes: [UInt16: PhysicalModifier] = {
        var m: [UInt16: PhysicalModifier] = [:]
        for p in PhysicalModifier.allCases where p.isSideSpecific || p == .fn {
            for c in p.keyCodes { m[c] = p }
        }
        return m
    }()
}
