import Foundation
import IOKit.ps

struct PowerState: Equatable {
    var percent: Int
    var isCharging: Bool
    var onAC: Bool
}

/// Internal battery state with a callback when the power source changes.
@MainActor
final class PowerMonitor {
    var onChange: ((PowerState) -> Void)?
    private(set) var state: PowerState?
    private var source: CFRunLoopSource?

    func start() {
        state = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let me = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { me.refresh() }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func refresh() {
        let new = Self.read()
        guard new != state else { return }
        state = new
        if let new { onChange?(new) }
    }

    nonisolated static func read() -> PowerState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            return PowerState(percent: max > 0 ? current * 100 / max : current,
                              isCharging: desc[kIOPSIsChargingKey] as? Bool ?? false,
                              onAC: desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}

struct HeadphoneBattery: Equatable {
    var name: String
    /// Ordered labels such as 왼쪽/오른쪽/케이스 or 배터리, with percentages.
    var levels: [(label: String, percent: Int)]

    static func == (a: HeadphoneBattery, b: HeadphoneBattery) -> Bool {
        a.name == b.name && a.levels.map(\.percent) == b.levels.map(\.percent)
    }
}

/// Reads connected headphone battery levels from `system_profiler`, which is
/// the only place macOS exposes them without private frameworks.
enum HeadphoneBatteryReader {
    private static let keys: [(String, String)] = [
        ("device_batteryLevelLeft", "왼쪽"),
        ("device_batteryLevelRight", "오른쪽"),
        ("device_batteryLevelCase", "케이스"),
        ("device_batteryLevelMain", "배터리"),
    ]

    static func read() -> HeadphoneBattery? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(data)
    }

    static func parse(_ data: Data) -> HeadphoneBattery? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any],
                          let type = info["device_minorType"] as? String,
                          type == "Headphones" || type == "Headset" else { continue }
                    let levels = keys.compactMap { key, label -> (String, Int)? in
                        guard let text = info[key] as? String,
                              let percent = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "%"))) else { return nil }
                        return (label, percent)
                    }
                    if !levels.isEmpty { return HeadphoneBattery(name: name, levels: levels.map { ($0.0, $0.1) }) }
                }
            }
        }
        return nil
    }
}
