import XCTest
@testable import PowerFlow

final class SystemChargePolicyTests: XCTestCase {
    private static let session = "11111111-2222-3333-4444-555555555555"

    private func file(_ policies: [ArchivedChargePolicy], session: String = SystemChargePolicyTests.session) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        archiver.setClassName(ArchivedChargePolicy.archivedName, for: ArchivedChargePolicy.self)
        archiver.encode(policies as NSArray, forKey: NSKeyedArchiveRootObjectKey)
        archiver.finishEncoding()
        return try PropertyListSerialization.data(
            fromPropertyList: ["bootSessionUUID": session, "policies": archiver.encodedData],
            format: .binary,
            options: 0
        )
    }

    private func manual(_ limit: Int, drain: Bool = true, terminated: Bool = false) -> ArchivedChargePolicy {
        ArchivedChargePolicy(limit: limit, drain: drain, terminated: terminated, reason: "manualChargeLimit")
    }

    func testManualLimit() throws {
        XCTAssertEqual(
            SystemChargePolicyReader.parse(try file([manual(80)]), bootSession: Self.session),
            SystemChargePolicy(limitPercent: 80, drainsToLimit: true, isManual: true)
        )
    }

    func testStrictestActivePolicyWins() throws {
        let data = try file([
            manual(90, drain: false),
            manual(60, terminated: true),
            ArchivedChargePolicy(limit: 85, drain: false, terminated: false, reason: "other")
        ])
        XCTAssertEqual(
            SystemChargePolicyReader.parse(data, bootSession: Self.session),
            SystemChargePolicy(limitPercent: 85, drainsToLimit: false, isManual: false)
        )
    }

    func testNoPolicyWhenNoneIsInForce() throws {
        XCTAssertNil(SystemChargePolicyReader.parse(try file([]), bootSession: Self.session))
        XCTAssertNil(SystemChargePolicyReader.parse(try file([manual(100)]), bootSession: Self.session))
        XCTAssertNil(SystemChargePolicyReader.parse(Data("garbage".utf8), bootSession: Self.session))
    }

    func testPolicyFromAnEarlierBootIsIgnored() throws {
        XCTAssertNil(
            SystemChargePolicyReader.parse(try file([manual(80)], session: UUID().uuidString), bootSession: Self.session)
        )
    }

    func testReaderFollowsTheFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = SystemChargePolicyReader(url: url, bootSession: Self.session)
        XCTAssertNil(reader.currentPolicy())

        try file([manual(80)]).write(to: url)
        XCTAssertEqual(reader.currentPolicy()?.limitPercent, 80)

        try file([]).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: url.path
        )
        XCTAssertNil(reader.currentPolicy())
    }

    func testTransientReadFailureDoesNotPoisonModificationStampOrEvictCachedPolicy() throws {
        final class ToggleableLoader: @unchecked Sendable {
            private let lock = NSLock()
            var shouldFail = true
            var loadCount = 0

            func load(_ url: URL) throws -> Data {
                lock.lock()
                loadCount += 1
                let fail = shouldFail
                lock.unlock()
                if fail {
                    throw CocoaError(.fileReadUnknown)
                }
                return try Data(contentsOf: url)
            }

            func setFail(_ fail: Bool) {
                lock.lock()
                shouldFail = fail
                lock.unlock()
            }

            var calls: Int {
                lock.lock()
                defer { lock.unlock() }
                return loadCount
            }
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        try file([manual(80)]).write(to: url)

        let loader = ToggleableLoader()
        let reader = SystemChargePolicyReader(
            url: url,
            bootSession: Self.session,
            dataLoader: { try loader.load($0) }
        )

        // First read fails transiently: must not record mtime so next call retries without mtime change
        XCTAssertNil(reader.currentPolicy())
        XCTAssertEqual(loader.calls, 1)

        loader.setFail(false)
        XCTAssertEqual(reader.currentPolicy()?.limitPercent, 80)
        XCTAssertEqual(loader.calls, 2)

        // Steady-state call with unchanged mtime hits stat cache without reading file
        XCTAssertEqual(reader.currentPolicy()?.limitPercent, 80)
        XCTAssertEqual(loader.calls, 2)

        // File updated with new mtime, but read fails transiently: keep previous policy and retry next tick
        try file([manual(90)]).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: url.path
        )
        loader.setFail(true)
        XCTAssertEqual(reader.currentPolicy()?.limitPercent, 80)
        XCTAssertEqual(loader.calls, 3)

        loader.setFail(false)
        XCTAssertEqual(reader.currentPolicy()?.limitPercent, 90)
        XCTAssertEqual(loader.calls, 4)
    }

    // MARK: - Effect on the snapshot

    func testDrainingToTheLimitWhilePluggedIn() {
        let limit = BatteryChargeLimitInfo(limitPercent: 80, source: .macOSSetting, drainsToLimit: true)
        func snapshot(percent: Int, adapterW: Double) -> PowerSnapshot {
            makeIsolatedResolver(chargeLimit: limit).resolve(
                reading: makeReading(
                    currentCapacityPercent: percent,
                    isExternalConnected: true,
                    isFullyCharged: true,
                    timeRemainingMinutes: 266,
                    instantAmperageMA: -1_200,
                    amperageMA: -1_200
                ),
                smc: SMCPowerSample(
                    deliveryRateW: adapterW,
                    systemTotalW: 15,
                    batteryRateW: -15,
                    batteryVoltageV: 12.5,
                    batteryCurrentA: -1.2
                ),
                connectionPhase: .onAC,
                isLowPowerModeEnabled: false
            )
        }

        let draining = snapshot(percent: 98, adapterW: 0.45)
        XCTAssertEqual(draining.flowMode, .batteryWhilePluggedIn)
        XCTAssertFalse(draining.isAdapterSupplyingPower)
        XCTAssertEqual(draining.chargingHoldReason, "Draining to 80%")
        XCTAssertNil(draining.timeRemainingMinutes)
        XCTAssertEqual(
            L10n.chargingHold("Draining to 80%", chargeLimitPercent: 80, language: .simplifiedChinese),
            "放电至 80%"
        )

        // A charger that really contributes is hybrid power, limit or not.
        XCTAssertEqual(snapshot(percent: 98, adapterW: 30).flowMode, .adapterBatteryHybrid)
    }
}
