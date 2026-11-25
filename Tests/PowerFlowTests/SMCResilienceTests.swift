import Foundation
import IOKit
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

    func testResetDiscoveryCachesReprobesPrimaryPackagePowerAndDieTempSensors() {
        let reader = FlakySMCKeyReader()
        reader.blockedKeys = ["PHPC", "Tp09"]
        reader.values = [
            "PHPC": makeFloatValue(key: "PHPC", value: 12.4),
            "PCPC": makeFloatValue(key: "PCPC", value: 7.0),
            "Tp09": makeFloatValue(key: "Tp09", value: 64.0),
            "Tp0D": makeFloatValue(key: "Tp0D", value: 58.0)
        ]
        let smc = SMCReader(keyReader: reader)

        // Pass 1 pins fallback PCPC and present sensor Tp0D
        let pass1 = smc.readSample(full: true)
        XCTAssertEqual(pass1.packagePowerW ?? 0, 7.0, accuracy: 0.01)
        XCTAssertEqual(pass1.cpuTemperatureC ?? 0, 58.0, accuracy: 0.01)
        let tp09ReadsAfterPass1 = reader.readCount(for: "Tp09")

        // Pass 2 stays pinned even after PHPC & Tp09 recover
        reader.blockedKeys = []
        let pass2 = smc.readSample(full: true)
        XCTAssertEqual(pass2.packagePowerW ?? 0, 7.0, accuracy: 0.01)
        XCTAssertEqual(pass2.cpuTemperatureC ?? 0, 58.0, accuracy: 0.01)
        XCTAssertEqual(reader.readCount(for: "Tp09"), tp09ReadsAfterPass1)

        // Resetting caches (e.g. on wake) re-probes PHPC and all die-temp sensors
        smc.resetDiscoveryCaches()
        let pass3 = smc.readSample(full: true)
        XCTAssertEqual(pass3.packagePowerW ?? 0, 12.4, accuracy: 0.01)
        XCTAssertEqual(pass3.cpuTemperatureC ?? 0, 64.0, accuracy: 0.01)
        XCTAssertEqual(reader.readCount(for: "Tp09"), tp09ReadsAfterPass1 + 1)
    }

    func testSMCConnectionReconnectsOnceOnConnectionLostAndPreservesKeyInfoCache() {
        final class FakeKernelState: @unchecked Sendable {
            private let lock = NSLock()
            var nextHandle: io_connect_t = 1
            var openCount = 0
            var closeCount = 0
            var keyInfoCalls = 0
            var readBytesCalls = 0
            var remainingConnectionDrops = 0

            func open() -> io_connect_t {
                lock.lock()
                defer { lock.unlock() }
                openCount += 1
                let h = nextHandle
                nextHandle += 1
                return h
            }

            func close(_ conn: io_connect_t) {
                lock.lock()
                defer { lock.unlock() }
                closeCount += 1
            }

            func setDrops(_ count: Int) {
                lock.lock()
                remainingConnectionDrops = count
                lock.unlock()
            }

            func call(_ conn: io_connect_t, input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
                lock.lock()
                defer { lock.unlock() }
                if input.data8 == 9 { // readKeyInfo
                    keyInfoCalls += 1
                    output.keyInfo.dataSize = 4
                    output.keyInfo.dataType = SMCConnection.fourCC("flt ") ?? 0
                    return KERN_SUCCESS
                }
                readBytesCalls += 1
                if remainingConnectionDrops > 0 {
                    remainingConnectionDrops -= 1
                    return kern_return_t(truncatingIfNeeded: kIOReturnNotOpen)
                }
                let bits = Float(25.5).bitPattern
                output.bytes.0 = UInt8(bits & 0xFF)
                output.bytes.1 = UInt8((bits >> 8) & 0xFF)
                output.bytes.2 = UInt8((bits >> 16) & 0xFF)
                output.bytes.3 = UInt8((bits >> 24) & 0xFF)
                return KERN_SUCCESS
            }

            var snapshot: (opens: Int, closes: Int, keyInfos: Int, reads: Int) {
                lock.lock()
                defer { lock.unlock() }
                return (openCount, closeCount, keyInfoCalls, readBytesCalls)
            }
        }

        let state = FakeKernelState()
        let connection = SMCConnection(
            transport: .init(
                open: { state.open() },
                close: { state.close($0) },
                callStructMethod: { conn, input, output in
                    state.call(conn, input: &input, output: &output)
                }
            )
        )

        // First read populates keyInfoCache
        let initial = connection.readKey("PDTR")?.floatValue()
        XCTAssertEqual(initial ?? 0, 25.5, accuracy: 0.01)
        XCTAssertEqual(state.snapshot.keyInfos, 1)

        // Single connection drop (e.g. post-sleep) reopens and retries once without wiping keyInfoCache
        state.setDrops(1)
        let recovered = connection.readKey("PDTR")?.floatValue()
        XCTAssertEqual(recovered ?? 0, 25.5, accuracy: 0.01)
        XCTAssertEqual(state.snapshot.opens, 2)
        XCTAssertEqual(state.snapshot.closes, 1)
        XCTAssertEqual(state.snapshot.keyInfos, 1)

        // Two consecutive drops fail cleanly after the single retry without looping
        state.setDrops(2)
        let failed = connection.readKey("PDTR")
        XCTAssertNil(failed)
        XCTAssertFalse(connection.isOpen)
        XCTAssertEqual(state.snapshot.opens, 3)
        XCTAssertEqual(state.snapshot.closes, 3)
        XCTAssertEqual(state.snapshot.keyInfos, 1)
    }

    func testSMCConnectionBacksOffMonotonicallyWhenAppleSMCAbsent() {
        final class FakeVMState: @unchecked Sendable {
            private let lock = NSLock()
            var now: TimeInterval = 100.0
            var openAttempts = 0
            var allowOpen = false

            func currentTime() -> TimeInterval {
                lock.lock()
                defer { lock.unlock() }
                return now
            }

            func advance(by delta: TimeInterval) {
                lock.lock()
                now += delta
                lock.unlock()
            }

            func open() -> io_connect_t {
                lock.lock()
                defer { lock.unlock() }
                openAttempts += 1
                return allowOpen ? 7 : 0
            }

            func setAllowOpen(_ allowed: Bool) {
                lock.lock()
                allowOpen = allowed
                lock.unlock()
            }

            var attempts: Int {
                lock.lock()
                defer { lock.unlock() }
                return openAttempts
            }
        }

        let state = FakeVMState()
        let connection = SMCConnection(
            transport: .init(
                open: { state.open() },
                close: { _ in },
                callStructMethod: { _, _, _ in KERN_FAILURE }
            ),
            uptime: { state.currentTime() }
        )

        // init() failed once -> 2s cooldown active
        XCTAssertFalse(connection.isOpen)
        XCTAssertEqual(state.attempts, 1)

        // Burst of 50 key reads within cooldown must NOT hit IOServiceOpen again
        state.advance(by: 0.5)
        for _ in 0..<50 {
            XCTAssertNil(connection.readKey("PDTR"))
        }
        XCTAssertEqual(state.attempts, 1)

        // Past first 2s backoff -> retries once, next backoff is 4s
        state.advance(by: 1.6)
        XCTAssertNil(connection.readKey("PDTR"))
        XCTAssertEqual(state.attempts, 2)

        // Within 4s cooldown -> suppressed
        state.advance(by: 3.5)
        XCTAssertNil(connection.readKey("PDTR"))
        XCTAssertEqual(state.attempts, 2)

        // Past 4s cooldown with AppleSMC available -> opens cleanly
        state.advance(by: 0.6)
        state.setAllowOpen(true)
        _ = connection.readKey("PDTR")
        XCTAssertEqual(state.attempts, 3)
        XCTAssertTrue(connection.isOpen)
    }

    #if arch(arm64)
    func testSMCReaderDefaultsToLittleEndianBatteryKeysForInjectedSMCConnectionOnArm64() {
        let connection = SMCConnection(
            transport: .init(
                open: { 1 },
                close: { _ in },
                callStructMethod: { _, input, output in
                    let isBatteryVoltage = input.key == SMCConnection.fourCC("B0AV")
                    let isCycleCount = input.key == SMCConnection.fourCC("B0CT")
                    guard isBatteryVoltage || isCycleCount else {
                        output.result = 0x84 // kSMCKeyNotFound
                        return KERN_SUCCESS
                    }
                    if input.data8 == 9 { // readKeyInfo
                        output.keyInfo.dataSize = 2
                        output.keyInfo.dataType = SMCConnection.fourCC("ui16") ?? 0
                        return KERN_SUCCESS
                    }
                    if isBatteryVoltage {
                        // Little-endian 13104 mV = [0x30, 0x33]
                        output.bytes.0 = 0x30
                        output.bytes.1 = 0x33
                        return KERN_SUCCESS
                    }
                    // Little-endian 35 cycles = [35, 0]
                    output.bytes.0 = 35
                    output.bytes.1 = 0
                    return KERN_SUCCESS
                }
            )
        )

        // Passing SMCConnection without explicit useLittleEndianBatteryKeys must default to LE on arm64
        let smc = SMCReader(keyReader: connection)
        let sample = smc.readSample(full: true)
        XCTAssertEqual(sample.batteryVoltageV ?? 0, 13.104, accuracy: 0.001)
        XCTAssertEqual(sample.cycleCount, 35)
    }
    #endif

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
