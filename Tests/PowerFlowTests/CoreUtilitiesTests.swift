import Foundation
import XCTest
@testable import PowerFlow

final class CoreUtilitiesTests: XCTestCase {
    // MARK: - PowerSnapshot & Cell Topology

    func testPowerSnapshotEmptyAndComputedProperties() {
        let empty = PowerSnapshot.empty
        XCTAssertFalse(empty.isDataAvailable)
        XCTAssertEqual(empty.telemetrySource, .unavailable)
        XCTAssertEqual(empty.connectionPhase, .onBattery)
        XCTAssertEqual(empty.flowMode, .unknown)
        XCTAssertFalse(empty.isEffectivelyOnAC)
        XCTAssertFalse(empty.isBatteryCharging)
        XCTAssertFalse(empty.isBatteryDischarging)
        XCTAssertFalse(empty.hasActiveOutboundPower)
        XCTAssertEqual(empty.batteryChargeRateW, 0)
        XCTAssertEqual(empty.batteryDischargeRateW, 0)

        let charging = PowerSnapshot(
            isDataAvailable: true,
            telemetrySource: .smcAndIOKit,
            connectionPhase: .onAC,
            flowMode: .adapterCharging,
            batteryPercent: 65,
            isExternalConnected: true,
            isCharging: true,
            batteryCurrentA: 2.5,
            batteryVoltageV: 12.6,
            batteryPowerW: 31.5,
            totalSystemLoadW: 18.0,
            netSystemLoadW: 18.0,
            adapterInputPowerW: 51.0
        )
        XCTAssertTrue(charging.isEffectivelyOnAC)
        XCTAssertTrue(charging.isBatteryCharging)
        XCTAssertFalse(charging.isBatteryDischarging)
        XCTAssertEqual(charging.batteryChargeRateW, 31.5, accuracy: 0.001)
        XCTAssertEqual(charging.batteryDischargeRateW, 0, accuracy: 0.001)

        let hybridWithOutbound = PowerSnapshot(
            isDataAvailable: true,
            telemetrySource: .smcAndIOKit,
            connectionPhase: .onAC,
            flowMode: .adapterBatteryHybrid,
            batteryPercent: 80,
            isExternalConnected: true,
            isCharging: false,
            batteryCurrentA: -1.1,
            batteryVoltageV: 12.4,
            batteryPowerW: -13.64,
            outboundPorts: [
                OutboundPortPower(
                    id: "usb-c-1",
                    portIndex: 1,
                    portLabel: "USB-C 1",
                    deviceName: "Demo Display",
                    isDisplayPortActive: true,
                    currentA: 1.6,
                    voltageV: 5.24,
                    powerW: 8.38
                )
            ],
            totalOutboundPowerW: 8.38,
            totalOutboundCurrentA: 1.6
        )
        XCTAssertTrue(hybridWithOutbound.isEffectivelyOnAC)
        XCTAssertFalse(hybridWithOutbound.isBatteryCharging)
        XCTAssertTrue(hybridWithOutbound.isBatteryDischarging)
        XCTAssertTrue(hybridWithOutbound.hasActiveOutboundPower)
        XCTAssertEqual(hybridWithOutbound.batteryChargeRateW, 0, accuracy: 0.001)
        XCTAssertEqual(hybridWithOutbound.batteryDischargeRateW, 13.64, accuracy: 0.001)
    }

    func testBatteryCellTopologyLabelAndSpread() {
        let topology3S2P = BatteryCellTopology(
            seriesCount: 3,
            parallelCount: 2,
            voltagesMV: [4120, 4125, 4118],
            qmaxMAh: [6200, 6210, 6195]
        )
        XCTAssertEqual(topology3S2P.label, "3S2P")
        XCTAssertEqual(topology3S2P.voltageSpreadMV, 7)

        let seriesOnly = BatteryCellTopology(seriesCount: 3, parallelCount: 0, voltagesMV: [4100])
        XCTAssertEqual(seriesOnly.label, "3S")
        XCTAssertNil(seriesOnly.voltageSpreadMV)

        let inferredFromVoltages = BatteryCellTopology(seriesCount: 0, parallelCount: 0, voltagesMV: [4000, 4012, 0])
        XCTAssertEqual(inferredFromVoltages.label, "3S")
        XCTAssertEqual(inferredFromVoltages.voltageSpreadMV, 12)

        let emptyTopology = BatteryCellTopology(seriesCount: 0, parallelCount: 0)
        XCTAssertEqual(emptyTopology.label, "—")
        XCTAssertNil(emptyTopology.voltageSpreadMV)
    }

