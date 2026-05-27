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
//   - verdict: REJECTED for script-driven discovery. CAVEAT: behavior inside a
//     signed/notarized .app with local-network entitlements may differ; if all
//     other paths also fail in their respective contexts, re-test Path 1
//     bundled in Tutti before final dismissal.
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
func runPath2() { print("\n=== Path 2: AVOutputContext class methods ===\n"); /* Task 0.3 fills in */ }
func runPath3() { print("\n=== Path 3: NetServiceBrowser + AVOutputDevice mapping ===\n"); /* Task 0.4 fills in */ }
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
