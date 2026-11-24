import Foundation
import XCTest
@testable import PowerFlow

final class SMCResilienceTests: XCTestCase {
    func testTransientFirstSampleDoesNotPoisonLaterDiscovery() {
        let reader = FlakySMCKeyReader()
        let smc = SMCReader(keyReader: reader)

        // Every key misses on the first full sample.
        let first = smc.readSample(full: true)
        XCTAssertNil(first.packagePowerW)
        XCTAssertNil(first.cpuTemperatureC)
        XCTAssertNil(first.gpuTemperatureC)
        XCTAssertTrue(first.fans.isEmpty)

        reader.values = [
            "PHPC": makeFloatValue(key: "PHPC", value: 5.17),
            "Tp05": makeFloatValue(key: "Tp05", value: 55.2),
            "Tg05": makeFloatValue(key: "Tg05", value: 47.1),
            "FNum": makeUInt8Value(key: "FNum", value: 2),
            "F0Ac": makeFloatValue(key: "F0Ac", value: 1200.0),
            "F1Ac": makeFloatValue(key: "F1Ac", value: 1850.0)
        ]

        let second = smc.readSample(full: true)
        XCTAssertEqual(second.packagePowerW ?? 0, 5.17, accuracy: 0.01)
        XCTAssertEqual(second.cpuTemperatureC ?? 0, 55.2, accuracy: 0.01)
        XCTAssertEqual(second.gpuTemperatureC ?? 0, 47.1, accuracy: 0.01)
        XCTAssertEqual(second.fans.count, 2)
    }

    func testDieTemperatureKeyInvalidOnFirstPassIsUsedLater() {
        let reader = FlakySMCKeyReader()
        reader.values = [
            "Tp05": makeFloatValue(key: "Tp05", value: 0.0) // below the valid die range
        ]
        let smc = SMCReader(keyReader: reader)

        let first = smc.readSample(full: true)
        XCTAssertNil(first.cpuTemperatureC)

        reader.values["Tp05"] = makeFloatValue(key: "Tp05", value: 55.2)

        let second = smc.readSample(full: true)
        XCTAssertEqual(second.cpuTemperatureC ?? 0, 55.2, accuracy: 0.01)
    }

    func testPackagePowerSticksToFirstSuccessfulKey() {
        let reader = FlakySMCKeyReader()
        reader.values = [
            "PHPC": makeFloatValue(key: "PHPC", value: 5.17),
            "PCPC": makeFloatValue(key: "PCPC", value: 7.0)
        ]
        let smc = SMCReader(keyReader: reader)

        let first = smc.readSample(full: true)
        XCTAssertEqual(first.packagePowerW ?? 0, 5.17, accuracy: 0.01)

        // The pinned key fails once. That tick reports nil and must not fall back to PCPC.
        reader.blockedKeys = ["PHPC"]
        let failing = smc.readSample(full: true)
        XCTAssertNil(failing.packagePowerW)
        XCTAssertEqual(reader.readCount(for: "PCPC"), 0)

        reader.blockedKeys = []
        let recovered = smc.readSample(full: true)
        XCTAssertEqual(recovered.packagePowerW ?? 0, 5.17, accuracy: 0.01)
        XCTAssertEqual(reader.readCount(for: "PCPC"), 0)
    }

    func testZeroFanCountIsCachedWhenReadSucceeds() {
        let reader = FlakySMCKeyReader()
        reader.values = [
            "FNum": makeUInt8Value(key: "FNum", value: 0)
        ]
        let smc = SMCReader(keyReader: reader)

        XCTAssertTrue(smc.readSample(full: true).fans.isEmpty)
        XCTAssertTrue(smc.readSample(full: true).fans.isEmpty)
        XCTAssertEqual(reader.readCount(for: "FNum"), 1)
    }

    func testFailedFanCountReadIsRetried() {
        let reader = FlakySMCKeyReader()
        reader.blockedKeys = ["FNum"]
        reader.values = [
            "FNum": makeUInt8Value(key: "FNum", value: 1),
            "F0Ac": makeFloatValue(key: "F0Ac", value: 900.0)
        ]
        let smc = SMCReader(keyReader: reader)

        XCTAssertTrue(smc.readSample(full: true).fans.isEmpty)

        reader.blockedKeys = []
        let fans = smc.readSample(full: true).fans
        XCTAssertEqual(fans.count, 1)
        XCTAssertEqual(reader.readCount(for: "FNum"), 2)
    }

    // MARK: - Helpers

    private func makeFloatValue(key: String, value: Float) -> SMCValue {
        let bits = value.bitPattern
        let bytes: [UInt8] = [
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF)
        ]
        return SMCValue(key: key, dataSize: 4, dataType: "flt ", bytes: bytes)
    }

    private func makeUInt8Value(key: String, value: UInt8) -> SMCValue {
        SMCValue(key: key, dataSize: 1, dataType: "ui8 ", bytes: [value])
    }
}

/// Key reader whose values and failures can change between samples.
/// Keys in `blockedKeys` read as nil. Every read is counted.
private final class FlakySMCKeyReader: SMCKeyReading, @unchecked Sendable {
    var values: [String: SMCValue] = [:]
    var blockedKeys: Set<String> = []
    private var counts: [String: Int] = [:]

    func readKey(_ key: String) -> SMCValue? {
        counts[key, default: 0] += 1
        if blockedKeys.contains(key) {
            return nil
        }
        return values[key]
    }

    func readCount(for key: String) -> Int {
        counts[key, default: 0]
    }
}