    // MARK: - PowerSettings & Store

    @MainActor
    func testPowerSettingsStorePersistenceAndDefaults() throws {
        let defaults = InMemoryUserDefaults()

        let store = PowerSettingsStore(
            userDefaults: defaults,
            storageKey: "test.settings",
            manageLaunchAtLogin: false
        )
        XCTAssertEqual(store.settings, .default)
        XCTAssertFalse(MenuBarDisplayMode.iconOnly.requiresPeriodicPolling)
        XCTAssertFalse(MenuBarDisplayMode.iconAndPercentage.requiresPeriodicPolling)
        XCTAssertTrue(MenuBarDisplayMode.iconAndWatts.requiresPeriodicPolling)
        XCTAssertTrue(MenuBarDisplayMode.iconPercentageAndWatts.requiresPeriodicPolling)

        var observed: [PowerSettings] = []
        store.onChange = { observed.append($0) }

        store.settings.menuBarDisplayMode = .iconPercentageAndWatts
        store.settings.liveRefreshInterval = .relaxed
        store.settings.temperatureUnit = .fahrenheit
        store.settings.maskSerialNumbers = true
        store.settings.appLanguage = .simplifiedChinese

        XCTAssertEqual(observed.count, 5)

        // Setting the exact same value should not re-fire onChange.
        let current = store.settings
        store.settings = current
        XCTAssertEqual(observed.count, 5)

        // Reload in a fresh store to verify persistence.
        let reloaded = PowerSettingsStore(
            userDefaults: defaults,
            storageKey: "test.settings",
            manageLaunchAtLogin: false
        )
        XCTAssertEqual(reloaded.settings, current)

        // Partial JSON should gracefully fall back to defaults for missing keys.
        let partialJSON = Data(#"{"temperatureUnit":"fahrenheit"}"#.utf8)
        let decodedPartial = try JSONDecoder().decode(PowerSettings.self, from: partialJSON)
        XCTAssertEqual(decodedPartial.temperatureUnit, .fahrenheit)
        XCTAssertEqual(decodedPartial.menuBarDisplayMode, .iconOnly)
        XCTAssertEqual(decodedPartial.liveRefreshInterval, .standard)
        XCTAssertEqual(decodedPartial.appLanguage, .system)

        // A retired value (the former 0.5 s refresh rate) falls back alone and keeps its neighbours.
        let retiredJSON = Data(#"{"liveRefreshInterval":0.5,"menuBarDisplayMode":"iconAndWatts"}"#.utf8)
        let decodedRetired = try JSONDecoder().decode(PowerSettings.self, from: retiredJSON)
        XCTAssertEqual(decodedRetired.liveRefreshInterval, .standard)
        XCTAssertEqual(decodedRetired.menuBarDisplayMode, .iconAndWatts)

        reloaded.resetToDefaults()
        XCTAssertEqual(reloaded.settings, .default)
    }

    // MARK: - BatteryChargeLimitResolver

    func testChargeLimitResolverCases() {
        XCTAssertEqual(BatteryChargeLimitResolver.resolve(notChargingReason: nil), .unlimited)
        XCTAssertEqual(BatteryChargeLimitResolver.resolve(notChargingReason: 0), .unlimited)
        XCTAssertEqual(
            BatteryChargeLimitResolver.resolve(notChargingReason: 0x0400),
            BatteryChargeLimitInfo(limitPercent: 80, source: .optimizedCharging)
        )
        XCTAssertEqual(
            BatteryChargeLimitResolver.resolve(notChargingReason: 0x0080),
            BatteryChargeLimitInfo(limitPercent: 80, source: .optimizedCharging)
        )
        // Inhibited charging alone names no tool and no limit.
        XCTAssertEqual(BatteryChargeLimitResolver.resolve(notChargingReason: 0x0008), .unlimited)
        XCTAssertEqual(
            BatteryChargeLimitResolver.resolve(notChargingReason: 0, alDenteLimit: 70),
            BatteryChargeLimitInfo(limitPercent: 70, source: .alDente)
        )
        XCTAssertEqual(
            BatteryChargeLimitResolver.resolve(
                notChargingReason: 0,
                systemPolicy: SystemChargePolicy(limitPercent: 80, drainsToLimit: true, isManual: true)
            ),
            BatteryChargeLimitInfo(limitPercent: 80, source: .macOSSetting, drainsToLimit: true)
        )
        XCTAssertEqual(
            BatteryChargeLimitResolver.resolve(
                notChargingReason: 0,
                systemPolicy: SystemChargePolicy(limitPercent: 85, drainsToLimit: false, isManual: false)
            ),
            BatteryChargeLimitInfo(limitPercent: 85, source: .optimizedCharging)
        )
        // A limit of 100% is no limit.
        XCTAssertEqual(
            BatteryChargeLimitResolver.resolve(notChargingReason: 0, alDenteLimit: 100),
            .unlimited
        )
    }

    func testAlDenteLimitIsIgnoredUnlessAlDenteIsRunning() {
        let defaults = InMemoryUserDefaults()
        defaults.set(80, forKey: "chargeVal")

        XCTAssertNil(
            BatteryChargeLimitResolver.readAlDenteChargeLimit(isRunning: { _ in false }, defaults: { _ in defaults })
        )
        XCTAssertEqual(
            BatteryChargeLimitResolver.readAlDenteChargeLimit(isRunning: { _ in true }, defaults: { _ in defaults }),
            80
        )

        defaults.set(false, forKey: "enableChargeLimiter")
        XCTAssertNil(
            BatteryChargeLimitResolver.readAlDenteChargeLimit(isRunning: { _ in true }, defaults: { _ in defaults })
        )
    }

    // MARK: - BatteryTimeEstimator

    func testTimeEstimatorDischargingAndEMASmoothing() {
        let estimator = BatteryTimeEstimator(emaAlpha: 0.25)

        // 3000 mAh remaining at -1.5 A -> 2 hours (120 min)
        let first = estimator.estimateMinutes(
            isCharging: false,
            batteryPercent: 50,
            currentChargeMAh: 3000,
            maxCapacityMAh: 6000,
            batteryCurrentA: -1.5,
            batteryPowerW: -18.0,
            batteryVoltageV: 12.0
        )
        XCTAssertEqual(first, 120)

        // Sudden spike to -3.0 A should be smoothed by EMA (0.25 * 3000 + 0.75 * 1500 = 1875 mA -> 96 min)
        let smoothed = estimator.estimateMinutes(
            isCharging: false,
            batteryPercent: 50,
            currentChargeMAh: 3000,
            maxCapacityMAh: 6000,
            batteryCurrentA: -3.0,
            batteryPowerW: -36.0,
            batteryVoltageV: 12.0
        )
        XCTAssertEqual(smoothed, 96)
    }

    func testTimeEstimatorChargingCVTaperAndChargeLimit() {
        // Pure CC: 50% -> 80% on 6000 mAh = 1800 mAh needed at 3.0 A -> 36 min
        let ccEstimator = BatteryTimeEstimator(emaAlpha: 1.0)
        let toLimit80 = ccEstimator.estimateMinutes(
            isCharging: true,
            batteryPercent: 50,
            chargeLimitPercent: 80,
            currentChargeMAh: 3000,
            maxCapacityMAh: 6000,
            batteryCurrentA: 3.0,
            batteryPowerW: 39.0,
            batteryVoltageV: 13.0
        )
        XCTAssertEqual(toLimit80, 36)

        // Crossing 80% -> 100% applies CV taper, so 50% -> 100% takes strictly longer than linear 60 min
        let fullEstimator = BatteryTimeEstimator(emaAlpha: 1.0)
        let toFull100 = fullEstimator.estimateMinutes(
            isCharging: true,
            batteryPercent: 50,
            chargeLimitPercent: 100,
            currentChargeMAh: 3000,
            maxCapacityMAh: 6000,
            batteryCurrentA: 3.0,
            batteryPowerW: 39.0,
            batteryVoltageV: 13.0
        )
        XCTAssertNotNil(toFull100)
        XCTAssertGreaterThan(toFull100 ?? 0, 60)

        // Already at charge limit -> nil
        let alreadyAtLimit = fullEstimator.estimateMinutes(
            isCharging: true,
            batteryPercent: 80,
            chargeLimitPercent: 80,
            currentChargeMAh: 4800,
            maxCapacityMAh: 6000,
            batteryCurrentA: 1.0,
            batteryPowerW: 13.0,
            batteryVoltageV: 13.0
        )
        XCTAssertNil(alreadyAtLimit)

        // Idle -> nil
        let idle = fullEstimator.estimateMinutes(
            isCharging: false,
            batteryPercent: 95,
            currentChargeMAh: 5700,
            maxCapacityMAh: 6000,
            batteryCurrentA: 0.0,
            batteryPowerW: 0.0,
            batteryVoltageV: 12.8
        )
        XCTAssertNil(idle)
    }

    func testTimeEstimatorModeSwitchResetAndSanitizedOSMinutes() {
        let estimator = BatteryTimeEstimator(emaAlpha: 0.25)
        _ = estimator.estimateMinutes(
            isCharging: false,
            batteryPercent: 50,
            currentChargeMAh: 3000,
            maxCapacityMAh: 6000,
            batteryCurrentA: -1.0,
            batteryPowerW: -12.0,
            batteryVoltageV: 12.0
        )
        // Switching to charging must reset EMA so 3.0 A isn't dragged down by previous 1.0 A discharge.
        let chargingEstimate = estimator.estimateMinutes(
            isCharging: true,
            batteryPercent: 50,
            chargeLimitPercent: 80,
            currentChargeMAh: 3000,
            maxCapacityMAh: 6000,
            batteryCurrentA: 3.0,
            batteryPowerW: 39.0,
            batteryVoltageV: 13.0
        )
        XCTAssertEqual(chargingEstimate, 36)

        XCTAssertNil(BatteryTimeEstimator.sanitizedOSMinutes(nil))
        XCTAssertNil(BatteryTimeEstimator.sanitizedOSMinutes(0))
        XCTAssertNil(BatteryTimeEstimator.sanitizedOSMinutes(-1))
        XCTAssertNil(BatteryTimeEstimator.sanitizedOSMinutes(65535))
        XCTAssertNil(BatteryTimeEstimator.sanitizedOSMinutes(10000))
        XCTAssertEqual(BatteryTimeEstimator.sanitizedOSMinutes(142), 142)
    }

    // MARK: - PowerFormatters

    func testPowerFormattersValuesAndEdgeCases() {
        XCTAssertEqual(PowerFormatters.watts(31.92), "31.92 W")
        XCTAssertEqual(PowerFormatters.watts(-0.001), "0 W")
        XCTAssertEqual(PowerFormatters.watts(24.5, signed: true), "+24.50 W")
        XCTAssertEqual(PowerFormatters.watts(-12.3, signed: true), "-12.30 W")
        XCTAssertEqual(PowerFormatters.watts(.nan), "—")

        XCTAssertEqual(PowerFormatters.compactWatts(31.92), "32W")
        XCTAssertEqual(PowerFormatters.compactWatts(8.38), "8.4W")
        XCTAssertEqual(PowerFormatters.compactWatts(0.01), "0W")

        XCTAssertEqual(PowerFormatters.amps(1.59), "1.59 A")
        XCTAssertEqual(PowerFormatters.amps(-0.001, signed: true), "0 A")
        XCTAssertEqual(PowerFormatters.amps(2.45, signed: true), "+2.45 A")
        XCTAssertEqual(PowerFormatters.amps(-1.82, signed: true), "-1.82 A")

        XCTAssertEqual(PowerFormatters.volts(20.04), "20.04 V")
        XCTAssertEqual(PowerFormatters.volts(0), "0 V")

        XCTAssertEqual(PowerFormatters.capacityMAh(6249), "6,249 mAh")
        XCTAssertEqual(PowerFormatters.capacityMAh(nil), "—")
        XCTAssertEqual(PowerFormatters.precisePercent(98.14), "98.1%")
        XCTAssertEqual(PowerFormatters.precisePercent(nil), "—")

        XCTAssertEqual(PowerFormatters.temperature(37.69, unit: .celsius), "37.7 °C")
        XCTAssertEqual(PowerFormatters.temperature(37.69, unit: .fahrenheit), "99.8 °F")
        XCTAssertEqual(PowerFormatters.temperature(nil, unit: .celsius), "—")

        XCTAssertEqual(PowerFormatters.duration(minutes: 135, language: .english), "2h 15m")
        XCTAssertEqual(PowerFormatters.duration(minutes: 120, language: .english), "2h")
        XCTAssertEqual(PowerFormatters.duration(minutes: 45, language: .english), "45m")
        XCTAssertEqual(PowerFormatters.duration(minutes: 135, language: .simplifiedChinese), "2小时15分")
        XCTAssertEqual(PowerFormatters.duration(minutes: 45, language: .simplifiedChinese), "45分钟")
        XCTAssertEqual(PowerFormatters.duration(minutes: 0, language: .english), "—")

        XCTAssertEqual(PowerFormatters.cycleCount(35, designLimit: 1000), "35 / 1,000")
        XCTAssertEqual(PowerFormatters.cycleCount(35, designLimit: nil), "35")
        XCTAssertEqual(PowerFormatters.cycleCount(nil, designLimit: 1000), "—")

        XCTAssertEqual(PowerFormatters.maskSerial("C02ABCD1234", masked: false), "C02ABCD1234")
        XCTAssertEqual(PowerFormatters.maskSerial("C02ABCD1234", masked: true), "C02••••34")
        XCTAssertEqual(PowerFormatters.maskSerial("12345", masked: true), "••••")
        XCTAssertEqual(PowerFormatters.maskSerial("   ", masked: true), "—")
    }

    // MARK: - L10n

    func testLocalizationEnglishAndSimplifiedChinese() {
        for key in L10n.Key.allCases {
            XCTAssertFalse(L10n.string(key, language: .english).isEmpty, "Missing EN string for \(key)")
            XCTAssertFalse(L10n.string(key, language: .simplifiedChinese).isEmpty, "Missing zh-Hans string for \(key)")
        }

        XCTAssertEqual(L10n.string(.batterySpecs, language: .english), "Battery Specs")
        XCTAssertEqual(L10n.string(.batterySpecs, language: .simplifiedChinese), "电池参数")
        XCTAssertEqual(L10n.label(for: .adapterBypass, language: .english), "Power Adapter")
        XCTAssertEqual(L10n.label(for: .adapterBypass, language: .simplifiedChinese), "电源适配器直供")
        XCTAssertEqual(L10n.label(for: .nominal, language: .english), "Nominal")
        XCTAssertEqual(L10n.label(for: .critical, language: .simplifiedChinese), "过热")
        XCTAssertEqual(L10n.tr("Hello", zh: "你好", language: .english), "Hello")
        XCTAssertEqual(L10n.tr("Hello", zh: "你好", language: .simplifiedChinese), "你好")
    }

    // MARK: - Round 3 Detailed Telemetry Models & Formatters

    func testTelemetryModelsCodableRoundTrip() throws {
        let pdProfile = USBPDProfile(
            id: 3,
            index: 3,
            maxVoltageV: 20.0,
            maxCurrentA: 3.39,
            maxWatts: 67.8,
            isActive: true
        )
        XCTAssertEqual(pdProfile.id, 3)
        XCTAssertEqual(USBPDProfile(index: 1, maxVoltageV: 5.0, maxCurrentA: 3.0, maxWatts: 15.0).id, 1)

        let fanActive = FanReading(index: 0, rpm: 3400, maxRpm: 6800)
        XCTAssertEqual(fanActive.id, 0)
        XCTAssertEqual(fanActive.percentMax ?? -1, 50.0, accuracy: 0.01)

        let fanNoMax = FanReading(id: 1, index: 1, rpm: 0, maxRpm: nil)
        XCTAssertNil(fanNoMax.percentMax)

        let fanZeroMax = FanReading(index: 1, rpm: 1000, maxRpm: 0)
        XCTAssertNil(fanZeroMax.percentMax)

        let fanClamped = FanReading(index: 0, rpm: 7500, maxRpm: 6800)
        XCTAssertEqual(fanClamped.percentMax ?? -1, 100.0, accuracy: 0.01)

        let lifetime = BatteryLifetimeStats(
            operatingHours: 4215,
            minTempC: 11.0,
            avgTempC: 22.5,
            maxTempC: 44.0,
            minPackVoltageV: 10.2,
            maxPackVoltageV: 13.15,
            maxChargeCurrentA: 5.2,
            maxDischargeCurrentA: 6.8
        )

        let breakdown = SystemPowerBreakdown(
            packagePowerW: 5.17,
            displayPowerW: 3.40,
            otherSystemW: 12.10,
            cpuTemperatureC: 58.2,
            gpuTemperatureC: 49.5,
            thermalState: .fair,
            fans: [fanActive, fanNoMax]
        )

        let portStatus = PhysicalPortStatus(
            id: "usbc-2",
            portKind: .usbC,
            portNumber: 2,
            portLabel: "USB-C 2",
            role: .powerOut,
            connectionActive: true,
            deviceName: "Demo Display",
            manufacturer: "Demo Display Maker",
            cableType: "Active Cable",
            activeTransports: ["CC", "USB2", "DisplayPort"],
            powerW: 5.70,
            currentA: 1.09,
            voltageV: 5.22,
            maxPDWatts: 15.0,
            vconnPowerW: 0.12,
            vconnCurrentA: 0.025
        )

        let adapter = AdapterSourceInfo(
            id: "magsafe-0",
            isActive: true,
            portKind: .magSafe,
            portNumber: 0,
            portLabel: "MagSafe 3",
            name: "70W USB-C Power Adapter",
            ratedWatts: 70,
            ratedVoltageV: 20.5,
            ratedCurrentA: 3.39,
            firmwareVersion: "1020034",
            hardwareVersion: "1.0",
            adapterID: 28945,
            pdProfiles: [pdProfile],
            activePDProfileIndex: 3
        )

        let outbound = OutboundPortPower(
            id: "usbc-2",
            portIndex: 2,
            portLabel: "USB-C 2",
            deviceName: "Demo Display",
            isDisplayPortActive: true,
            currentA: 1.09,
            voltageV: 5.22,
            powerW: 5.70,
            filteredPowerW: 5.64,
            activeTransports: ["CC", "DisplayPort"],
            cableType: "Passive Cable",
            pdSpecRevision: 3
        )

        let snapshot = PowerSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            isDataAvailable: true,
            telemetrySource: .smcAndIOKit,
            connectionPhase: .onAC,
            flowMode: .adapterBypass,
            batteryPercent: 100,
            isExternalConnected: true,
            activeAdapter: adapter,
            outboundPorts: [outbound],
            totalOutboundPowerW: 5.70,
            totalOutboundCurrentA: 1.09,
            health: BatteryHealthInfo(designCapacityMAh: 6249, lifetime: lifetime),
            wallPowerEstimateW: 36.2,
            batteryRemainingWh: 77.3,
            batteryDesignWh: 71.2,
            batteryFullChargeWh: 70.0,
            chargingHoldReason: "Battery Full",
            systemBreakdown: breakdown,
            physicalPorts: [portStatus]
        )

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PowerSnapshot.self, from: encoded)
        XCTAssertEqual(decoded, snapshot)
    }

