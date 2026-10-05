import Foundation
import Testing
@testable import Nunsseop

struct HeadphoneBatteryTests {
    private func data(_ connected: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["SPBluetoothDataType": [["device_connected": connected]]])
    }

    @Test func readsHeadphoneLevels() throws {
        let json = try data([
            ["Mouse": ["device_minorType": "Mouse", "device_batteryLevelMain": "50%"]],
            ["AirPods Pro": ["device_minorType": "Headphones", "device_batteryLevelLeft": "90%",
                             "device_batteryLevelRight": "85%", "device_batteryLevelCase": "60%"]],
        ])
        let battery = try #require(HeadphoneBatteryReader.parse(json))
        #expect(battery.name == "AirPods Pro")
        #expect(battery.levels.map(\.percent) == [90, 85, 60])
    }

    @Test func readsHeadsetMainBattery() throws {
        let json = try data([["Headset": ["device_minorType": "Headset", "device_batteryLevelMain": "40%"]]])
        #expect(HeadphoneBatteryReader.parse(json)?.levels.map(\.percent) == [40])
    }

    @Test func ignoresOtherDevicesAndBadData() throws {
        #expect(HeadphoneBatteryReader.parse(try data([["Mouse": ["device_minorType": "Mouse", "device_batteryLevelMain": "50%"]]])) == nil)
        #expect(HeadphoneBatteryReader.parse(try data([["Buds": ["device_minorType": "Headphones"]]])) == nil)
        #expect(HeadphoneBatteryReader.parse(Data("not json".utf8)) == nil)
        #expect(HeadphoneBatteryReader.parse(Data("{}".utf8)) == nil)
    }
}
