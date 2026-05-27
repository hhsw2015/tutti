#!/usr/bin/env swift
//
// AirPlay discovery API spike — tries each candidate path and prints findings.
// Standalone Swift script; run with: swift scripts/airplay-spike.swift [path1|path2|path3|path4|all]
//
// Background: macOS doesn't expose a public API to enumerate LAN AirPlay
// devices (only the currently-routed one via Core Audio HAL). This script
// probes four ObjC-runtime + Bonjour candidates to find an enumeration
// method that survives notarization and works on macOS 26+.
//
// Path 1 result (run 2026-05-27, macOS 26.5, unsigned `swift` CLI):
//   - class found: yes (AVOutputDeviceDiscoverySession)
//   - notable selectors: initWithDeviceFeatures:, setDiscoveryMode:,
//     availableOutputDevices, fastDiscoveryEnabled, impl, routeDiscoverer,
//     outputDeviceDiscoverySessionImplDidChangeAvailableOutputDevices:
//   - default init() returns nil; must use initWithDeviceFeatures: (1,2,4,8,0xFFFF accepted)
//   - session is real (non-nil impl: AVFigRouteDiscovererOutputDeviceDiscoverySessionImpl)
//   - impl talks to a Fig daemon over XPC (has _serverDied callback)
//   - devices enumerated by end-to-end probe: 0 across discoveryMode=1,2,3 with 8s wait + fastDiscoveryEnabled
//   - meets 5-criteria validation: no (criterion 1 + 4 both fail in script context)
//
// Path 1 signed-binary re-test (run 2026-05-27, macOS 26.5):
//   Hypothesis: Fig daemon refuses unsigned/unentitled clients; a notarization-
//   class signed binary may receive a populated device list.
//   Method: standalone swiftc-compiled Mach-O, signed with Developer ID
//   Application (BaoLin Wu, RFW398ARA9), --options runtime --timestamp.
//   Same code (direct IMP calls for initWithDeviceFeatures:0xFFFF,
//   setDiscoveryMode:2, setFastDiscoveryEnabled:true), 10s poll.
//   Results across three signing contexts (LAN had 4+ live AirPlay devices
//   confirmed via `dns-sd -B _airplay._tcp local.`):
//     - signed Developer ID + Hardened Runtime + timestamp:  0 devices (exit 2)
//     - signed Developer ID + Hardened Runtime + network entitlements
//       (com.apple.security.network.client/.server):         0 devices (exit 2)
//     - ad-hoc / unsigned compiled binary:                   0 devices (exit 2)
//   Impl is non-nil in all cases; the framework just never populates the array.
//   Note: when using KVC setValue(forKey:"discoveryMode") instead of a direct
//   setDiscoveryMode: IMP call, signed binaries crash inside
//   -[AVOutputDeviceDiscoverySession setDiscoveryMode:forClientIdentifiers:]
//   at offset 312 (KERN_INVALID_ADDRESS at 0x8). That crash is a Swift-bridging
//   artifact unrelated to discovery — direct IMP calls work cleanly.
//
//   verdict: REJECTED for real. Signing/entitlements do not unlock this API
//   from a Developer ID context. The Fig daemon appears to gate AirPlay device
//   enumeration on something stronger than code signature — likely a private
//   first-party entitlement (com.apple.private.avfoundation.* family) or an
//   Apple-team-id check. Move on to Path 2/3/4.
//
// Path 2 result (run 2026-05-27, macOS 26.5):
//   - class found: yes (AVOutputContext)
//   - total class methods sweeped: 25
//   - interesting selectors (20): outputContext, auxiliaryOutputContext,
//     defaultSharedOutputContext, outputContextForControllingOutputDeviceGroupWithID:options:,
//     outputContextExistsWithRemoteOutputDevice, resetOutputDeviceForAllOutputContexts,
//     sharedSystemAudioContext, outputContextWithFigRoutingContextCreator:,
//     outputContextWithFigRoutingContextCreator:communicationChannelManagerCreator:,
//     sharedAudioPresentationOutputContext, outputContextForControllingOutputDeviceGroupWithID:,
//     outputContextForID:, defaultOutputContextImplClass,
//     outputContextWithFigRoutingContextCreator:volumeController:,
//     outputContextWithFigRoutingContextCreator:outputDeviceTranslator:,
//     sharedSystemRemotePoolContext, sharedSystemScreenContext,
//     allSharedAudioOutputContexts, addSharedAudioOutputContext,
//     sharedSystemRemoteDisplayContext
//   - non-nil array-returning methods:
//       +allSharedAudioOutputContexts -> NSArray of 4 AVOutputContext
//         (UUIDs, type=AVOutputContextTypeAudio) — but these are AUDIO CONTEXTS,
//         not devices. Each context's outputDevice = nil, outputDevices = [].
//   - other non-nil singletons (all AVOutputContext, not devices):
//       +outputContext (video), +auxiliaryOutputContext (video),
//       +defaultSharedOutputContext (audio), +addSharedAudioOutputContext (audio),
//       +defaultOutputContextImplClass (returns AVFigRoutingContextOutputContextImpl class)
//   - drill-down: probed instance methods (62 total). outputDevice/outputDevices
//     properties exist but are nil/empty even after 5s poll on every context,
//     including +iTunesAudioContext. The class is a routing SINK abstraction
//     (setOutputDevice:, addOutputDevice:, removeOutputDevice:), not a discovery
//     source — it expects you to already have an AVOutputDevice from elsewhere.
//   - meets 5-criteria validation: NO (criterion 1: 0 AirPlay devices visible;
//     criterion 2: contexts are not AVOutputDevice-shaped; criterion 4: empty)
//   - verdict: REJECTED
//   - notes: confirms Path 1's finding — AirPlay device enumeration is gated at
//     the Fig daemon level regardless of which AVFoundation surface you use.
//     AVOutputContext is downstream of discovery, not a discovery API itself.
//     Move on to Path 3 (NetServiceBrowser + AVOutputDevice mapping).
//
// Path 3 result (run 2026-05-27, macOS 26.5):
//   - Bonjour _airplay._tcp services discovered: 5
//       * Barry's HomePod 2 @ Barrys-HomePod-2.local.:7000
//       * Barry's TV @ Barrys-TV.local.:7000  (Apple TV)
//       * Fanny's MacBook Air @ Fanny.local.:7000
//       * Barry's Mac Studio @ Barrys-Mac-Studio.local.:7000
//       * Barry's MacBook Neo @ Barrys-MacBook-Neo.local.:7000
//     (Bonjour is NOT entitlement-gated — works fine from unsigned swift CLI.)
//   - AVOutputDevice class found: yes
//   - AVOutputDevice class methods (12 total):
//       initialize, sharedLocalDevice, localDeviceDidChange,
//       outputDeviceWithFigEndpoint:,
//       outputDeviceWithFigEndpoint:routingContextFactory:,
//       outputDeviceWithFigEndpoint:volumeController:,
//       outputDeviceWithRouteDescriptor:,
//       outputDeviceWithRouteDescriptor:routeDiscoverer:,
//       outputDeviceWithRouteDescriptor:routingContextFactory:,
//       outputDeviceWithRouteDescriptor:volumeController:,
//       outputDeviceWithRouteDescriptor:withRoutingContext:,
//       prefersRouteDescriptors
//   - Common public-shape factory selectors that exist: NONE
//       (deviceWithUID:, deviceWithName:, deviceWithHost:, deviceWithIdentifier:,
//        outputDeviceWithUID:, outputDeviceWithIdentifier: all absent)
//   - Real factories require opaque CoreMedia private types as input:
//       FigEndpointRef        — a MediaToolbox CFTypeRef produced by the Fig
//                               routing daemon's discovery pipeline
//       RouteDescriptorRef    — same family, also Fig-daemon-sourced
//     NSClassFromString("FigEndpoint"), "AVFigEndpoint", "FigRoutingContextEndpoint",
//     "AVOutputDeviceRouteDescriptor" all return nil. The visible classes in
//     AVFoundation are wrappers like AVFigEndpointOutputDeviceImpl /
//     AVFigRouteDescriptorOutputDeviceImpl that CONSUME these refs internally;
//     there is no public way to mint a FigEndpoint from a Bonjour hostname.
//   - meets 5-criteria validation: no
//   - verdict: REJECTED
//   - notes: Bonjour discovery itself works perfectly and we can see every
//     AirPlay endpoint on the LAN. But the bridge from "I have a hostname and
//     port" to "I have an AVOutputDevice the rest of AVFoundation will accept"
//     does not exist in any reachable form. AVOutputDevice factories all
//     require Fig-daemon-produced opaque refs, which is exactly the gate that
//     blocked Paths 1 and 2. Bonjour alone is useful for *listing* devices but
//     not for *switching* — and even listing would require us to reimplement
//     the AirPlay capability/feature parsing the Fig daemon already does from
//     TXT records. Move on to Path 4 (MRMediaRemoteService).
//