    func testEnergyAndFanFormatters() {
        XCTAssertEqual(PowerFormatters.wattHours(77.34), "77.3 Wh")
        XCTAssertEqual(PowerFormatters.wattHours(77.34, decimals: 2), "77.34 Wh")
        XCTAssertEqual(PowerFormatters.wattHours(0.01), "0 Wh")
        XCTAssertEqual(PowerFormatters.wattHours(-1.0), "—")
        XCTAssertEqual(PowerFormatters.wattHours(nil), "—")

        XCTAssertEqual(PowerFormatters.rpm(0), "0 RPM")
        XCTAssertEqual(PowerFormatters.rpm(2450.6), "2,451 RPM")
        XCTAssertEqual(PowerFormatters.rpm(-10), "—")
    }

    func testOverflowSafeFormattersAndIntMinGrouping() {
        XCTAssertEqual(PowerFormatters.integerGrouped(Int.min), "-9,223,372,036,854,775,808")
        XCTAssertFalse(PowerFormatters.compactWatts(1e30).isEmpty)
        XCTAssertTrue(PowerFormatters.compactWatts(1e30).hasSuffix("W"))
        XCTAssertTrue(PowerFormatters.rpm(1e30).hasSuffix(" RPM"))
    }

    func testTimeEstimatorZeroSoCReturnsNilAndTimestampGapResetsEMA() {
        let estimator = BatteryTimeEstimator(emaAlpha: 0.25)
        let t0 = Date(timeIntervalSince1970: 2_000)

        // 0% SoC discharging must return nil (not 0).
        let zeroSoc = estimator.estimateMinutes(
            isCharging: false,
            batteryPercent: 0,
            currentChargeMAh: 0,
            maxCapacityMAh: 6000,
            batteryCurrentA: -1.5,
            batteryPowerW: -18.0,
            batteryVoltageV: 12.0,
            at: t0
        )
        XCTAssertNil(zeroSoc)

        // Seed EMA at t0 with -1.5A -> 120 min
        let first = estimator.estimateMinutes(
            isCharging: false,
            batteryPercent: 50,
            currentChargeMAh: 3000,
            maxCapacityMAh: 6000,
            batteryCurrentA: -1.5,
            batteryPowerW: -18.0,
            batteryVoltageV: 12.0,
            at: t0
        )
        XCTAssertEqual(first, 120)

        // Within <= 10s (at t0 + 2s), EMA smooths -3.0A -> 1875 mA -> 96 min.
        let smoothed = estimator.estimateMinutes(
            isCharging: false,
            batteryPercent: 50,
            currentChargeMAh: 3000,
            maxCapacityMAh: 6000,
            batteryCurrentA: -3.0,
            batteryPowerW: -36.0,
            batteryVoltageV: 12.0,
            at: t0.addingTimeInterval(2.0)
        )
        XCTAssertEqual(smoothed, 96)

        // After > 10s gap (e.g. post-sleep or dormant wake at t0 + 15s), EMA resets to instant -3.0A -> 60 min.
        let resetEstimate = estimator.estimateMinutes(
            isCharging: false,
            batteryPercent: 50,
            currentChargeMAh: 3000,
            maxCapacityMAh: 6000,
            batteryCurrentA: -3.0,
            batteryPowerW: -36.0,
            batteryVoltageV: 12.0,
            at: t0.addingTimeInterval(15.0)
        )
        XCTAssertEqual(resetEstimate, 60)
    }

