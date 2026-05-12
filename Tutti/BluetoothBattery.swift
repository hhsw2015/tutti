import Foundation

enum BluetoothBattery {
    // AirPods report case battery separately from the buds; case can be near-empty
    // while the earbuds are full, which would mislead as a single readout. Earlier
    // releases used a "Main" key — that key never exists in SPBluetoothDataType
    // JSON, so battery silently returned empty. Real keys are Left/Right/Case.
    private static let prefix = "device_batteryLevel"
    private static let excludedSuffix = "Case"

    static func fetch() async -> [String: Int] {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            // Drop stderr to /dev/null — a 16KB pipe buffer left undrained would
            // deadlock waitUntilExit().
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return parse(data)
            } catch {
                return [:]
            }
        }.value
    }

    static func normalize(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func parse(_ data: Data) -> [String: Int] {
        var result: [String: Int] = [:]
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return [:] }

        for controller in controllers {
            for key in ["device_connected", "device_not_connected"] {
                guard let list = controller[key] as? [[String: Any]] else { continue }
                for entry in list {
                    for (name, info) in entry {
                        guard let dict = info as? [String: Any],
                              let level = lowestBatteryPercent(in: dict) else { continue }
                        result[normalize(name)] = level
                    }
                }
            }
        }
        return result
    }

    private static func lowestBatteryPercent(in dict: [String: Any]) -> Int? {
        dict.compactMap { (key, value) -> Int? in
            guard key.hasPrefix(prefix),
                  !key.hasSuffix(excludedSuffix),
                  let s = value as? String else { return nil }
            return parsePercent(s)
        }.min()
    }

    private static func parsePercent(_ s: String) -> Int? {
        Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }
}
