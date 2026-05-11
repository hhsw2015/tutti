import Foundation

enum BluetoothBattery {
    // Exclude case battery — for headphones it can be very low while the buds
    // themselves are full, which would be misleading as a single readout.
    private static let batteryKeys = [
        "device_batteryLevelMain",
        "device_batteryLevelLeft",
        "device_batteryLevelRight"
    ]

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
        batteryKeys.compactMap { dict[$0] as? String }.compactMap(parsePercent).min()
    }

    private static func parsePercent(_ s: String) -> Int? {
        Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }
}