import Foundation
import AVFoundation
import ObjectiveC.runtime

// MARK: - Reflection helpers

func classExists(_ name: String) -> NSObject.Type? {
    return NSClassFromString(name) as? NSObject.Type
}

func printClassMethods(_ cls: AnyClass) {
    // Instance methods
    var instCount: UInt32 = 0
    if let instMethods = class_copyMethodList(cls, &instCount) {
        for i in 0..<Int(instCount) {
            let sel = method_getName(instMethods[i])
            print("  - instance: \(sel)")
        }
        free(instMethods)
    }

    // Class methods (live on the metaclass)
    if let meta: AnyClass = object_getClass(cls) {
        var classCount: UInt32 = 0
        if let classMethods = class_copyMethodList(meta, &classCount) {
            for i in 0..<Int(classCount) {
                let sel = method_getName(classMethods[i])
                print("  + class: \(sel)")
            }
            free(classMethods)
        }
    }
}

// MARK: - Path runners (defined in subsequent tasks)

func runPath1() {
    print("\n=== Path 1: AVOutputDeviceDiscoverySession ===\n")
    guard let cls = classExists("AVOutputDeviceDiscoverySession") else {
        print("[Path 1] NSClassFromString returned nil — class doesn't exist on this macOS")
        return
    }
    print("[Path 1] Class found: \(cls)")
    print("[Path 1] Methods:")
    printClassMethods(cls)

    // Try common init patterns
    let initSelectors = [
        "init",
        "initWithDeviceType:",
        "initWithRequestedDeviceTypes:",
        "discoverySessionForRequestedDeviceTypes:",
    ]

    for selName in initSelectors {
        let sel = NSSelectorFromString(selName)
        if cls.responds(to: sel) {
            print("[Path 1] +[\(cls) \(selName)] responds")
        }
    }

    // Try instantiating with no args
    let session = cls.init()
    print("[Path 1] Default init result: \(session)")

    // Look for delegate-related selectors
    var instCount: UInt32 = 0
    if let methods = class_copyMethodList(cls, &instCount) {
        for i in 0..<Int(instCount) {
            let sel = method_getName(methods[i])
            let selStr = NSStringFromSelector(sel)
            if selStr.contains("delegate") || selStr.contains("start") || selStr.contains("device") {
                print("[Path 1] interesting instance selector: \(selStr)")
            }
        }
        free(methods)
    }

    // End-to-end probe: try to enumerate devices.
    // API shape inferred from selectors:
    //   - init() → session
    //   - setDiscoveryMode: takes an integer; non-zero likely activates scanning
    //   - availableOutputDevices returns NSArray of AVOutputDevice
    // No explicit start; discovery turns on via discoveryMode > 0.
    print("\n[Path 1] === End-to-end probe ===")
    // Plain init() returns nil on macOS — must use initWithDeviceFeatures: or the factory.
    // Try the factory class method first.
    var probeSession: NSObject? = nil

    let factorySel = NSSelectorFromString("outputDeviceDiscoverySessionFactory")
    if let meta = object_getClass(cls), class_respondsToSelector(meta, factorySel) {
        let factoryResult = (cls as AnyObject).perform(factorySel)?.takeUnretainedValue()
        print("[Path 1] factory result: \(String(describing: factoryResult))")
    }

    // Try initWithDeviceFeatures: with various values.
    // AVOutputDeviceFeatures is likely a bitmask. 0 = audio? 1 = video? Let's try several.
    let allocSel = NSSelectorFromString("alloc")
    typealias AllocFn = @convention(c) (AnyClass, Selector) -> NSObject?
    let allocImp = method_getImplementation(class_getClassMethod(cls, allocSel)!)
    let allocFn = unsafeBitCast(allocImp, to: AllocFn.self)

    for features in [UInt(0), 1, 2, 4, 8, 0xFF, 0xFFFF, ~UInt(0)] {
        guard let alloc = allocFn(cls, allocSel) else {
            print("[Path 1] alloc returned nil")
            continue
        }
        let initSel = NSSelectorFromString("initWithDeviceFeatures:")
        guard let imp = alloc.method(for: initSel) else {
            print("[Path 1] no IMP for initWithDeviceFeatures: on alloc")
            continue
        }
        typealias InitFn = @convention(c) (NSObject, Selector, UInt) -> NSObject?
        let fn = unsafeBitCast(imp, to: InitFn.self)
        let s = fn(alloc, initSel, features)
        let ptrStr = s.map { String(describing: Unmanaged.passUnretained($0).toOpaque()) } ?? "nil"
        print("[Path 1] initWithDeviceFeatures:0x\(String(features, radix: 16)) -> \(String(describing: s)) ptr=\(ptrStr)")
        if let s = s, probeSession == nil {
            probeSession = s
        }
    }

    guard let probeSession = probeSession else {
        print("[Path 1] ABORT: could not construct a non-nil session")
        return
    }
    print("[Path 1] using session: \(probeSession) class=\(String(describing: object_getClass(probeSession)))")

    // Use KVC for property reads
    let initialMode = probeSession.value(forKey: "discoveryMode")
    print("[Path 1] initial discoveryMode: \(String(describing: initialMode))")

    let initialDevices = probeSession.value(forKey: "availableOutputDevices")
    print("[Path 1] initial availableOutputDevices: \(String(describing: initialDevices))")

    let impl = probeSession.value(forKey: "impl")
    print("[Path 1] impl: \(String(describing: impl))")

    // Dump impl methods so we can see what controls discovery
    if let implObj = impl as AnyObject?, let implCls: AnyClass = object_getClass(implObj) {
        print("[Path 1] impl class: \(implCls)")
        var n: UInt32 = 0
        if let ms = class_copyMethodList(implCls, &n) {
            print("[Path 1] impl instance methods:")
            for i in 0..<Int(n) {
                let sel = method_getName(ms[i])
                print("  - \(NSStringFromSelector(sel))")
            }
            free(ms)
        }
    }

    // Helper: set discoveryMode via direct IMP call (KVC won't bridge NSNumber → NSInteger cleanly here)
    func setMode(_ session: NSObject, _ mode: Int) {
        let setSel = NSSelectorFromString("setDiscoveryMode:")
        guard let imp = session.method(for: setSel) else {
            print("[Path 1] method(for: setDiscoveryMode:) returned nil")
            return
        }
        typealias SetModeFn = @convention(c) (NSObject, Selector, Int) -> Void
        let fn = unsafeBitCast(imp, to: SetModeFn.self)
        fn(session, setSel, mode)
    }

    // Helper: safely read a KVC key, catching valueForUndefinedKey: by checking the class first.
    func safeReadAttribute(_ obj: NSObject, _ keys: [String]) -> [String: Any] {
        var result: [String: Any] = [:]
        let cls: AnyClass = object_getClass(obj)!
        for key in keys {
            let sel = NSSelectorFromString(key)
            // Walk the class chain to be sure the getter exists
            if class_getInstanceMethod(cls, sel) != nil {
                if let v = obj.value(forKey: key) {
                    result[key] = v
                }
            }
        }
        return result
    }

    // First, dump AVOutputDevice instance methods so we know what to read.
    if let outDevCls: AnyClass = NSClassFromString("AVOutputDevice") {
        print("\n[Path 1] AVOutputDevice instance methods:")
        var n: UInt32 = 0
        if let ms = class_copyMethodList(outDevCls, &n) {
            for i in 0..<Int(n) {
                let sel = method_getName(ms[i])
                print("  - \(NSStringFromSelector(sel))")
            }
            free(ms)
        }
    }

    // Try a wide feature mask (0xFFFF should include audio + video AirPlay).
    // Construct a session with broader features for the discovery loop.
    let allocForDiscovery = allocFn(cls, allocSel)!
    let initSel = NSSelectorFromString("initWithDeviceFeatures:")
    let initImp = allocForDiscovery.method(for: initSel)!
    typealias InitFn = @convention(c) (NSObject, Selector, UInt) -> NSObject?
    let initFn = unsafeBitCast(initImp, to: InitFn.self)
    let wideSession = initFn(allocForDiscovery, initSel, 0xFFFF) ?? probeSession
    print("\n[Path 1] discovery session (features=0xFFFF): \(wideSession)")

    // Set fastDiscoveryEnabled and observe KVO-style availableOutputDevices changes
    let fastSel = NSSelectorFromString("setFastDiscoveryEnabled:")
    if let fastImp = wideSession.method(for: fastSel) {
        typealias BoolFn = @convention(c) (NSObject, Selector, Bool) -> Void
        let fn = unsafeBitCast(fastImp, to: BoolFn.self)
        fn(wideSession, fastSel, true)
        print("[Path 1] fastDiscoveryEnabled set to true")
    }

    // Try each plausible discovery mode value with a longer wait
    for mode in [1, 2, 3] {
        print("\n[Path 1] --- Trying discoveryMode = \(mode), 8s wait ---")
        setMode(wideSession, mode)
        let actualMode = wideSession.value(forKey: "discoveryMode")
        print("[Path 1] discoveryMode after set: \(String(describing: actualMode))")

        // Wait for discovery — AirPlay/Bonjour can take 5+ seconds
        let deadline = Date(timeIntervalSinceNow: 8.0)
        var lastCount = -1
        while Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            if let arr = wideSession.value(forKey: "availableOutputDevices") as? [AnyObject], arr.count != lastCount {
                print("[Path 1]   t=\(String(format: "%.1f", 8.0 - deadline.timeIntervalSinceNow))s -> \(arr.count) device(s)")
                lastCount = arr.count
            }
        }

        let devicesAny = wideSession.value(forKey: "availableOutputDevices")
        guard let devices = devicesAny as? [AnyObject] else {
            print("[Path 1] availableOutputDevices not an array: \(String(describing: devicesAny))")
            continue
        }
        print("[Path 1] mode=\(mode) FINAL: \(devices.count) device(s)")
        for d in devices {
            guard let obj = d as? NSObject else { continue }
            let className = String(describing: object_getClass(obj) ?? type(of: d) as AnyClass)
            let attrs = safeReadAttribute(obj, [
                "name", "modelID", "deviceType", "deviceFeatures",
                "deviceID", "ID", "manufacturer",
                "supportsBufferedAirPlay", "airPlayProperties",
            ])
            print("  - [\(className)] \(attrs)")
            if let avOutputDeviceCls = NSClassFromString("AVOutputDevice") {
                print("    isAVOutputDevice: \(obj.isKind(of: avOutputDeviceCls))")
            }
        }
    }

    // Reset to off
    setMode(probeSession, 0)
}
func runPath2() {
    print("\n=== Path 2: AVOutputContext class methods sweep ===\n")
    guard let cls = classExists("AVOutputContext") else {
        print("[Path 2] AVOutputContext NSClassFromString returned nil — unexpected, was found in v0.3.0 spike")
        return
    }
    print("[Path 2] Class found: \(cls)")

    guard let meta: AnyClass = object_getClass(cls) else {
        print("[Path 2] No metaclass — abort")
        return
    }

    var classCount: UInt32 = 0
    guard let classMethods = class_copyMethodList(meta, &classCount) else {
        print("[Path 2] class_copyMethodList returned nil")
        return
    }
    defer { free(classMethods) }

    print("[Path 2] All \(classCount) class methods:")
    var interesting: [String] = []
    for i in 0..<Int(classCount) {
        let sel = method_getName(classMethods[i])
        let selStr = NSStringFromSelector(sel)
        print("  + \(selStr)")
        let lower = selStr.lowercased()
        let keywords = ["discover", "candidate", "available", "browse", "session", "all", "shared", "output"]
        if keywords.contains(where: { lower.contains($0) }) {
            interesting.append(selStr)
        }
    }

    print("\n[Path 2] Interesting selectors (discovery-adjacent):")
    for sel in interesting { print("  ★ \(sel)") }

    // Try invoking each interesting class method with no args; check return type
    for selStr in interesting {
        let sel = NSSelectorFromString(selStr)
        guard cls.responds(to: sel) else { continue }
        // Only invoke methods with 0 args (no colon = no params)
        if !selStr.contains(":") {
            let result = cls.perform(sel)?.takeUnretainedValue()
            print("[Path 2] +[\(cls) \(selStr)] → \(String(describing: result))")
            if let array = result as? NSArray {
                print("    array of \(array.count) elements")
                for item in array {
                    print("    - \(type(of: item)): \(item)")
                }
            }
        }
    }
}
func runPath3() {
    print("\n=== Path 3: NetServiceBrowser + AVOutputDevice mapping ===\n")

    // Phase 3a: Can we discover AirPlay endpoints via mDNS?
    let browser = NetServiceBrowser()
    let delegate = NetServiceBrowserDelegateImpl()
    browser.delegate = delegate
    browser.searchForServices(ofType: "_airplay._tcp.", inDomain: "local.")

    // Run RunLoop for 3 seconds to give Bonjour time to discover
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }

    browser.stop()

    print("[Path 3a] Discovered \(delegate.services.count) _airplay._tcp services:")
    for svc in delegate.services {
        print("  - \(svc.name) @ \(svc.hostName ?? "?"):\(svc.port)")
    }

    if delegate.services.isEmpty {
        print("[Path 3a] No services found — Bonjour either restricted or no AirPlay endpoints on LAN")
        return
    }

    // Phase 3b: Try to construct AVOutputDevice for the first endpoint
    guard let avOutputDeviceCls = classExists("AVOutputDevice") else {
        print("[Path 3b] AVOutputDevice class not found")
        return
    }

    print("\n[Path 3b] AVOutputDevice class found, inspecting class methods:")
    guard let meta: AnyClass = object_getClass(avOutputDeviceCls) else { return }
    var count: UInt32 = 0
    if let methods = class_copyMethodList(meta, &count) {
        for i in 0..<Int(count) {
            print("  + \(NSStringFromSelector(method_getName(methods[i])))")
        }
        free(methods)
    }

    // Also dump instance methods for context — AVOutputDevice's properties
    // tell us what fields a discovery API would need to fill in
    print("\n[Path 3b] AVOutputDevice instance methods (first 30):")
    var icount: UInt32 = 0
    if let methods = class_copyMethodList(avOutputDeviceCls, &icount) {
        for i in 0..<min(Int(icount), 30) {
            print("  - \(NSStringFromSelector(method_getName(methods[i])))")
        }
        free(methods)
    }

    // Common factory selector patterns to try
    let constructorSelectors = [
        "deviceWithUID:",
        "deviceWithName:",
        "deviceWithHost:",
        "deviceWithIdentifier:",
        "outputDeviceWithUID:",
        "outputDeviceWithIdentifier:",
    ]
    print("\n[Path 3b] Trying factory selectors:")
    for selName in constructorSelectors {
        let sel = NSSelectorFromString(selName)
        if avOutputDeviceCls.responds(to: sel) {
            print("  ★ +[AVOutputDevice \(selName)] EXISTS — try invoking")
            if let firstSvc = delegate.services.first, let host = firstSvc.hostName {
                let device = avOutputDeviceCls.perform(sel, with: host)?.takeUnretainedValue()
                print("    result: \(String(describing: device))")
            }
        }
    }
}

class NetServiceBrowserDelegateImpl: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var services: [NetService] = []

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 2)
        services.append(service)
    }
}
func runPath4() { print("\n=== Path 4: MRMediaRemoteService ===\n"); /* Task 0.5 fills in */ }

// MARK: - Entry point

let args = CommandLine.arguments.dropFirst()
let target = args.first ?? "all"

switch target {
case "path1": runPath1()
case "path2": runPath2()
case "path3": runPath3()
case "path4": runPath4()
case "all": runPath1(); runPath2(); runPath3(); runPath4()
default:
    print("Usage: swift scripts/airplay-spike.swift [path1|path2|path3|path4|all]")
    exit(1)
}
