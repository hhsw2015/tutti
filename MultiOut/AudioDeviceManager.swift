import Foundation
import CoreAudio
import ApplicationServices

private extension AudioObjectPropertyAddress {
    init(_ sel: AudioObjectPropertySelector,
         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
         _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) {
        self.init(mSelector: sel, mScope: scope, mElement: element)
    }
}

@MainActor
final class AudioDeviceManager: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var selectedIDs: Set<AudioDeviceID> = []
    @Published var volumes: [AudioDeviceID: Float] = [:]
    @Published private(set) var sampleRates: [AudioDeviceID: Double] = [:]
    @Published private(set) var batteryLevels: [AudioDeviceID: Int] = [:]
    @Published private(set) var isActive = false {
        didSet { volumeKeyMonitor?.interceptEnabled = isActive }
    }
    @Published private(set) var hasAccessibilityPermission = false

    private var aggregateID: AudioDeviceID?
    private var savedDefaultID: AudioDeviceID?

    private var volumeKeyMonitor: VolumeKeyMonitor?
    private var preMuteVolumes: [AudioDeviceID: Float]?
    private var permissionTimer: DispatchSourceTimer?
    private var batteryTask: Task<Void, Never>?

    init() {
        cleanupOrphans()
        refreshDevices()
        startListening()
        startVolumeKeyMonitoring()
        startPermissionPolling()
        startBatteryPolling()
    }

    func toggle(_ device: AudioDevice) {
        if selectedIDs.contains(device.id) {
            selectedIDs.remove(device.id)
        } else {
            if volumes[device.id] == nil {
                volumes[device.id] = readVolume(device.id) ?? 1.0
            }
            selectedIDs.insert(device.id)
        }
        updateAggregate()
    }

    func setVolume(_ volume: Float, for id: AudioDeviceID) {
        volumes[id] = volume
        writeVolume(volume, to: id)
    }

    func applyPreset(uids: [String]) {
        selectedIDs = Set(devices.filter { uids.contains($0.uid) }.map { $0.id })
        updateAggregate()
    }

    func cleanup() {
        destroyAggregate()
    }

    // MARK: - Aggregate lifecycle

    private func updateAggregate() {
        let selected = devices.filter { selectedIDs.contains($0.id) }
        destroyAggregate()

        if selected.count >= 2 {
            if let agg = buildAggregate(selected) {
                aggregateID = agg
                setDefault(agg)
                isActive = true
                for d in selected {
                    if let v = volumes[d.id] { writeVolume(v, to: d.id) }
                }
            }
        } else {
            if let id = selected.first?.id {
                setDefault(id)
            } else if let saved = savedDefaultID {
                setDefault(saved)
                savedDefaultID = nil
            }
            isActive = false
        }
    }

    private func destroyAggregate() {
        guard let agg = aggregateID else { return }
        if let saved = savedDefaultID { setDefault(saved); savedDefaultID = nil }
        AudioHardwareDestroyAggregateDevice(agg)
        aggregateID = nil
        isActive = false
    }

    private func buildAggregate(_ selected: [AudioDevice]) -> AudioDeviceID? {
        if savedDefaultID == nil { savedDefaultID = readDefault() }

        let subs: [[String: Any]] = selected.enumerated().map { i, d in
            ["uid": d.uid, "drift": i == 0 ? 0 : 1]
        }
        let desc: [String: Any] = [
            "name": "MultiOut",
            "uid": "com.multiout.aggregate",
            "subdevices": subs,
            "master": selected[0].uid,
            "stacked": 1
        ]
        var id: AudioDeviceID = 0
        guard AudioHardwareCreateAggregateDevice(desc as CFDictionary, &id) == noErr else { return nil }
        return id
    }

    // MARK: - Enumeration

    func refreshDevices() {
        var addr = AudioObjectPropertyAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)

        var newDevices: [AudioDevice] = []
        for id in ids {
            guard isOutputDevice(id),
                  let name = stringProp(id, kAudioObjectPropertyName),
                  let uid = stringProp(id, kAudioDevicePropertyDeviceUID),
                  uid != "com.multiout.aggregate" else { continue }
            let transport = readTransportType(id)
            // AirPlay devices can't be aggregated — Audio MIDI Setup hides them too.
            if transport == kAudioDeviceTransportTypeAirPlay { continue }
            newDevices.append(AudioDevice(id: id, name: name, uid: uid,
                                          canSetVolume: checkSettable(id),
                                          transportType: transport))
        }

        let freshIDs = Set(newDevices.map { $0.id })

        // Selected devices that vanished from CoreAudio are likely sub-devices absorbed
        // by our aggregate — keep them visible while the aggregate is alive. Outside
        // of aggregate mode, a vanished device is genuinely gone (e.g., Bluetooth
        // disconnect) and should be removed from the list.
        let preserved: [AudioDevice] = aggregateID != nil
            ? devices.filter { selectedIDs.contains($0.id) && !freshIDs.contains($0.id) }
            : []
        newDevices += preserved

        devices = newDevices

        var newRates: [AudioDeviceID: Double] = [:]
        for d in newDevices {
            let r = readSampleRate(d.id)
            newRates[d.id] = r > 0 ? r : sampleRates[d.id] ?? 0
        }
        sampleRates = newRates

        let trulyGone = selectedIDs.subtracting(Set(newDevices.map { $0.id }))
        if !trulyGone.isEmpty {
            selectedIDs = selectedIDs.subtracting(trulyGone)
            updateAggregate()
        }

        syncSelectionToExternalDefault()
    }

    private func readSampleRate(_ id: AudioDeviceID) -> Double {
        var addr = AudioObjectPropertyAddress(kAudioDevicePropertyNominalSampleRate)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &rate) == noErr else { return 0 }
        return rate
    }

    private func readTransportType(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(kAudioDevicePropertyTransportType)
        var type: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &type)
        return type
    }

    private func isOutputDevice(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(kAudioDevicePropertyStreamConfiguration,
                                              kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let ptr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr) == noErr else { return false }
        return ptr.pointee.mNumberBuffers > 0
    }

    private func stringProp(_ id: AudioDeviceID, _ sel: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(sel)
        var val: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &val) == noErr else { return nil }
        return val?.takeRetainedValue() as String?
    }

    private func readDefault() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    private func setDefault(_ id: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var devID = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &devID)
    }

    // MARK: - Volume

    // Returns the first element (0 or 1) that actually has the volume property,
    // and is settable. Using AudioObjectHasProperty before IsPropertySettable
    // avoids false positives on built-in devices where IsPropertySettable
    // returns true but writes are silently ignored.
    private func settableVolumeAddress(for id: AudioDeviceID) -> AudioObjectPropertyAddress? {
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1] {
            var addr = AudioObjectPropertyAddress(kAudioDevicePropertyVolumeScalar,
                                                  kAudioDevicePropertyScopeOutput,
                                                  element)
            guard AudioObjectHasProperty(id, &addr) else { continue }
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(id, &addr, &settable) == noErr,
                  settable.boolValue else { continue }
            return addr
        }
        return nil
    }

    private func checkSettable(_ id: AudioDeviceID) -> Bool {
        settableVolumeAddress(for: id) != nil
    }

    private func readVolume(_ id: AudioDeviceID) -> Float? {
        guard var addr = settableVolumeAddress(for: id) else { return nil }
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &vol) == noErr else { return nil }
        return vol
    }

    private func writeVolume(_ volume: Float, to id: AudioDeviceID) {
        guard var addr = settableVolumeAddress(for: id) else { return }
        var vol = Float32(volume)
        AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
        // If using per-channel (element 1), also set right channel
        if addr.mElement == 1 {
            addr.mElement = 2
            if AudioObjectHasProperty(id, &addr) {
                AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
            }
        }
    }

    // MARK: - Orphan cleanup & device listener

    private func cleanupOrphans() {
        var addr = AudioObjectPropertyAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        for id in ids {
            if let uid = stringProp(id, kAudioDevicePropertyDeviceUID), uid == "com.multiout.aggregate" {
                AudioHardwareDestroyAggregateDevice(id)
            }
        }
    }

    private func startListening() {
        var devAddr = AudioObjectPropertyAddress(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devAddr, nil) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshDevices() }
        }

        // Detect when something external (System Settings, Control Center) changes
        // the default output away from our aggregate device
        var defAddr = AudioObjectPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defAddr, nil) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.handleExternalDefaultChange() }
        }
    }

    private func handleExternalDefaultChange() {
        if let aggID = aggregateID,
           let currentDefault = readDefault(),
           currentDefault != aggID {
            // System default changed away from our aggregate externally — reset state
            AudioHardwareDestroyAggregateDevice(aggID)
            aggregateID = nil
            savedDefaultID = nil
            selectedIDs = []
            isActive = false
            // refreshDevices() will be called by the kAudioHardwarePropertyDevices
            // notification that fires when the aggregate is destroyed
        }
        syncSelectionToExternalDefault()
    }

    // Follow macOS when something external (Bluetooth auto-switch, Control Center,
    // System Settings) changes the default output, and on startup so the menu shows
    // whatever is currently producing sound.
    private func syncSelectionToExternalDefault() {
        guard aggregateID == nil else { return }
        guard let id = readDefault(),
              devices.contains(where: { $0.id == id }) else { return }
        if selectedIDs == [id] { return }
        if volumes[id] == nil { volumes[id] = readVolume(id) ?? 1.0 }
        selectedIDs = [id]
    }

    // MARK: - System volume key handling

    // Aggregate devices don't expose master volume to CoreAudio, so the system
    // volume slider is greyed out when our aggregate is the default. We intercept
    // the hardware volume keys globally and apply the change to all sub-devices.
    // SwiftUI Timer.publish in a MenuBarExtra popover isn't reliable — alt-tab-macos
    // uses a DispatchSourceTimer on a background queue for the same reason.
    private func startBatteryPolling() {
        batteryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshBatteryLevels()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func refreshBatteryLevels() async {
        let bluetoothDevices = devices.filter { $0.isBluetooth }
        guard !bluetoothDevices.isEmpty else {
            if !batteryLevels.isEmpty { batteryLevels = [:] }
            return
        }
        let byName = await BluetoothBattery.fetch()
        var newLevels: [AudioDeviceID: Int] = [:]
        for d in bluetoothDevices {
            if let level = byName[BluetoothBattery.normalize(d.name)] {
                newLevels[d.id] = level
            }
        }
        batteryLevels = newLevels
    }

    private func startPermissionPolling() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in self?.recheckPermission() }
        }
        timer.resume()
        permissionTimer = timer
    }

    private func recheckPermission() {
        // Retry tap creation in case permission was just granted externally.
        volumeKeyMonitor?.start(promptForPermission: false)
        // Trust either signal — AX may have stale in-process state, tap creation
        // may fail for unrelated reasons. Granted if either reports true.
        let axTrusted = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ] as CFDictionary)
        let now = axTrusted || (volumeKeyMonitor?.isRunning ?? false)
        if now != hasAccessibilityPermission {
            hasAccessibilityPermission = now
        }
    }

    private func startVolumeKeyMonitoring() {
        volumeKeyMonitor = VolumeKeyMonitor { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleVolumeKey(action)
            }
        }
        volumeKeyMonitor?.start(promptForPermission: true)
    }

    private func handleVolumeKey(_ action: VolumeKeyAction) {
        guard isActive else { return }
        switch action {
        case .adjust(let delta):
            preMuteVolumes = nil
            adjustAllVolumes(by: delta)
        case .mute:
            toggleMute()
        }
    }

    private func adjustAllVolumes(by delta: Float) {
        for id in selectedIDs {
            let current = volumes[id] ?? 1.0
            setVolume(max(0, min(1, current + delta)), for: id)
        }
    }

    private func toggleMute() {
        if let saved = preMuteVolumes {
            for (id, v) in saved where selectedIDs.contains(id) {
                setVolume(v, for: id)
            }
            preMuteVolumes = nil
        } else {
            preMuteVolumes = volumes
            for id in selectedIDs {
                setVolume(0, for: id)
            }
        }
    }
}
