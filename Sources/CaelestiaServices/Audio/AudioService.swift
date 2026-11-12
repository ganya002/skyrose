import AudioToolbox
import CoreAudio
import Foundation
import CaelestiaCore

/// Snapshot of the default output/input devices. `volume` is the CoreAudio virtual main volume
/// (0...1), already clamped to `AudioService.volumeMax`.
public struct AudioState: Hashable, Sendable {
    public var volume: Double = 0
    public var muted: Bool = false
    public var outputDeviceName: String = ""
    public var outputDeviceID: AudioDeviceID = 0
    /// The output's volume can be set (false for e.g. HDMI/DisplayPort audio without a volume
    /// control: the media keys then go to macOS).
    public var volumeSettable: Bool = false
    public var micVolume: Double = 0
    public var micMuted: Bool = false
    public var inputDeviceName: String = ""
    public var inputDeviceID: AudioDeviceID = 0
    /// Set when there is no output device at all (nothing to control).
    public var unavailableReason: String? = nil
    public init() {}
}

/// One selectable output device for the volume popout / `cycleOutput()`.
public struct AudioDevice: Hashable, Sendable, Identifiable {
    public var id: AudioDeviceID
    public var name: String
    public var isDefault: Bool
    public init(id: AudioDeviceID, name: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

/// CoreAudio-backed volume, mute and device control for the bar's audio icon, the OSD and the
/// Hyprland-style volume binds. Changes made elsewhere (keyboard F-keys, System Settings, another
/// app) arrive through `AudioObjectAddPropertyListenerBlock` listeners, so nothing polls.
@MainActor
public final class AudioService {
    /// Hyprland `wpctl set-volume -l 1`: never above 100 %.
    public static let volumeMax: Double = 1.0
    /// Caelestia `audio increment/decrement` step.
    public static let volumeStep: Double = 0.10

    public private(set) var state = AudioState()
    public var onChange: ((AudioState) -> Void)?

    private var listeners: [(object: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []
    private var running = false

    public init() {}

    /// Reads the current state and installs the property listeners.
    public func start() {
        guard !running else { return }
        running = true
        let system = AudioObjectID(kAudioObjectSystemObject)
        addListener(system, selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        addListener(system, selector: kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        addListener(system, selector: kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        refresh()
    }

    public func stop() {
        guard running else { return }
        running = false
        removeAllListeners()
    }

    // MARK: Controls

    /// Sets the output volume (clamped to 0...`volumeMax`) and unmutes, as the volume binds do.
    public func setVolume(_ value: Double) {
        let device = CoreAudioProperties.defaultDevice(input: false)
        guard device != 0 else { return }
        let clamped = clamp(value, 0...Self.volumeMax)
        if CoreAudioProperties.setVolume(Float32(clamped), device: device, input: false) {
            if CoreAudioProperties.muted(device: device, input: false) == true {
                _ = CoreAudioProperties.setMuted(false, device: device, input: false)
            }
        }
        refresh()
    }

    /// Adds `delta` (default ±10 %) to the current volume.
    public func step(_ delta: Double = AudioService.volumeStep) {
        setVolume(state.volume + delta)
    }

    public func setMuted(_ muted: Bool) {
        let device = CoreAudioProperties.defaultDevice(input: false)
        guard device != 0 else { return }
        _ = CoreAudioProperties.setMuted(muted, device: device, input: false)
        refresh()
    }

    public func toggleMuted() { setMuted(!state.muted) }

    /// Mutes/unmutes the default input device (quick toggle "Mic mute").
    public func setMicMuted(_ muted: Bool) {
        let device = CoreAudioProperties.defaultDevice(input: true)
        guard device != 0 else { return }
        if !CoreAudioProperties.setMuted(muted, device: device, input: true) {
            // Devices without a mute control: emulate with volume 0 / previous volume.
            _ = CoreAudioProperties.setVolume(muted ? 0 : 1, device: device, input: true)
        }
        refresh()
    }

    public func toggleMicMuted() { setMicMuted(!state.micMuted) }

    /// All devices with at least one output stream, in CoreAudio order.
    public func outputDevices() -> [AudioDevice] {
        let current = CoreAudioProperties.defaultDevice(input: false)
        return CoreAudioProperties.allDevices().compactMap { id in
            guard CoreAudioProperties.hasStreams(device: id, input: false) else { return nil }
            let name = CoreAudioProperties.name(of: id)
            guard !name.isEmpty else { return nil }
            return AudioDevice(id: id, name: name, isDefault: id == current)
        }
    }

    /// Caelestia `audio.cycleOutput`: makes the next output device the default.
    public func cycleOutput() {
        let devices = outputDevices()
        guard devices.count > 1, let index = devices.firstIndex(where: \.isDefault) else { return }
        let next = devices[(index + 1) % devices.count]
        setOutputDevice(next.id)
    }

    /// All devices with at least one input stream (microphones).
    public func inputDevices() -> [AudioDevice] {
        let current = CoreAudioProperties.defaultDevice(input: true)
        return CoreAudioProperties.allDevices().compactMap { id in
            guard CoreAudioProperties.hasStreams(device: id, input: true) else { return nil }
            let name = CoreAudioProperties.name(of: id)
            guard !name.isEmpty else { return nil }
            return AudioDevice(id: id, name: name, isDefault: id == current)
        }
    }

    public func setInputDevice(_ id: AudioDeviceID) { setDefault(id, selector: kAudioHardwarePropertyDefaultInputDevice) }

    public func setOutputDevice(_ id: AudioDeviceID) { setDefault(id, selector: kAudioHardwarePropertyDefaultOutputDevice) }

    private func setDefault(_ id: AudioDeviceID, selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = id
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        if status != noErr {
            Log.services.error("set default audio device failed: \(status)")
        }
        refresh()
    }

    // MARK: Refresh

    /// Re-reads everything. Called by the listeners and after every control call.
    public func refresh() {
        var s = AudioState()
        let output = CoreAudioProperties.defaultDevice(input: false)
        let input = CoreAudioProperties.defaultDevice(input: true)
        if output != 0 {
            s.outputDeviceID = output
            s.outputDeviceName = CoreAudioProperties.name(of: output)
            s.volume = clamp(Double(CoreAudioProperties.volume(device: output, input: false) ?? 0), 0...Self.volumeMax)
            s.muted = CoreAudioProperties.muted(device: output, input: false) ?? false
            s.volumeSettable = CoreAudioProperties.canSetVolume(device: output, input: false)
        } else {
            s.unavailableReason = "No audio output device"
        }
        if input != 0 {
            s.inputDeviceID = input
            s.inputDeviceName = CoreAudioProperties.name(of: input)
            let micVolume = CoreAudioProperties.volume(device: input, input: true)
            s.micVolume = Double(micVolume ?? 1)
            s.micMuted = CoreAudioProperties.muted(device: input, input: true) ?? (micVolume == 0)
        }
        syncDeviceListeners(output: output, input: input)
        if s != state {
            state = s
            onChange?(s)
        }
    }

    // MARK: Listeners

    private var listenedOutput: AudioObjectID = 0
    private var listenedInput: AudioObjectID = 0

    private func syncDeviceListeners(output: AudioObjectID, input: AudioObjectID) {
        guard running else { return }
        if output != listenedOutput {
            removeListeners(for: listenedOutput)
            listenedOutput = output
            if output != 0 {
                addListener(output, selector: CoreAudioProperties.virtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
                addListener(output, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
                addListener(output, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
            }
        }
        if input != listenedInput {
            removeListeners(for: listenedInput)
            listenedInput = input
            if input != 0 {
                addListener(input, selector: CoreAudioProperties.virtualMainVolume, scope: kAudioDevicePropertyScopeInput)
                addListener(input, selector: kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeInput)
                addListener(input, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput)
            }
        }
    }

    private func addListener(_ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard object == AudioObjectID(kAudioObjectSystemObject) || AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            onMain { self.refresh() }
        }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block)
        if status == noErr {
            listeners.append((object, address, block))
        }
    }

    private func removeListeners(for object: AudioObjectID) {
        guard object != 0 else { return }
        for entry in listeners where entry.object == object {
            var address = entry.address
            AudioObjectRemovePropertyListenerBlock(entry.object, &address, DispatchQueue.main, entry.block)
        }
        listeners.removeAll { $0.object == object }
    }

    private func removeAllListeners() {
        for entry in listeners {
            var address = entry.address
            AudioObjectRemovePropertyListenerBlock(entry.object, &address, DispatchQueue.main, entry.block)
        }
        listeners.removeAll()
        listenedOutput = 0
        listenedInput = 0
    }
}

/// Thin, synchronous CoreAudio property accessors. Every call degrades to `nil`/`false` on error.
enum CoreAudioProperties {
    /// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` ('vmvc'): the per-device main volume
    /// that System Settings and the volume keys use, available even for devices with no master
    /// channel control.
    static let virtualMainVolume: AudioObjectPropertySelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume

    static func defaultDevice(input: Bool) -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : 0
    }

    static func allDevices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices)
        return status == noErr ? devices : []
    }

    static func name(of device: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        guard status == noErr, let value = name?.takeRetainedValue() else { return "" }
        return value as String
    }

    static func hasStreams(device: AudioDeviceID, input: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    /// Virtual main volume, falling back to the channel-1 scalar volume.
    static func volume(device: AudioDeviceID, input: Bool) -> Float32? {
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        if let v = getFloat(device, selector: virtualMainVolume, scope: scope, element: kAudioObjectPropertyElementMain) { return v }
        if let v = getFloat(device, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: kAudioObjectPropertyElementMain) { return v }
        return getFloat(device, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: 1)
    }

    static func setVolume(_ value: Float32, device: AudioDeviceID, input: Bool) -> Bool {
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        if setFloat(value, device, selector: virtualMainVolume, scope: scope, element: kAudioObjectPropertyElementMain) { return true }
        if setFloat(value, device, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: kAudioObjectPropertyElementMain) { return true }
        var any = false
        for channel: AudioObjectPropertyElement in [1, 2] {
            any = setFloat(value, device, selector: kAudioDevicePropertyVolumeScalar, scope: scope, element: channel) || any
        }
        return any
    }

    /// Whether `setVolume` can work on this device (some selector is settable).
    static func canSetVolume(device: AudioDeviceID, input: Bool) -> Bool {
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        let candidates: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (virtualMainVolume, kAudioObjectPropertyElementMain), (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
        ]
        for (selector, element) in candidates {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
            var settable: DarwinBoolean = false
            if AudioObjectHasProperty(device, &address), AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue {
                return true
            }
        }
        return false
    }

    static func muted(device: AudioDeviceID, input: Bool) -> Bool? {
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        if let v = getUInt32(device, selector: kAudioDevicePropertyMute, scope: scope, element: kAudioObjectPropertyElementMain) { return v != 0 }
        if let v = getUInt32(device, selector: kAudioDevicePropertyMute, scope: scope, element: 1) { return v != 0 }
        return nil
    }

    static func setMuted(_ muted: Bool, device: AudioDeviceID, input: Bool) -> Bool {
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        if setUInt32(muted ? 1 : 0, device, selector: kAudioDevicePropertyMute, scope: scope, element: kAudioObjectPropertyElementMain) { return true }
        var any = false
        for channel: AudioObjectPropertyElement in [1, 2] {
            any = setUInt32(muted ? 1 : 0, device, selector: kAudioDevicePropertyMute, scope: scope, element: channel) || any
        }
        return any
    }

    // MARK: Primitives

    private static func getFloat(_ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Float32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func setFloat(_ value: Float32, _ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(object, &address), AudioObjectIsPropertySettable(object, &address, &settable) == noErr, settable.boolValue else { return false }
        var v = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    private static func getUInt32(_ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func setUInt32(_ value: UInt32, _ object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(object, &address), AudioObjectIsPropertySettable(object, &address, &settable) == noErr, settable.boolValue else { return false }
        var v = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }
}
