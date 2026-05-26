import Foundation
import CoreAudio
import ApplicationServices
import Combine

private extension AudioObjectPropertyAddress {
    init(_ sel: AudioObjectPropertySelector,
         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
         _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) {
        self.init(mSelector: sel, mScope: scope, mElement: element)
    }
}

private let aggregateUID = "com.recents.tutti.aggregate"
private let legacyMultiOutUID = "com.multiout.aggregate"
private let systemObject = AudioObjectID(kAudioObjectSystemObject)

/// Why a free user just hit a Pro gate. Banner copy routes on this.
enum UpgradeReason: Equatable {
    case volumeTakeover  // hardware volume keys or scroll on the menu bar icon
    case profile         // save / apply a device-set profile
}

@MainActor
final class AudioDeviceManager: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var selectedIDs: Set<AudioDeviceID> = [] {
        didSet { syncVolumeListeners(old: oldValue) }
    }
    @Published private(set) var volumes: [AudioDeviceID: Float] = [:]
    @Published private(set) var batteryLevels: [AudioDeviceID: Int] = [:]
    @Published private(set) var isActive = false {
        didSet { refreshProFeatureStates() }
    }
    @Published private(set) var hasAccessibilityPermission = false
    /// Bumped whenever a free-tier (no-Pro, no-trial) user hits a Pro-only
    /// feature path — currently the hardware volume key after trial expiry.
    /// UI observes this to open the upgrade banner; new UUID each time so
    /// repeated attempts still fire.
    @Published var lastUpgradeAttemptID: UUID?
    /// Which Pro-only path the most recent upgrade attempt came from. Banner
    /// copy routes on this so a profile-tap doesn't show "音量直控" copy.
    @Published private(set) var pendingUpgradeReason: UpgradeReason = .volumeTakeover

    private var aggregateID: AudioDeviceID?
    private var savedDefaultID: AudioDeviceID?

    private var volumeKeyMonitor: VolumeKeyMonitor?
    private var preMuteVolumes: [AudioDeviceID: Float] = [:]
    private var volumeAddressCache: [AudioDeviceID: AudioObjectPropertyAddress] = [:]
    private var permissionTimer: DispatchSourceTimer?
    private var batteryTask: Task<Void, Never>?
    private var popoverIsOpen = false
    private var licenseObserver: AnyCancellable?
    private var trialObserver: AnyCancellable?
    private var lastVolumeKeyUpgradePromptAt: Date?

    /// Per-device CoreAudio volume listeners. We must keep the block
    /// reference to deregister later, so a token bundles address+block.
    private struct VolumeListener {
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var volumeListeners: [AudioDeviceID: VolumeListener] = [:]

    init() {
        cleanupOrphans()
        refreshDevices()
        startListening()
        startVolumeKeyMonitoring()
        startPermissionPolling()
        startBatteryPolling()
        startLicenseObserver()
        startTrialObserver()
    }

    private func startLicenseObserver() {
        licenseObserver = LicenseManager.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshProFeatureStates()
            }
    }

    private func startTrialObserver() {
        trialObserver = TrialManager.shared.$trialStartDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshProFeatureStates()
            }
    }

    private func refreshProFeatureStates() {
        volumeKeyMonitor?.interceptEnabled = isActive && LicenseManager.hasProAccess
    }

    func toggle(_ device: AudioDevice) {
        let alreadySelected = selectedIDs.contains(device.id)

        if alreadySelected {
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
        guard volumes[id] != volume else { return }
        volumes[id] = volume
        writeVolume(volume, to: id)
        // Raising a device past 0 invalidates any saved restore hint — the
        // user has explicitly chosen a new volume.
        if volume > 0 {
            preMuteVolumes.removeValue(forKey: id)
        }
    }

    var masterVolume: Float {
        selectedIDs.compactMap { volumes[$0] }.max() ?? 0
    }

    /// "Muted" means audible silence: volume is 0. `preMuteVolumes` is only a
    /// hint about what to restore to, not the source of truth.
    func isMuted(_ id: AudioDeviceID) -> Bool {
        (volumes[id] ?? 0) == 0
    }

    /// True only when every selected device is silent. Per-device muting of a
    /// single output doesn't count as "muted" while other devices still play.
    var isMuted: Bool {
        !selectedIDs.isEmpty && selectedIDs.allSatisfy { (volumes[$0] ?? 0) == 0 }
    }

    var silentCount: Int {
        selectedIDs.reduce(into: 0) { acc, id in
            if (volumes[id] ?? 0) == 0 { acc += 1 }
        }
    }

    func setMasterVolume(_ value: Float) {
        let delta = value - masterVolume
        guard delta != 0 else { return }
        adjustAllVolumes(by: delta)
    }

    func toggleMute(deviceID id: AudioDeviceID) {
        if isMuted(id) {
            // Restore from saved hint if we have one, otherwise pick a sensible default.
            let restoreTo = preMuteVolumes[id] ?? 0.5
            setVolume(restoreTo, for: id)
        } else {
            let current = volumes[id] ?? 1.0
            preMuteVolumes[id] = current
            setVolume(0, for: id)
        }
    }

    func toggleMasterMute() {
        if isMuted {
            for id in selectedIDs {
                toggleMute(deviceID: id)
            }
        } else {
            for id in selectedIDs where (volumes[id] ?? 0) > 0 {
                toggleMute(deviceID: id)
            }
        }
    }

    func cleanup() {
        destroyAggregate()
        batteryTask?.cancel()
        permissionTimer?.cancel()
        for id in Array(volumeListeners.keys) { removeVolumeListener(for: id) }
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
            "name": "Tutti",
            "uid": aggregateUID,
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
        var newDevices: [AudioDevice] = []
        for id in allDeviceIDs() {
            guard isOutputDevice(id),
                  let name = stringProp(id, kAudioObjectPropertyName),
                  let uid = stringProp(id, kAudioDevicePropertyDeviceUID),
                  uid != aggregateUID else { continue }
            let transport = readTransportType(id)
            // AirPlay devices can't be aggregated — Audio MIDI Setup hides them too.
            if transport == kAudioDeviceTransportTypeAirPlay { continue }
            newDevices.append(AudioDevice(id: id, name: name, uid: uid,
                                          canSetVolume: checkSettable(id),
                                          transportType: transport))
        }

        let freshIDs = Set(newDevices.map { $0.id })

        // Sub-devices absorbed into our aggregate disappear from CoreAudio's
        // global list, so we re-inject them. But only those still active in the
        // aggregate — a Bluetooth device that physically disconnects also falls
        // out of the global list, and we must NOT preserve those.
        let stillActive = activeSubdeviceIDs()
        let preserved: [AudioDevice] = aggregateID != nil
            ? devices.filter { selectedIDs.contains($0.id) && !freshIDs.contains($0.id) && stillActive.contains($0.id) }
            : []
        newDevices += preserved

        if newDevices != devices { devices = newDevices }
        let keepIDs = Set(newDevices.map { $0.id })
        let filteredVolumes = volumes.filter { keepIDs.contains($0.key) }
        if filteredVolumes != volumes { volumes = filteredVolumes }
        preMuteVolumes = preMuteVolumes.filter { keepIDs.contains($0.key) }
        volumeAddressCache = volumeAddressCache.filter { keepIDs.contains($0.key) }

        let trulyGone = selectedIDs.subtracting(keepIDs)
        if !trulyGone.isEmpty {
            selectedIDs = selectedIDs.subtracting(trulyGone)
            updateAggregate()
        }

        syncSelectionToExternalDefault()
    }

    private func allDeviceIDs() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(systemObject, &addr, 0, nil, &size)
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &ids)
        return ids
    }

    private func activeSubdeviceIDs() -> Set<AudioDeviceID> {
        guard let agg = aggregateID else { return [] }
        var addr = AudioObjectPropertyAddress(kAudioAggregateDevicePropertyActiveSubDeviceList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(agg, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(agg, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return Set(ids)
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
        guard AudioObjectGetPropertyData(systemObject, &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    private func setDefault(_ id: AudioDeviceID) {
        var addr = AudioObjectPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var devID = id
        AudioObjectSetPropertyData(systemObject, &addr, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &devID)
    }

    // MARK: - Volume

    // Returns the first element (0 or 1) that actually has the volume property,
    // and is settable. Using AudioObjectHasProperty before IsPropertySettable
    // avoids false positives on built-in devices where IsPropertySettable
    // returns true but writes are silently ignored. Cached because slider drags
    // probe this dozens of times per second per device.
    private func settableVolumeAddress(for id: AudioDeviceID) -> AudioObjectPropertyAddress? {
        if let cached = volumeAddressCache[id] { return cached }
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1] {
            var addr = AudioObjectPropertyAddress(kAudioDevicePropertyVolumeScalar,
                                                  kAudioDevicePropertyScopeOutput,
                                                  element)
            guard AudioObjectHasProperty(id, &addr) else { continue }
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(id, &addr, &settable) == noErr,
                  settable.boolValue else { continue }
            volumeAddressCache[id] = addr
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

    // MARK: - External volume sync
    //
    // CoreAudio fires this whenever a device's volume changes — from any
    // source: our own writeVolume, the system volume slider in Control
    // Center, hardware volume keys we passed through (single-device mode),
    // AppleScript, etc. Pulling the latest value here keeps the per-device
    // slider in sync with the world; without it, single-device mode's
    // sliders go stale the moment the user touches anything outside Tutti.

    private func syncVolumeListeners(old: Set<AudioDeviceID>) {
        let now = selectedIDs
        for id in now.subtracting(old) { addVolumeListener(for: id) }
        for id in old.subtracting(now) { removeVolumeListener(for: id) }
    }

    private func addVolumeListener(for id: AudioDeviceID) {
        guard volumeListeners[id] == nil,
              let addr = settableVolumeAddress(for: id) else { return }
        var a = addr
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.externalVolumeDidChange(for: id) }
        }
        let status = AudioObjectAddPropertyListenerBlock(id, &a, nil, block)
        guard status == noErr else { return }
        volumeListeners[id] = VolumeListener(address: addr, block: block)
    }

    private func removeVolumeListener(for id: AudioDeviceID) {
        guard var token = volumeListeners.removeValue(forKey: id) else { return }
        // Removing a listener on a device that has since been invalidated
        // (e.g. Bluetooth disconnect) returns a non-zero OSStatus; the
        // listener tears down with the device, so dropping the token is
        // enough. Ignore the return value.
        _ = AudioObjectRemovePropertyListenerBlock(id, &token.address, nil, token.block)
    }

    private func externalVolumeDidChange(for id: AudioDeviceID) {
        guard let newVol = readVolume(id) else { return }
        if volumes[id] != newVol {
            volumes[id] = newVol
            // If an external slider drags this device past 0, clear any
            // stale pre-mute hint so a follow-up un-mute uses a sensible
            // default instead of restoring an unrelated past volume.
            if newVol > 0 {
                preMuteVolumes.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Orphan cleanup & device listener

    private func cleanupOrphans() {
        for id in allDeviceIDs() {
            guard let uid = stringProp(id, kAudioDevicePropertyDeviceUID) else { continue }
            // Also destroy leftover MultiOut aggregate from before the rename
            if uid == aggregateUID || uid == legacyMultiOutUID {
                AudioHardwareDestroyAggregateDevice(id)
            }
        }
    }

    private func startListening() {
        var devAddr = AudioObjectPropertyAddress(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(systemObject, &devAddr, nil) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshDevices() }
        }

        // Detect when something external (System Settings, Control Center) changes
        // the default output away from our aggregate device
        var defAddr = AudioObjectPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(systemObject, &defAddr, nil) { [weak self] _, _ in
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

    private func syncSelectionToExternalDefault() {
        guard aggregateID == nil else { return }
        guard let id = readDefault(),
              devices.contains(where: { $0.id == id }) else { return }
        if selectedIDs == [id] { return }
        if volumes[id] == nil { volumes[id] = readVolume(id) ?? 1.0 }
        selectedIDs = [id]
    }

    // MARK: - Battery polling

    /// `system_profiler SPBluetoothDataType` is a 1-3s subprocess; polling every
    /// 60s while the popover is closed is mostly wasted. Run fast (60s) only while
    /// the user is looking at the panel; coast at 10min in the background so
    /// numbers stay roughly current without burning CPU.
    func setPopoverVisible(_ visible: Bool) {
        guard popoverIsOpen != visible else { return }
        popoverIsOpen = visible
        startBatteryPolling()
    }

    private func startBatteryPolling() {
        batteryTask?.cancel()
        let interval: Duration = popoverIsOpen ? .seconds(60) : .seconds(600)
        batteryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.refreshBatteryLevels()
                try? await Task.sleep(for: interval)
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
        if newLevels != batteryLevels { batteryLevels = newLevels }
    }

    // MARK: - System volume key handling

    // Aggregate devices don't expose master volume to CoreAudio, so the system
    // volume slider is greyed out when our aggregate is the default. We intercept
    // the hardware volume keys globally and apply the change to all sub-devices.
    // SwiftUI Timer.publish in a MenuBarExtra popover isn't reliable — alt-tab-macos
    // uses a DispatchSourceTimer on a background queue for the same reason.
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
        let tapRunning = volumeKeyMonitor?.isRunning ?? false
        let now = axTrusted || tapRunning
        if now != hasAccessibilityPermission {
            hasAccessibilityPermission = now
        }
        // Revocation requires app restart anyway, so once we've confirmed both
        // signals are positive we can stop polling.
        if now && tapRunning {
            permissionTimer?.cancel()
            permissionTimer = nil
        }
    }

    private func startVolumeKeyMonitoring() {
        volumeKeyMonitor = VolumeKeyMonitor(
            onKey: { [weak self] action in
                Task { @MainActor [weak self] in
                    self?.handleVolumeKey(action)
                }
            },
            onUnauthorized: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.triggerVolumeKeyUpgradePrompt()
                }
            }
        )
        // No prompt at startup — the system permission dialog only appears
        // when the user explicitly clicks "去授权" in Settings (after they
        // have or want Pro). Free-tier users never see an unsolicited
        // accessibility prompt for a feature they can't use.
        volumeKeyMonitor?.start(promptForPermission: false)
    }

    /// Called when a free / expired-trial user hits a Pro-only path.
    /// Throttled so a 5-second volume drag doesn't fire the banner dozens
    /// of times. The throttle is shared across reasons on purpose — back-to-back
    /// attempts from different features still feel like one upsell event.
    func triggerUpgradePrompt(reason: UpgradeReason) {
        guard !LicenseManager.hasProAccess else { return }
        let now = Date()
        if let last = lastVolumeKeyUpgradePromptAt,
           now.timeIntervalSince(last) < 30 {
            return
        }
        lastVolumeKeyUpgradePromptAt = now
        pendingUpgradeReason = reason
        lastUpgradeAttemptID = UUID()
    }

    /// Back-compat alias for the hardware volume-key / scroll path. Kept so
    /// VolumeKeyMonitor and existing scroll handlers don't need to know about
    /// the reason enum.
    func triggerVolumeKeyUpgradePrompt() {
        triggerUpgradePrompt(reason: .volumeTakeover)
    }

    /// Pro-gated. Replaces the selected device set with the devices matching
    /// `uids`. Free users get an upgrade banner instead of an apply.
    func applyProfile(uids: [String]) {
        guard LicenseManager.hasProAccess else {
            triggerUpgradePrompt(reason: .profile)
            return
        }
        selectedIDs = Set(devices.filter { uids.contains($0.uid) }.map { $0.id })
        updateAggregate()
    }

    /// Scroll on the menu bar icon. Pro-gated, with OSD feedback.
    /// Unlike the hardware volume key (which only takes over in aggregate mode
    /// to avoid fighting the system OSD), scroll always belongs to Tutti — the
    /// system never receives it. So we adjust whenever any device is selected,
    /// including the single-device case.
    func handleScrollVolumeAdjust(by delta: Float) {
        guard LicenseManager.hasProAccess else {
            triggerVolumeKeyUpgradePrompt()
            return
        }
        guard !selectedIDs.isEmpty else { return }
        adjustAllVolumes(by: delta)
        let names = devices.filter { selectedIDs.contains($0.id) }.map { $0.name }
        VolumeOSDController.shared.show(volume: masterVolume, isMuted: isMuted, deviceNames: names)
    }

    private func handleVolumeKey(_ action: VolumeKeyAction) {
        guard isActive else { return }
        switch action {
        case .adjust(let delta):
            adjustAllVolumes(by: delta)
        case .mute:
            toggleMasterMute()
        }
        let names = devices.filter { selectedIDs.contains($0.id) }.map { $0.name }
        guard !names.isEmpty else { return }
        VolumeOSDController.shared.show(volume: masterVolume, isMuted: isMuted, deviceNames: names)
    }

    func adjustAllVolumes(by delta: Float) {
        for id in selectedIDs {
            let current = volumes[id] ?? 1.0
            let newVol = max(0, min(1, current + delta))
            // When a downward drag forces a device to 0, remember its pre-drag
            // volume so a follow-up mute-toggle can restore it. Raising past 0
            // is handled by setVolume's existing clear logic.
            if newVol == 0 && current > 0 {
                preMuteVolumes[id] = current
            }
            setVolume(newVol, for: id)
        }
    }
}
