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

func runPath1() { print("\n=== Path 1: AVOutputDeviceDiscoverySession ===\n"); /* Task 0.2 fills in */ }
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