    func testL10nChargingHoldPreservesAlDenteAndIncludesApprovalKeys() {
        XCTAssertEqual(
            L10n.chargingHold("Charge Limit (80% · AlDente)", chargeLimitPercent: 80, language: .english),
            "Charge Limit (80% · AlDente)"
        )
        XCTAssertEqual(
            L10n.chargingHold("Charge Limit (80% · AlDente)", chargeLimitPercent: 80, language: .simplifiedChinese),
            "充电上限 (80% · AlDente)"
        )
        XCTAssertEqual(
            L10n.chargingHold("Charge Limit (80%)", chargeLimitPercent: 80, language: .english),
            "Charge Limit (80%)"
        )
        XCTAssertFalse(L10n.string(.launchAtLoginRequiresApproval, language: .english).isEmpty)
        XCTAssertFalse(L10n.string(.openLoginItemsSettings, language: .simplifiedChinese).isEmpty)
    }

    @MainActor
    func testPowerSettingsStoreTracksLaunchAtLoginApprovalStatus() {
        let store = PowerSettingsStore(userDefaults: nil, manageLaunchAtLogin: false)
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertFalse(store.launchAtLoginRequiresApproval)

        store.syncLaunchAtLoginStatus(.requiresApproval)
        XCTAssertTrue(store.launchAtLogin)
        XCTAssertTrue(store.launchAtLoginRequiresApproval)

        store.syncLaunchAtLoginStatus(.enabled)
        XCTAssertTrue(store.launchAtLogin)
        XCTAssertFalse(store.launchAtLoginRequiresApproval)

        store.syncLaunchAtLoginStatus(.notRegistered)
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertFalse(store.launchAtLoginRequiresApproval)
    }

    func testPowerSnapshotACStateAlignmentDuringUnplugDebounce() {
        let debouncingUnplug = PowerSnapshot(
            isDataAvailable: true,
            connectionPhase: .onAC,
            flowMode: .batteryOnly,
            isExternalConnected: false
        )
        XCTAssertFalse(debouncingUnplug.isEffectivelyOnAC)
        XCTAssertFalse(debouncingUnplug.isAdapterSupplyingPower)

        let connecting = PowerSnapshot(
            isDataAvailable: true,
            connectionPhase: .connectingAC,
            flowMode: .connectingAC,
            isExternalConnected: false
        )
        XCTAssertTrue(connecting.isEffectivelyOnAC)
        XCTAssertTrue(connecting.isAdapterSupplyingPower)

        let unknownOnAC = PowerSnapshot(
            isDataAvailable: true,
            connectionPhase: .onAC,
            flowMode: .unknown,
            isExternalConnected: true
        )
        XCTAssertTrue(unknownOnAC.isEffectivelyOnAC)
        XCTAssertFalse(unknownOnAC.isAdapterSupplyingPower)
    }
}
