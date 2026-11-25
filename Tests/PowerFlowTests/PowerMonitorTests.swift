import XCTest
@testable import PowerFlow

final class PowerMonitorTests: XCTestCase {

    // MARK: - 1. All 5 Flow Modes

    func testAllFiveFlowModes() {
        let resolver = makeIsolatedResolver()
        let magSafeAdapter = RawAdapterEntry(
            index: 0,
            name: "70W USB-C Power Adapter",
            manufacturer: "Apple Inc.",
            serialNumber: "C02TEST",
            model: "A2743",
            description: "pd charger",
            watts: 68,
            voltageMV: 20_000,
            currentMA: 3_390,
            adapterID: 28_672
        )

        // 1) connectingAC
        let connectingSnap = resolver.resolve(
            reading: makeReading(isExternalConnected: true, isCharging: false, activeAdapter: nil),
            smc: .empty,
            connectionPhase: .connectingAC,
            isLowPowerModeEnabled: false
        )
        XCTAssertEqual(connectingSnap.flowMode, .connectingAC)
        XCTAssertNil(connectingSnap.timeRemainingMinutes)

        // 2) batteryOnly (stale SystemPowerIn must be suppressed!)
        let batterySnap = resolver.resolve(
            reading: makeReading(
                currentCapacityPercent: 72,
                isExternalConnected: false,
                isCharging: false,
                voltageMV: 12_200,
                instantAmperageMA: -1_500,
                telemetrySystemPowerInMW: 31_900, // stale glitch that must be zeroed
                telemetrySystemLoadMW: 18_300,
                telemetryBatteryPowerMW: 18_300, // unsigned positive magnitude on Apple Silicon
                activeAdapter: magSafeAdapter
            ),
            smc: SMCPowerSample(deliveryRateW: 31.9, systemTotalW: 18.3, batteryRateW: -18.3),
            connectionPhase: .onBattery,
            isLowPowerModeEnabled: false
        )
        XCTAssertEqual(batterySnap.flowMode, .batteryOnly)
        XCTAssertEqual(batterySnap.adapterInputPowerW, 0, accuracy: 0.001)
        XCTAssertNil(batterySnap.activeAdapter)
        XCTAssertLessThan(batterySnap.batteryPowerW, 0)
        XCTAssertLessThan(batterySnap.batteryCurrentA, 0)
        XCTAssertEqual(batterySnap.batteryPowerW, -18.3, accuracy: 0.01)

        // 3) adapterCharging
        let chargingSnap = resolver.resolve(
            reading: makeReading(
                currentCapacityPercent: 50,
                isExternalConnected: true,
                isCharging: true,
                timeRemainingMinutes: 45,
                voltageMV: 12_800,
                instantAmperageMA: 2_500,
                telemetrySystemPowerInMW: 55_000,
                telemetrySystemLoadMW: 23_000,
                telemetryBatteryPowerMW: 32_000,
                activeAdapter: magSafeAdapter
            ),
            smc: SMCPowerSample(deliveryRateW: 55.0, systemTotalW: 23.0, batteryRateW: 32.0),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )
        XCTAssertEqual(chargingSnap.flowMode, .adapterCharging)
        XCTAssertGreaterThan(chargingSnap.batteryPowerW, 0)
        XCTAssertGreaterThan(chargingSnap.batteryCurrentA, 0)
        XCTAssertEqual(chargingSnap.timeRemainingMinutes, 45)
        XCTAssertTrue(chargingSnap.isTimeEstimateToFull)

        // 4) adapterBatteryHybrid (AC + Battery both discharging under heavy load)
        let hybridSnap = resolver.resolve(
            reading: makeReading(
                currentCapacityPercent: 60,
                isExternalConnected: true,
                isCharging: false,
                voltageMV: 12_100,
                instantAmperageMA: -1_800,
                telemetrySystemPowerInMW: 65_000,
                telemetrySystemLoadMW: 86_800,
                telemetryBatteryPowerMW: -21_800,
                activeAdapter: magSafeAdapter
            ),
            smc: SMCPowerSample(deliveryRateW: 65.0, systemTotalW: 86.8, batteryRateW: -21.8),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )
        XCTAssertEqual(hybridSnap.flowMode, .adapterBatteryHybrid)
        XCTAssertEqual(hybridSnap.batteryPowerW, -21.8, accuracy: 0.01)
        XCTAssertEqual(hybridSnap.batteryCurrentA, -1.8, accuracy: 0.01)
        XCTAssertFalse(hybridSnap.isTimeEstimateToFull)

        // 5) adapterBypass (100% / idle, telemetry lag AND Apple Silicon PPBR quiescent offset must NOT mislabel!)
        let bypassSnap = resolver.resolve(
            reading: makeReading(
                currentCapacityPercent: 100,
                isExternalConnected: true,
                isCharging: false,
                isFullyCharged: true,
                voltageMV: 13_100,
                instantAmperageMA: 0,
                telemetrySystemPowerInMW: 31_990,
                telemetrySystemLoadMW: 33_190,
                telemetryBatteryPowerMW: -1_200, // transient lag while InstantAmperage is 0
                activeAdapter: magSafeAdapter
            ),
            smc: SMCPowerSample(deliveryRateW: 31.99, systemTotalW: 33.19, batteryRateW: 0.65, batteryCurrentA: 0),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )
        XCTAssertEqual(bypassSnap.flowMode, .adapterBypass)
        XCTAssertEqual(bypassSnap.batteryPowerW, 0, accuracy: 0.001)
        XCTAssertEqual(bypassSnap.batteryCurrentA, 0, accuracy: 0.001)
        XCTAssertNil(bypassSnap.timeRemainingMinutes)
    }

    // MARK: - 2. Outbound Port Mapping, Standby Adapter, and Net System Load Math

    func testOutboundPortMappingAndNetSystemLoadMath() {
        let resolver = makeIsolatedResolver()

        let activeRaw = RawAdapterEntry(
            index: 0,
            name: "70W USB-C Power Adapter",
            manufacturer: "Apple Inc.",
            serialNumber: "C02ACTIVE",
            model: "A2743",
            description: "pd charger",
            watts: 68,
            voltageMV: 20_000,
            currentMA: 3_390,
            adapterID: 1001
        )
        let standbyRaw = RawAdapterEntry(
            index: 1,
            name: "Demo Display",
            manufacturer: "Demo Display Maker",
            serialNumber: nil,
            model: nil,
            description: "usb host",
            watts: 15,
            voltageMV: 5_000,
            currentMA: 3_000,
            adapterID: 2002
        )

        let topology: [IOPortTopologyEntry] = [
            IOPortTopologyEntry(
                portKind: .magSafe,
                portNumber: 1,
                portLabel: "MagSafe 3",
                connectionActive: true,
                isWinningPowerSource: true,
                winningMaxPowerMW: 70_000,
                winningMaxCurrentMA: 3_500,
                standbyMaxPowerMW: nil,
                sopVendorID: nil,
                sopProductID: nil,
                usbProductName: nil,
                usbManufacturer: nil,
                isDisplayPortActive: false
            ),
            IOPortTopologyEntry(
                portKind: .usbC,
                portNumber: 1,
                portLabel: "USB-C 1",
                connectionActive: true,
                isWinningPowerSource: false,
                winningMaxPowerMW: nil,
                winningMaxCurrentMA: nil,
                standbyMaxPowerMW: 15_000,
                sopVendorID: 0x0B05,
                sopProductID: 0x1A2B,
                usbProductName: "Demo Display",
                usbManufacturer: "Demo Display Maker",
                isDisplayPortActive: true
            ),
            IOPortTopologyEntry(
                portKind: .usbC,
                portNumber: 2,
                portLabel: "USB-C 2",
                connectionActive: true,
                isWinningPowerSource: false,
                winningMaxPowerMW: nil,
                winningMaxCurrentMA: nil,
                standbyMaxPowerMW: nil,
                sopVendorID: 0x2717,
                sopProductID: 0xFF40,
                usbProductName: "Demo Phone",
                usbManufacturer: "Demo Maker",
                isDisplayPortActive: false
            ),
            IOPortTopologyEntry(
                portKind: .usbC,
                portNumber: 3,
                portLabel: "USB-C 3",
                connectionActive: true,
                isWinningPowerSource: false,
                winningMaxPowerMW: nil,
                winningMaxCurrentMA: nil,
                standbyMaxPowerMW: nil,
                sopVendorID: 0x1050,
                sopProductID: 0x0407,
                usbProductName: nil,
                usbManufacturer: nil,
                isDisplayPortActive: true
            ),
            IOPortTopologyEntry(
                portKind: .usbC,
                portNumber: 4,
                portLabel: "USB-C 4",
                connectionActive: true,
                isWinningPowerSource: false,
                winningMaxPowerMW: nil,
                winningMaxCurrentMA: nil,
                standbyMaxPowerMW: nil,
                sopVendorID: 0x9999,
                sopProductID: 0x8888,
                usbProductName: "NVMe SSD Enclosure",
                usbManufacturer: "Acasis",
                isDisplayPortActive: false
            )
        ]

        let powerOut: [RawPowerOutEntry] = [
            // Direct USB-C 2 match -> "Demo Phone"
            RawPowerOutEntry(
                portIndex: 2,
                wattsMW: 5_200,
                filteredPowerMW: 5_100,
                currentMA: 1_040,
                voltageMV: 5_000,
                configuredVoltageMV: 5_000,
                configuredCurrentMA: 3_000,
                pdPowerMW: 15_000,
                vconnCurrentMA: 40,
                vconnPowerMW: 200
            ),
            // Direct USB-C 3 match with DP active and nil USB name -> "External Display"
            RawPowerOutEntry(
                portIndex: 3,
                wattsMW: 3_180,
                filteredPowerMW: 3_150,
                currentMA: 560,
                voltageMV: 5_000,
                configuredVoltageMV: 5_000,
                configuredCurrentMA: 1_500,
                pdPowerMW: 7_500,
                vconnCurrentMA: 0,
                vconnPowerMW: 0
            ),
            // Fallback via FedDetails VID/PID match when portIndex differs from topology number
            RawPowerOutEntry(
                portIndex: 5,
                wattsMW: 2_500,
                filteredPowerMW: 2_500,
                currentMA: 500,
                voltageMV: 5_000,
                configuredVoltageMV: 5_000,
                configuredCurrentMA: 3_000,
                pdPowerMW: 15_000,
                vconnCurrentMA: 0,
                vconnPowerMW: 0
            )
        ]

        let fedDetails: [RawFedPortEntry] = [
            RawFedPortEntry(
                arrayIndex: 5,
                portPowerRole: 1,
                vendorID: 0x9999,
                productID: 0x8888,
                externalConnected: true
            )
        ]

        let reading = makeReading(
            currentCapacityPercent: 100,
            isExternalConnected: true,
            isCharging: false,
            isFullyCharged: true,
            telemetrySystemPowerInMW: 32_000,
            telemetrySystemLoadMW: 33_190,
            activeAdapter: activeRaw,
            rawAdapters: [activeRaw, standbyRaw],
            powerOutDetails: powerOut,
            fedDetails: fedDetails
        )

        let snap = resolver.resolve(
            reading: reading,
            smc: SMCPowerSample(deliveryRateW: 32.0, systemTotalW: 33.19, batteryRateW: 0),
            portTopology: topology,
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )

        // Active adapter -> MagSafe 3
        XCTAssertEqual(snap.activeAdapter?.portLabel, "MagSafe 3")
        XCTAssertEqual(snap.activeAdapter?.portKind, .magSafe)
        XCTAssertEqual(snap.activeAdapter?.ratedWatts, 68)

        // Standby adapter -> USB-C 1 · Demo Display · 15W
        XCTAssertEqual(snap.standbyAdapters.count, 1)
        XCTAssertEqual(snap.standbyAdapters.first?.portLabel, "USB-C 1")
        XCTAssertEqual(snap.standbyAdapters.first?.connectedDeviceName, "Demo Display")
        XCTAssertEqual(snap.standbyAdapters.first?.ratedWatts, 15)

        // Outbound ports & names
        XCTAssertEqual(snap.outboundPorts.count, 3)
        XCTAssertEqual(snap.outboundPorts[0].portLabel, "USB-C 2")
        XCTAssertEqual(snap.outboundPorts[0].deviceName, "Demo Phone")
        XCTAssertEqual(snap.outboundPorts[0].powerW, 5.2, accuracy: 0.001)

        XCTAssertEqual(snap.outboundPorts[1].portLabel, "USB-C 3")
        XCTAssertEqual(snap.outboundPorts[1].deviceName, "External Display")
        XCTAssertTrue(snap.outboundPorts[1].isDisplayPortActive)

        XCTAssertEqual(snap.outboundPorts[2].deviceName, "NVMe SSD Enclosure")
        XCTAssertEqual(snap.outboundPorts[2].manufacturer, "Acasis")

        // Totals & netSystemLoadW math
        XCTAssertEqual(snap.totalOutboundPowerW, 10.88, accuracy: 0.01)
        XCTAssertEqual(snap.totalOutboundCurrentA, 2.10, accuracy: 0.01)
        // Idle battery on AC: the load is the adapter input, not the trailing PSTR reading.
        XCTAssertEqual(snap.netSystemLoadW, 32.0 - 10.88, accuracy: 0.01)

        // Health percentages: realHealth = 6132/6249 = 98.127%, macOS = min(100, round(6284/6249*100)) = 100
        XCTAssertEqual(snap.health.macOSCapacityPercent, 100)
        XCTAssertEqual(snap.health.realHealthPercent ?? 0, 98.13, accuracy: 0.05)
    }

    // MARK: - 3. SMC PPBR Polarity Calibration

    func testSMCPolarityAutoCalibrationInvertedAndNormal() {
        let calibrator = SMCPolarityCalibrator(userDefaults: nil, modelIdentifier: "TestInvertedMac")
        let resolver = PowerFlowResolver(
            polarityCalibrator: calibrator,
            chargeLimitProvider: { _ in .unlimited }
        )

        // Hardware with INVERTED PPBR reports +14.5W while unplugged (discharging)
        let dischargeSnap = resolver.resolve(
            reading: makeReading(
                isExternalConnected: false,
                isCharging: false,
                instantAmperageMA: -1_200
            ),
            smc: SMCPowerSample(systemTotalW: 14.5, batteryRateW: 14.5),
            connectionPhase: .onBattery,
            isLowPowerModeEnabled: false
        )
        XCTAssertEqual(calibrator.currentPolarity, .inverted)
        XCTAssertEqual(dischargeSnap.batteryPowerW, -14.5, accuracy: 0.01)

        // Subsequently charging with inverted PPBR (-28.0W raw) must normalize to +28.0W
        let chargeSnap = resolver.resolve(
            reading: makeReading(
                isExternalConnected: true,
                isCharging: true,
                instantAmperageMA: 2_200
            ),
            smc: SMCPowerSample(deliveryRateW: 45.0, systemTotalW: 17.0, batteryRateW: -28.0),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )
        XCTAssertEqual(calibrator.currentPolarity, .inverted)
        XCTAssertEqual(chargeSnap.batteryPowerW, 28.0, accuracy: 0.01)
        XCTAssertEqual(chargeSnap.flowMode, .adapterCharging)

        // Normal polarity Mac reports +25W while charging
        let normalCalibrator = SMCPolarityCalibrator(userDefaults: nil, modelIdentifier: "TestNormalMac")
        let normalized = normalCalibrator.normalizeBatteryPower(
            rawPPBR: 25.0,
            isExternalConnected: true,
            isCharging: true
        )
        XCTAssertEqual(normalCalibrator.currentPolarity, .normal)
        XCTAssertEqual(normalized, 25.0, accuracy: 0.001)
    }

    // MARK: - 4. Charge-Limit-Aware Time Estimation

    func testTimeEstimationRespectsChargeLimitAndSanitizesOSSentinel() {
        let resolver = makeIsolatedResolver(
            chargeLimit: BatteryChargeLimitInfo(limitPercent: 80, source: .alDente)
        )

        // OS reports 65535 (invalid) or a 100%-targeted estimate; at 60% charging toward 80% limit,
        // estimator should compute time to 80%, not 100%.
        let snap = resolver.resolve(
            reading: makeReading(
                currentCapacityPercent: 60,
                isExternalConnected: true,
                isCharging: true,
                timeRemainingMinutes: 65_535,
                voltageMV: 12_500,
                instantAmperageMA: 2_000,
                rawMaxCapacityMAh: 6_000,
                currentChargeMAh: 3_600
            ),
            smc: SMCPowerSample(deliveryRateW: 40.0, systemTotalW: 15.0, batteryRateW: 25.0),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )

        XCTAssertEqual(snap.chargeLimitPercent, 80)
        XCTAssertEqual(snap.chargeLimitSource, .alDente)
        XCTAssertTrue(snap.isTimeEstimateToFull)
        // Needed: (80% - 60%) * 6000 mAh = 1200 mAh at 2000 mA -> 0.6h = 36 min
        XCTAssertEqual(snap.timeRemainingMinutes, 36)
    }

    // MARK: - 5. Plug / Unplug State Machine Transitions

    func testPlugUnplugStateMachineTransitions() {
        var machine = PowerConnectionStateMachine(connectingTimeout: 3.0, unplugDebounce: 1.5)
        let t0 = Date(timeIntervalSince1970: 1_000)

        // Initial launch on battery
        XCTAssertEqual(machine.advance(isExternalConnected: false, hasValidACTelemetry: false, now: t0), .onBattery)

        // Plug in -> enters connectingAC
        let t1 = t0.addingTimeInterval(1.0)
        XCTAssertEqual(machine.advance(isExternalConnected: true, hasValidACTelemetry: false, now: t1), .connectingAC)

        // Still negotiating at +1.0s without valid AC telemetry -> stays connectingAC
        XCTAssertEqual(
            machine.advance(isExternalConnected: true, hasValidACTelemetry: false, now: t1.addingTimeInterval(1.0)),
            .connectingAC
        )

        // Valid AC telemetry arrives at +1.5s -> settles to onAC
        let t2 = t1.addingTimeInterval(1.5)
        XCTAssertEqual(machine.advance(isExternalConnected: true, hasValidACTelemetry: true, now: t2), .onAC)

        // Brief 0.6s PD renegotiation disconnect blip -> debounced, remains onAC
        let t3 = t2.addingTimeInterval(10.0)
        XCTAssertEqual(machine.advance(isExternalConnected: false, hasValidACTelemetry: false, now: t3), .onAC)
        XCTAssertEqual(
            machine.advance(isExternalConnected: false, hasValidACTelemetry: false, now: t3.addingTimeInterval(0.6)),
            .onAC
        )
        // Reconnects within 1.5s -> stays onAC
        XCTAssertEqual(
            machine.advance(isExternalConnected: true, hasValidACTelemetry: true, now: t3.addingTimeInterval(0.9)),
            .onAC
        )

        // Genuine unplug sustained beyond 1.5s -> transitions to onBattery
        let t4 = t3.addingTimeInterval(5.0)
        XCTAssertEqual(machine.advance(isExternalConnected: false, hasValidACTelemetry: false, now: t4), .onAC)
        XCTAssertEqual(
            machine.advance(isExternalConnected: false, hasValidACTelemetry: false, now: t4.addingTimeInterval(1.5)),
            .onBattery
        )

        // Slow adapter timeout: connectingAC settles to onAC after 3.0s even without telemetry
        let t5 = t4.addingTimeInterval(5.0)
        XCTAssertEqual(machine.advance(isExternalConnected: true, hasValidACTelemetry: false, now: t5), .connectingAC)
        XCTAssertEqual(
            machine.advance(isExternalConnected: true, hasValidACTelemetry: false, now: t5.addingTimeInterval(3.0)),
            .onAC
        )
    }

    // MARK: - 6. Adaptive Zero-Overhead Timer Policy

    @MainActor
    func testAdaptiveTimerPolicyZeroTimerWhenDormant() {
        let store = PowerSettingsStore(userDefaults: nil, manageLaunchAtLogin: false)
        store.settings = PowerSettings(
            menuBarDisplayMode: .iconOnly,
            liveRefreshInterval: .standard
        )

        let mockBattery = MockSmartBatteryReader(reading: makeReading())
        let mockPorts = MockIOPortReader(entries: [])
        let mockSMC = SMCReader(keyReader: SilentSMCKeyReader())
        let mockNotifier = MockPowerEventNotifier()

        let monitor = PowerMonitor(
            settingsStore: store,
            smartBatteryReader: mockBattery,
            ioPortReader: mockPorts,
            smcReader: mockSMC,
            notifier: mockNotifier,
            resolver: makeIsolatedResolver(),
            isDisplayAsleepProvider: { false }
        )
        defer { monitor.stop() }

        monitor.start()

        // Dormant `.iconOnly` mode: NO recurring timer!
        XCTAssertEqual(monitor.activePollingTier, .dormant)
        XCTAssertFalse(monitor.hasActiveTimer)
        XCTAssertFalse(monitor.isLiveStreaming)

        // `.iconAndPercentage` when hidden: STILL NO recurring timer!
        store.settings.menuBarDisplayMode = .iconAndPercentage
        XCTAssertEqual(monitor.activePollingTier, .dormant)
        XCTAssertFalse(monitor.hasActiveTimer)

        // `.iconAndWatts` when hidden: lightweight 3.0s summary timer
        store.settings.menuBarDisplayMode = .iconAndWatts
        XCTAssertEqual(monitor.activePollingTier, .summary(interval: 3.0))
        XCTAssertTrue(monitor.hasActiveTimer)
        XCTAssertFalse(monitor.isLiveStreaming)

        // Back to `.iconOnly`: timer immediately cancelled!
        store.settings.menuBarDisplayMode = .iconOnly
        XCTAssertEqual(monitor.activePollingTier, .dormant)
        XCTAssertFalse(monitor.hasActiveTimer)

        // Opening popover activates live tier at configured interval (1.0s)
        monitor.setPopoverVisible(true)
        XCTAssertEqual(monitor.activePollingTier, .live(interval: 1.0))
        XCTAssertTrue(monitor.hasActiveTimer)
        XCTAssertTrue(monitor.isLiveStreaming)

        // Changing live refresh rate updates interval
        store.settings.liveRefreshInterval = .relaxed
        XCTAssertEqual(monitor.activePollingTier, .live(interval: 2.0))

        // Screen sleep cancels timer immediately even while popover/dashboard visible
        mockNotifier.emit(.screensDidSleep)
        let sleepExp = expectation(description: "screen sleep processed")
        DispatchQueue.main.async { sleepExp.fulfill() }
        wait(for: [sleepExp], timeout: 1.0)
        XCTAssertEqual(monitor.activePollingTier, .suspended)
        XCTAssertFalse(monitor.hasActiveTimer)
        XCTAssertFalse(monitor.isLiveStreaming)

        // Screen wake restores live tier
        mockNotifier.emit(.screensDidWake)
        let wakeExp = expectation(description: "screen wake processed")
        DispatchQueue.main.async { wakeExp.fulfill() }
        wait(for: [wakeExp], timeout: 1.0)
        XCTAssertEqual(monitor.activePollingTier, .live(interval: 2.0))
        XCTAssertTrue(monitor.hasActiveTimer)
        XCTAssertTrue(monitor.isLiveStreaming)

        // Closing popover drops back to dormant zero-timer mode
        monitor.setPopoverVisible(false)
        XCTAssertEqual(monitor.activePollingTier, .dormant)
        XCTAssertFalse(monitor.hasActiveTimer)
        XCTAssertFalse(monitor.isLiveStreaming)
    }

    // MARK: - 7. Discharge-Only Apple Silicon PPBR Fallback While Charging

    func testDischargeOnlyPPBRWhileChargingFallsBackAndPreservesPolarity() {
        let calibrator = SMCPolarityCalibrator(userDefaults: nil, modelIdentifier: "TestAppleSiliconMac")
        let resolver = PowerFlowResolver(
            polarityCalibrator: calibrator,
            chargeLimitProvider: { _ in .unlimited }
        )

        // Charging at +2.5 A @ 13.0 V (~32.5 W), while Apple Silicon discharge-only PPBR sits at 0.62 W.
        let viFallbackSnap = resolver.resolve(
            reading: makeReading(
                currentCapacityPercent: 55,
                isExternalConnected: true,
                isCharging: true,
                voltageMV: 13_000,
                instantAmperageMA: 2_500,
                telemetrySystemPowerInMW: 50_000,
                telemetrySystemLoadMW: 17_500,
                telemetryBatteryPowerMW: nil
            ),
            smc: SMCPowerSample(
                deliveryRateW: 50.0,
                systemTotalW: 17.5,
                batteryRateW: 0.62,
                batteryVoltageV: 13.0,
                batteryCurrentA: 2.5
            ),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )

        XCTAssertEqual(viFallbackSnap.flowMode, .adapterCharging)
        XCTAssertEqual(viFallbackSnap.batteryPowerW, 32.5, accuracy: 0.05)
        XCTAssertEqual(viFallbackSnap.batteryCurrentA, 2.5, accuracy: 0.01)
        // Quiescent 0.62 W (< 2.0 W threshold) must NOT corrupt uncalibrated polarity to .normal!
        XCTAssertNil(calibrator.currentPolarity)

        // If polarity was already calibrated to .inverted during discharge (+14.5 W while unplugged),
        // subsequent charging with quiescent 0.62 W PPBR must preserve .inverted and prefer IOKit telemetry.
        _ = resolver.resolve(
            reading: makeReading(
                isExternalConnected: false,
                isCharging: false,
                voltageMV: 12_000,
                instantAmperageMA: -1_200
            ),
            smc: SMCPowerSample(systemTotalW: 14.5, batteryRateW: 14.5),
            connectionPhase: .onBattery,
            isLowPowerModeEnabled: false
        )
        XCTAssertEqual(calibrator.currentPolarity, .inverted)

        let telemetryFallbackSnap = resolver.resolve(
            reading: makeReading(
                currentCapacityPercent: 56,
                isExternalConnected: true,
                isCharging: true,
                voltageMV: 13_000,
                instantAmperageMA: 2_500,
                telemetrySystemPowerInMW: 50_000,
                telemetrySystemLoadMW: 18_000,
                telemetryBatteryPowerMW: 32_000
            ),
            smc: SMCPowerSample(
                deliveryRateW: 50.0,
                systemTotalW: 18.0,
                batteryRateW: 0.62,
                batteryVoltageV: 13.0,
                batteryCurrentA: 2.5
            ),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )
        XCTAssertEqual(calibrator.currentPolarity, .inverted)
        XCTAssertEqual(telemetryFallbackSnap.flowMode, .adapterCharging)
        XCTAssertEqual(telemetryFallbackSnap.batteryPowerW, 32.0, accuracy: 0.05)
    }

    // MARK: - 8. Dormant Steady-State IOPS Notifications Suppress Plug Bursts & Cell Scans

    @MainActor
    func testSteadyStatePowerSourceChangedSuppressesPlugBurstsAndCellScans() {
        let store = PowerSettingsStore(userDefaults: nil, manageLaunchAtLogin: false)
        store.settings = PowerSettings(
            menuBarDisplayMode: .iconOnly,
            liveRefreshInterval: .standard
        )

        let mockBattery = MockSmartBatteryReader(
            reading: makeReading(currentCapacityPercent: 80, isExternalConnected: true, isCharging: false)
        )
        let mockPorts = MockIOPortReader(entries: [])
        let mockSMC = SMCReader(keyReader: SilentSMCKeyReader())
        let mockNotifier = MockPowerEventNotifier()

        let monitor = PowerMonitor(
            settingsStore: store,
            smartBatteryReader: mockBattery,
            ioPortReader: mockPorts,
            smcReader: mockSMC,
            notifier: mockNotifier,
            resolver: makeIsolatedResolver(),
            isDisplayAsleepProvider: { false }
        )
        defer { monitor.stop() }

        monitor.start()

        // Wait for initial startup sample to complete
        let startExp = expectation(description: "initial sample")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { startExp.fulfill() }
        wait(for: [startExp], timeout: 1.0)

        XCTAssertEqual(monitor.snapshot.batteryPercent, 80)
        XCTAssertFalse(monitor.hasPendingBurstRefreshes)
        XCTAssertEqual(mockBattery.cellTopologyScanCount, 0)

        mockBattery.resetCounters()
        mockPorts.resetCounters()

        // Routine 1% SoC update while still on AC (steady state — no plug/unplug transition!)
        mockBattery.setReading(
            makeReading(currentCapacityPercent: 79, isExternalConnected: true, isCharging: false)
        )
        mockNotifier.emit(.powerSourceChanged)

        let steadyExp = expectation(description: "steady-state powerSourceChanged processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { steadyExp.fulfill() }
        wait(for: [steadyExp], timeout: 1.0)

        XCTAssertEqual(monitor.snapshot.batteryPercent, 79)
        XCTAssertFalse(monitor.hasPendingBurstRefreshes)
        XCTAssertEqual(mockBattery.readCount, 1)
        XCTAssertEqual(mockBattery.cellTopologyScanCount, 0)
        XCTAssertEqual(mockPorts.readCount, 0)

        // Real unplug event (isExternalConnected: true -> false) MUST schedule convergence bursts & port scan,
        // while still keeping cell topology disabled when popover/dashboard are hidden.
        mockBattery.setReading(
            makeReading(currentCapacityPercent: 79, isExternalConnected: false, isCharging: false)
        )
        mockNotifier.emit(.powerSourceChanged)

        let unplugExp = expectation(description: "unplug transition processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { unplugExp.fulfill() }
        wait(for: [unplugExp], timeout: 1.0)

        XCTAssertTrue(monitor.hasPendingBurstRefreshes)
        XCTAssertGreaterThanOrEqual(mockPorts.readCount, 1)
        XCTAssertEqual(mockBattery.cellTopologyScanCount, 0)
    }

    // MARK: - 9. Real DispatchSourceTimer & Burst Execution on Telemetry Queue (Swift 6 Isolation)

    @MainActor
    func testLiveTimerTicksExecuteOnTelemetryQueueWithoutTrapping() {
        let store = PowerSettingsStore(userDefaults: nil, manageLaunchAtLogin: false)
        store.settings = PowerSettings(
            menuBarDisplayMode: .iconOnly,
            liveRefreshInterval: .standard // real 1.0s DispatchSourceTimer
        )

        let tickCounter = LockedCounter()
        let baseReading = makeReading(
            currentCapacityPercent: 50,
            isExternalConnected: true,
            isCharging: true,
            voltageMV: 12_800,
            instantAmperageMA: 2_000
        )
        let mockBattery = DynamicSmartBatteryReader {
            let tick = tickCounter.increment()
            return SmartBatteryReading(
                currentCapacityPercent: min(100, 50 + tick),
                maxCapacityPercent: baseReading.maxCapacityPercent,
                stateOfCharge: min(100, 50 + tick),
                dailyMinSoc: baseReading.dailyMinSoc,
                dailyMaxSoc: baseReading.dailyMaxSoc,
                isExternalConnected: baseReading.isExternalConnected,
                isCharging: baseReading.isCharging,
                isFullyCharged: baseReading.isFullyCharged,
                atCriticalLevel: baseReading.atCriticalLevel,
                notChargingReason: baseReading.notChargingReason,
                slowChargingReason: baseReading.slowChargingReason,
                timeRemainingMinutes: baseReading.timeRemainingMinutes,
                avgTimeToEmptyMinutes: baseReading.avgTimeToEmptyMinutes,
                voltageMV: baseReading.voltageMV,
                instantAmperageMA: baseReading.instantAmperageMA,
                amperageMA: baseReading.amperageMA,
                temperatureC: baseReading.temperatureC,
                telemetrySystemPowerInMW: baseReading.telemetrySystemPowerInMW,
                telemetrySystemLoadMW: baseReading.telemetrySystemLoadMW,
                telemetryBatteryPowerMW: baseReading.telemetryBatteryPowerMW,
                telemetrySystemVoltageInMV: baseReading.telemetrySystemVoltageInMV,
                telemetrySystemCurrentInMA: baseReading.telemetrySystemCurrentInMA,
                telemetryAdapterEfficiencyLossMW: baseReading.telemetryAdapterEfficiencyLossMW,
                activeAdapter: baseReading.activeAdapter,
                rawAdapters: baseReading.rawAdapters,
                powerOutDetails: baseReading.powerOutDetails,
                fedDetails: baseReading.fedDetails,
                designCapacityMAh: baseReading.designCapacityMAh,
                rawMaxCapacityMAh: baseReading.rawMaxCapacityMAh,
                fullChargeCapacityMAh: baseReading.fullChargeCapacityMAh,
                nominalCapacityMAh: baseReading.nominalCapacityMAh,
                currentChargeMAh: baseReading.currentChargeMAh,
                cycleCount: baseReading.cycleCount,
                designCycleCount: baseReading.designCycleCount,
                condition: baseReading.condition,
                manufactureDate: baseReading.manufactureDate,
                batterySerial: baseReading.batterySerial,
                deviceName: baseReading.deviceName,
                cellTopology: baseReading.cellTopology
            )
        }
        let mockPorts = MockIOPortReader(entries: [])
        let mockSMC = SMCReader(keyReader: SilentSMCKeyReader())
        let mockNotifier = MockPowerEventNotifier()

        let monitor = PowerMonitor(
            settingsStore: store,
            smartBatteryReader: mockBattery,
            ioPortReader: mockPorts,
            smcReader: mockSMC,
            notifier: mockNotifier,
            resolver: makeIsolatedResolver(),
            isDisplayAsleepProvider: { false }
        )
        defer { monitor.stop() }

        monitor.start()
        monitor.setPopoverVisible(true)
        XCTAssertEqual(monitor.activePollingTier, .live(interval: 1.0))
        XCTAssertTrue(monitor.hasActiveTimer)

        // Wait for initial sample + at least 2 real DispatchSourceTimer ticks on telemetryQueue (~2.3s).
        let exp = expectation(description: "multiple live timer ticks completed without Swift 6 isolation trap")
        let deadline = Date().addingTimeInterval(4.0)
        func pollUntilTicksReady() {
            if tickCounter.value >= 4 && monitor.snapshot.batteryPercent >= 54 {
                exp.fulfill()
            } else if Date() >= deadline {
                XCTFail("Expected >= 4 reads (incl. >= 2 real timer ticks), got \(tickCounter.value), pct=\(monitor.snapshot.batteryPercent)")
                exp.fulfill()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pollUntilTicksReady()
                }
            }
        }
        pollUntilTicksReady()
        wait(for: [exp], timeout: 4.5)

        monitor.setPopoverVisible(false)
        XCTAssertFalse(monitor.hasActiveTimer)
    }

    @MainActor
    func testPlugEventBurstsExecuteOnTelemetryQueueWithoutTrapping() {
        let store = PowerSettingsStore(userDefaults: nil, manageLaunchAtLogin: false)
        store.settings = PowerSettings(
            menuBarDisplayMode: .iconOnly,
            liveRefreshInterval: .standard
        )

        let mockBattery = MockSmartBatteryReader(
            reading: makeReading(currentCapacityPercent: 80, isExternalConnected: true, isCharging: false)
        )
        let mockPorts = MockIOPortReader(entries: [])
        let mockSMC = SMCReader(keyReader: SilentSMCKeyReader())
        let mockNotifier = MockPowerEventNotifier()

        let monitor = PowerMonitor(
            settingsStore: store,
            smartBatteryReader: mockBattery,
            ioPortReader: mockPorts,
            smcReader: mockSMC,
            notifier: mockNotifier,
            resolver: makeIsolatedResolver(),
            isDisplayAsleepProvider: { false }
        )
        defer { monitor.stop() }

        monitor.start()

        let initExp = expectation(description: "initial read")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { initExp.fulfill() }
        wait(for: [initExp], timeout: 1.0)
        mockBattery.resetCounters()

        // Trigger real unplug transition -> schedules DispatchWorkItem bursts at 0.2s, 0.8s, 2.0s, 3.2s
        mockBattery.setReading(
            makeReading(currentCapacityPercent: 79, isExternalConnected: false, isCharging: false)
        )
        mockNotifier.emit(.powerSourceChanged)

        // Wait past the 0.2s burst offset to verify real DispatchWorkItem executes on telemetryQueue without trapping.
        let burstExp = expectation(description: "plug burst DispatchWorkItem executed on telemetryQueue")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { burstExp.fulfill() }
        wait(for: [burstExp], timeout: 1.5)

        XCTAssertGreaterThanOrEqual(mockBattery.readCount, 2)
    }

    // MARK: - 10. System Breakdown, Wall Power, Battery Wh, and Charging Hold Reason

    func testSystemBreakdownWallPowerAndBatteryWhMath() throws {
        let resolver = makeIsolatedResolver()
        let fans = [
            FanReading(index: 0, rpm: 0, maxRpm: 6_800),
            FanReading(index: 1, rpm: 1_700, maxRpm: 6_800)
        ]
        let cellTopology = BatteryCellTopology(
            seriesCount: 3,
            parallelCount: 2,
            voltagesMV: [4_367, 4_367, 4_368],
            qmaxMAh: [6_461, 6_426, 6_440]
        )

        let snap = resolver.resolve(
            reading: makeReading(
                currentCapacityPercent: 100,
                isExternalConnected: true,
                isCharging: false,
                isFullyCharged: true,
                voltageMV: 13_100,
                instantAmperageMA: 0,
                telemetrySystemPowerInMW: 20_400,
                telemetrySystemLoadMW: 19_260,
                telemetryAdapterEfficiencyLossMW: 260,
                powerOutDetails: [
                    RawPowerOutEntry(
                        portIndex: 2,
                        wattsMW: 8_260,
                        filteredPowerMW: 8_200,
                        currentMA: 1_580,
                        voltageMV: 5_220,
                        configuredVoltageMV: 5_000,
                        configuredCurrentMA: 3_000,
                        pdPowerMW: 15_000,
                        vconnCurrentMA: 0,
                        vconnPowerMW: 0
                    )
                ],
                designCapacityMAh: 6_249,
                rawMaxCapacityMAh: 6_132,
                currentChargeMAh: 5_906,
                cellTopology: cellTopology
            ),
            smc: SMCPowerSample(
                deliveryRateW: 20.4,
                systemTotalW: 19.26,
                batteryRateW: 0,
                batteryVoltageV: 13.1,
                batteryCurrentA: 0,
                packagePowerW: 5.2,
                displayPowerW: 2.1,
                cpuTemperatureC: 58.0,
                gpuTemperatureC: 49.5,
                fans: fans
            ),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false,
            thermalState: .fair
        )

        // Net load = 20.4 - 8.26 = 12.14 W; otherSystemW = 12.14 - 5.2 - 2.1 = 4.84 W
        XCTAssertEqual(snap.netSystemLoadW, 12.14, accuracy: 0.01)
        XCTAssertEqual(snap.systemBreakdown?.packagePowerW ?? 0, 5.2, accuracy: 0.01)
        XCTAssertEqual(snap.systemBreakdown?.displayPowerW ?? 0, 2.1, accuracy: 0.01)
        XCTAssertEqual(snap.systemBreakdown?.otherSystemW ?? 0, 4.84, accuracy: 0.01)
        XCTAssertEqual(snap.systemBreakdown?.cpuTemperatureC ?? 0, 58.0, accuracy: 0.01)
        XCTAssertEqual(snap.systemBreakdown?.gpuTemperatureC ?? 0, 49.5, accuracy: 0.01)
        XCTAssertEqual(snap.systemBreakdown?.thermalState, .fair)
        XCTAssertEqual(snap.systemBreakdown?.fans, fans)

        // Wall power = 20.4 + 0.26 = 20.66 W
        XCTAssertEqual(snap.wallPowerEstimateW ?? 0, 20.66, accuracy: 0.01)

        // Battery Wh: all three unified to 3S nominal pack voltage (11.4 V) so remaining <= fullCharge
        let designWh = try XCTUnwrap(snap.batteryDesignWh)
        let fullChargeWh = try XCTUnwrap(snap.batteryFullChargeWh)
        let remainingWh = try XCTUnwrap(snap.batteryRemainingWh)
        XCTAssertEqual(designWh, 6_249 * 11.4 / 1000.0, accuracy: 0.05)
        XCTAssertEqual(fullChargeWh, 6_132 * 11.4 / 1000.0, accuracy: 0.05)
        XCTAssertEqual(remainingWh, 5_906 * 11.4 / 1000.0, accuracy: 0.05)
        XCTAssertLessThanOrEqual(remainingWh, fullChargeWh)
        XCTAssertEqual(snap.chargingHoldReason, "Fully Charged")

        // Fallback to telemetryWallEnergyEstimateMW when efficiency loss is nil
        let wallFallbackSnap = resolver.resolve(
            reading: makeReading(
                isExternalConnected: true,
                isCharging: true,
                instantAmperageMA: 2_000,
                telemetrySystemPowerInMW: 30_000,
                telemetryWallEnergyEstimateMW: 33_500
            ),
            smc: SMCPowerSample(deliveryRateW: 30.0, systemTotalW: 12.0, batteryRateW: 18.0),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )
        XCTAssertEqual(wallFallbackSnap.wallPowerEstimateW ?? 0, 33.5, accuracy: 0.01)
        XCTAssertNil(wallFallbackSnap.chargingHoldReason)
    }

    // MARK: - 11. Physical Ports Role Classification, PD Profiles, & Lifetime Stats

    func testPhysicalPortsRolesPDProfilesAndLifetimeStats() {
        let resolver = makeIsolatedResolver()
        let pdProfiles = [
            USBPDProfile(index: 0, maxVoltageV: 5, maxCurrentA: 3, maxWatts: 15, isActive: false),
            USBPDProfile(index: 1, maxVoltageV: 9, maxCurrentA: 3, maxWatts: 27, isActive: false),
            USBPDProfile(index: 2, maxVoltageV: 15, maxCurrentA: 3, maxWatts: 45, isActive: false),
            USBPDProfile(index: 3, maxVoltageV: 20, maxCurrentA: 3.39, maxWatts: 67.8, isActive: true)
        ]
        let activeRaw = RawAdapterEntry(
            index: 0,
            name: "70W USB-C Power Adapter",
            manufacturer: "Apple Inc.",
            serialNumber: "C02SAMPLE3",
            model: "A2743",
            description: "pd charger",
            watts: 68,
            voltageMV: 20_000,
            currentMA: 3_390,
            adapterID: 28_672,
            firmwareVersion: "1.0.4",
            hardwareVersion: "1.0",
            activeHvcIndex: 3,
            pdProfiles: pdProfiles
        )
        let lifetime = BatteryLifetimeStats(
            operatingHours: 1_240,
            minTempC: 12.0,
            avgTempC: 22.5,
            maxTempC: 41.0,
            minPackVoltageV: 10.45,
            maxPackVoltageV: 13.15,
            maxChargeCurrentA: 5.4,
            maxDischargeCurrentA: 6.2
        )

        let topology: [IOPortTopologyEntry] = [
            // Intentionally unsorted to verify MagSafe-first, USB-C ascending order
            IOPortTopologyEntry(
                portKind: .usbC, portNumber: 4, portLabel: "USB-C 4",
                connectionActive: false, isWinningPowerSource: false,
                winningMaxPowerMW: nil, winningMaxCurrentMA: nil, standbyMaxPowerMW: nil,
                sopVendorID: nil, sopProductID: nil, usbProductName: nil, usbManufacturer: nil,
                isDisplayPortActive: false
            ),
            IOPortTopologyEntry(
                portKind: .usbC, portNumber: 3, portLabel: "USB-C 3",
                connectionActive: true, isWinningPowerSource: false,
                winningMaxPowerMW: nil, winningMaxCurrentMA: nil, standbyMaxPowerMW: nil,
                sopVendorID: 0x2717, sopProductID: 0xFF40, usbProductName: "Demo Phone", usbManufacturer: "Demo Maker",
                isDisplayPortActive: false, activeTransports: ["CC", "USB2"], cableType: "Passive Cable"
            ),
            IOPortTopologyEntry(
                portKind: .usbC, portNumber: 2, portLabel: "USB-C 2",
                connectionActive: true, isWinningPowerSource: false,
                winningMaxPowerMW: nil, winningMaxCurrentMA: nil, standbyMaxPowerMW: nil,
                sopVendorID: nil, sopProductID: nil, usbProductName: nil, usbManufacturer: nil,
                isDisplayPortActive: true, activeTransports: ["CC", "DisplayPort"], cableType: "Active Cable"
            ),
            IOPortTopologyEntry(
                portKind: .usbC, portNumber: 1, portLabel: "USB-C 1",
                connectionActive: true, isWinningPowerSource: false,
                winningMaxPowerMW: nil, winningMaxCurrentMA: nil, standbyMaxPowerMW: 7_500,
                sopVendorID: 0x0B05, sopProductID: 0x1A2B, usbProductName: "Demo Display", usbManufacturer: "Demo Display Maker",
                isDisplayPortActive: true, activeTransports: ["CC", "USB2", "DisplayPort"], cableType: "Passive Cable"
            ),
            IOPortTopologyEntry(
                portKind: .magSafe, portNumber: 1, portLabel: "MagSafe 3",
                connectionActive: true, isWinningPowerSource: true,
                winningMaxPowerMW: 67_800, winningMaxCurrentMA: 3_390, standbyMaxPowerMW: nil,
                sopVendorID: nil, sopProductID: nil, usbProductName: nil, usbManufacturer: nil,
                isDisplayPortActive: false, activeTransports: ["MagSafe"], cableType: "MagSafe 3 Cable"
            )
        ]

        let snap = resolver.resolve(
            reading: makeReading(
                currentCapacityPercent: 100,
                isExternalConnected: true,
                isCharging: false,
                isFullyCharged: true,
                activeAdapter: activeRaw,
                rawAdapters: [activeRaw],
                powerOutDetails: [
                    RawPowerOutEntry(
                        portIndex: 3,
                        wattsMW: 2_680,
                        filteredPowerMW: 2_650,
                        currentMA: 510,
                        voltageMV: 5_210,
                        configuredVoltageMV: 5_000,
                        configuredCurrentMA: 3_000,
                        pdPowerMW: 15_000,
                        vconnCurrentMA: 20,
                        vconnPowerMW: 100
                    )
                ],
                fedDetails: [
                    RawFedPortEntry(
                        arrayIndex: 3,
                        portPowerRole: 1,
                        vendorID: 0x2717,
                        productID: 0xFF40,
                        externalConnected: true,
                        pdSpecRevision: 3
                    )
                ],
                lifetimeStats: lifetime
            ),
            smc: SMCPowerSample(
                deliveryRateW: 20.5,
                systemTotalW: 19.0,
                batteryRateW: 0,
                adapterInputVoltageV: 20.2,
                adapterInputCurrentA: 1.01
            ),
            portTopology: topology,
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )

        // Active adapter PD profiles & firmware/hw metadata
        XCTAssertEqual(snap.activeAdapter?.firmwareVersion, "1.0.4")
        XCTAssertEqual(snap.activeAdapter?.hardwareVersion, "1.0")
        XCTAssertEqual(snap.activeAdapter?.adapterID, 28_672)
        XCTAssertEqual(snap.activeAdapter?.pdProfiles, pdProfiles)
        XCTAssertEqual(snap.activeAdapter?.activePDProfileIndex, 3)

        // Lifetime stats
        XCTAssertEqual(snap.health.lifetime, lifetime)

        // Enriched outbound port
        XCTAssertEqual(snap.outboundPorts.count, 1)
        XCTAssertEqual(snap.outboundPorts[0].filteredPowerW ?? 0, 2.65, accuracy: 0.01)
        XCTAssertEqual(snap.outboundPorts[0].activeTransports, ["CC", "USB2"])
        XCTAssertEqual(snap.outboundPorts[0].cableType, "Passive Cable")
        XCTAssertEqual(snap.outboundPorts[0].pdSpecRevision, 3)

        // All 5 physical port roles in sorted order: MagSafe 3, USB-C 1..4
        XCTAssertEqual(snap.physicalPorts.map(\.portLabel), ["MagSafe 3", "USB-C 1", "USB-C 2", "USB-C 3", "USB-C 4"])
        XCTAssertEqual(snap.physicalPorts.map(\.role), [.powerInActive, .powerInStandby, .dataOnly, .powerOut, .idle])
        XCTAssertEqual(snap.physicalPorts[0].powerW, 20.5, accuracy: 0.01)
        XCTAssertEqual(snap.physicalPorts[1].maxPDWatts, 7.5, accuracy: 0.01)
        XCTAssertEqual(snap.physicalPorts[2].deviceName, "External Display")
        XCTAssertEqual(snap.physicalPorts[3].deviceName, "Demo Phone")
        XCTAssertEqual(snap.physicalPorts[3].powerW, 2.68, accuracy: 0.01)
        XCTAssertFalse(snap.physicalPorts[4].connectionActive)
    }

    // MARK: - 12. Split-Brain Suppression, Polarity Guardrails, Charge-Limit Holds & Fast Paths

    func testUnplugDebounceSuppressesAdapterAndWallPower() {
        let resolver = makeIsolatedResolver()
        let adapter = RawAdapterEntry(
            index: 0, name: "70W", manufacturer: "Apple", serialNumber: nil, model: nil,
            description: "pd charger", watts: 70, voltageMV: 20_000, currentMA: 3_500, adapterID: 1001
        )
        let snap = resolver.resolve(
            reading: makeReading(
                currentCapacityPercent: 75,
                isExternalConnected: false,
                isCharging: false,
                instantAmperageMA: -1_200,
                telemetrySystemPowerInMW: 30_000,
                telemetryWallEnergyEstimateMW: 33_000,
                activeAdapter: adapter,
                rawAdapters: [adapter]
            ),
            smc: SMCPowerSample(deliveryRateW: 30.0, systemTotalW: 15.0, batteryRateW: -15.0),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false,
            isInTransition: true
        )

        XCTAssertEqual(snap.flowMode, .batteryOnly)
        XCTAssertFalse(snap.isExternalConnected)
        XCTAssertFalse(snap.isEffectivelyOnAC)
        XCTAssertFalse(snap.isAdapterSupplyingPower)
        XCTAssertNil(snap.activeAdapter)
        XCTAssertTrue(snap.standbyAdapters.isEmpty)
        XCTAssertEqual(snap.adapterInputPowerW, 0, accuracy: 0.001)
        XCTAssertNil(snap.wallPowerEstimateW)
    }

    func testSMCPolarityCalibrationGuardsTransitionsRequiresThreeSamplesAndStopsUnsignedFlipFlop() {
        let defaults = InMemoryUserDefaults()
        let calibrator = SMCPolarityCalibrator(userDefaults: defaults, modelIdentifier: "TestGuardMac")
        let resolver = PowerFlowResolver(polarityCalibrator: calibrator, chargeLimitProvider: { _ in .unlimited })

        // First steady-state sample calibrates immediately to .normal (1 UserDefaults write).
        _ = resolver.resolve(
            reading: makeReading(isExternalConnected: false, isCharging: false, instantAmperageMA: -1_500),
            smc: SMCPowerSample(systemTotalW: 18.0, batteryRateW: -18.0),
            connectionPhase: .onBattery,
            isLowPowerModeEnabled: false,
            isInTransition: false
        )
        XCTAssertEqual(calibrator.currentPolarity, .normal)
        XCTAssertEqual(defaults.writeCount, 1)

        // Lagging positive PPBR during transition or with mismatched positive current must NOT flip polarity.
        for _ in 0..<5 {
            _ = resolver.resolve(
                reading: makeReading(isExternalConnected: false, isCharging: false, instantAmperageMA: 1_500),
                smc: SMCPowerSample(systemTotalW: 18.0, batteryRateW: 18.0),
                connectionPhase: .onAC,
                isLowPowerModeEnabled: false,
                isInTransition: true
            )
        }
        XCTAssertEqual(calibrator.currentPolarity, .normal)
        XCTAssertEqual(defaults.writeCount, 1)

        // Two opposite steady-state samples (< 3) must NOT flip a pre-existing stored polarity.
        let storedDefaults = InMemoryUserDefaults()
        storedDefaults.set(SMCBatteryPowerPolarity.inverted.rawValue, forKey: "com.powerflow.smc.ppbrPolarity.RepairMac")
        let repairCalibrator = SMCPolarityCalibrator(userDefaults: storedDefaults, modelIdentifier: "RepairMac")
        let initialWrites = storedDefaults.writeCount
        _ = repairCalibrator.normalizeBatteryPower(rawPPBR: -15.0, isExternalConnected: false, isCharging: false)
        _ = repairCalibrator.normalizeBatteryPower(rawPPBR: -15.0, isExternalConnected: false, isCharging: false)
        XCTAssertEqual(repairCalibrator.currentPolarity, .inverted)
        XCTAssertEqual(storedDefaults.writeCount, initialWrites)

        // Third consecutive steady-state sample repairs corrupted stored polarity -> .normal.
        _ = repairCalibrator.normalizeBatteryPower(rawPPBR: -15.0, isExternalConnected: false, isCharging: false)
        XCTAssertEqual(repairCalibrator.currentPolarity, .normal)
        XCTAssertEqual(storedDefaults.writeCount, initialWrites + 1)

        // Unsigned-PPBR Mac: +15W while discharging AND +25W while charging -> detects flip-flop & stops writes!
        let unsignedDefaults = InMemoryUserDefaults()
        let unsignedCalibrator = SMCPolarityCalibrator(userDefaults: unsignedDefaults, modelIdentifier: "UnsignedMac")
        let dischargeW = unsignedCalibrator.normalizeBatteryPower(rawPPBR: 15.0, isExternalConnected: false, isCharging: false)
        XCTAssertEqual(dischargeW, -15.0, accuracy: 0.01)
        XCTAssertEqual(unsignedDefaults.writeCount, 1)

        for _ in 0..<3 {
            _ = unsignedCalibrator.normalizeBatteryPower(rawPPBR: 25.0, isExternalConnected: true, isCharging: true)
        }
        XCTAssertTrue(unsignedCalibrator.isUnsignedMagnitudeDetected)
        XCTAssertEqual(unsignedDefaults.writeCount, 1)

        // Subsequent plug/unplug cycles never write UserDefaults again and return correct signs.
        let steadyChargeW = unsignedCalibrator.normalizeBatteryPower(rawPPBR: 24.0, isExternalConnected: true, isCharging: true)
        let steadyDischargeW = unsignedCalibrator.normalizeBatteryPower(rawPPBR: 14.0, isExternalConnected: false, isCharging: false)
        XCTAssertEqual(steadyChargeW, 24.0, accuracy: 0.01)
        XCTAssertEqual(steadyDischargeW, -14.0, accuracy: 0.01)
        XCTAssertEqual(unsignedDefaults.writeCount, 1)
    }

    func testChargeLimitNeverFallsBackTo100PercentOSMinutesAndHoldReasonPriority() {
        let alDente80 = BatteryChargeLimitInfo(limitPercent: 80, source: .alDente)
        let resolver = makeIsolatedResolver(chargeLimit: alDente80)

        // At 80% with 80% limit, estimator returns nil; must NOT fall back to 100%-targeted osMinutes (45).
        let atLimitCharging = resolver.resolve(
            reading: makeReading(
                currentCapacityPercent: 80,
                isExternalConnected: true,
                isCharging: true,
                timeRemainingMinutes: 45,
                voltageMV: 12_800,
                instantAmperageMA: 500,
                rawMaxCapacityMAh: 6_000,
                currentChargeMAh: 4_800
            ),
            smc: SMCPowerSample(deliveryRateW: 25.0, systemTotalW: 18.0, batteryRateW: 6.4),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )
        XCTAssertNil(atLimitCharging.timeRemainingMinutes)

        // Thermal protection bit at 80% overrides AlDente charge limit.
        let thermalAtLimit = PowerFlowResolver.resolveChargingHoldReason(
            effectiveOnAC: true,
            flowMode: .adapterBypass,
            isFullyCharged: false,
            batteryPercent: 80,
            chargeLimit: alDente80,
            notChargingReason: 0x0000_0004,
            slowChargingReason: nil
        )
        XCTAssertEqual(thermalAtLimit, "Thermal Protection")

        // Charging hold bit at 40% (below 80% limit) reports Charging On Hold instead of blaming AlDente.
        let holdBelowLimit = PowerFlowResolver.resolveChargingHoldReason(
            effectiveOnAC: true,
            flowMode: .adapterBypass,
            isFullyCharged: false,
            batteryPercent: 40,
            chargeLimit: alDente80,
            notChargingReason: 0x0000_0008,
            slowChargingReason: nil
        )
        XCTAssertEqual(holdBelowLimit, "Charging On Hold")

        // No hold bits at 40% with 80% AlDente limit returns nil (does not blame charge limit).
        let noReasonBelowLimit = PowerFlowResolver.resolveChargingHoldReason(
            effectiveOnAC: true,
            flowMode: .adapterBypass,
            isFullyCharged: false,
            batteryPercent: 40,
            chargeLimit: alDente80,
            notChargingReason: 0,
            slowChargingReason: nil
        )
        XCTAssertNil(noReasonBelowLimit)

        // At 80% with 80% AlDente limit and inhibited bit (0x0008), reports AlDente charge limit.
        let alDenteAtCeiling = PowerFlowResolver.resolveChargingHoldReason(
            effectiveOnAC: true,
            flowMode: .adapterBypass,
            isFullyCharged: false,
            batteryPercent: 80,
            chargeLimit: alDente80,
            notChargingReason: 0x0000_0008,
            slowChargingReason: nil
        )
        XCTAssertEqual(alDenteAtCeiling, "Charge Limit (80% · AlDente)")
    }

    func testIncludeChargeLimitFalseSkipsProviderAndExtremeCapacityClampsSafely() {
        let calls = LockedCounter()
        let resolver = PowerFlowResolver(
            polarityCalibrator: SMCPolarityCalibrator(userDefaults: nil, modelIdentifier: "SkipLimitMac"),
            chargeLimitProvider: { _ in
                calls.increment()
                return BatteryChargeLimitInfo(limitPercent: 80, source: .alDente)
            }
        )

        let skipped = resolver.resolve(
            reading: makeReading(
                isExternalConnected: true,
                designCapacityMAh: 1,
                rawMaxCapacityMAh: Int.max,
                fullChargeCapacityMAh: Int.max,
                nominalCapacityMAh: Int.max
            ),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false,
            includeChargeLimit: false
        )
        XCTAssertEqual(calls.value, 0)
        XCTAssertEqual(skipped.chargeLimitPercent, 100)
        XCTAssertEqual(skipped.health.macOSCapacityPercent, 100)
    }

    @MainActor
    func testDormantSteadyStateSkipsHealthDetailsAndChargeLimit() {
        let store = PowerSettingsStore(userDefaults: nil, manageLaunchAtLogin: false)
        store.settings.menuBarDisplayMode = .iconOnly
        let mockBattery = MockSmartBatteryReader(reading: makeReading(currentCapacityPercent: 80, isExternalConnected: true))
        let mockPorts = MockIOPortReader(entries: [])
        let mockNotifier = MockPowerEventNotifier()
        let chargeLimitCalls = LockedCounter()
        let resolver = PowerFlowResolver(
            polarityCalibrator: SMCPolarityCalibrator(userDefaults: nil, modelIdentifier: "DormantMac"),
            chargeLimitProvider: { _ in
                chargeLimitCalls.increment()
                return .unlimited
            }
        )

        let monitor = PowerMonitor(
            settingsStore: store,
            smartBatteryReader: mockBattery,
            ioPortReader: mockPorts,
            smcReader: SMCReader(keyReader: SilentSMCKeyReader()),
            notifier: mockNotifier,
            resolver: resolver,
            isDisplayAsleepProvider: { false }
        )
        defer { monitor.stop() }
        monitor.start()

        let startExp = expectation(description: "startup sample")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { startExp.fulfill() }
        wait(for: [startExp], timeout: 1.0)

        XCTAssertEqual(mockBattery.healthDetailsScanCount, 1)
        XCTAssertEqual(chargeLimitCalls.value, 1)

        mockBattery.resetCounters()
        let beforeLimitCalls = chargeLimitCalls.value
        mockNotifier.emit(.powerSourceChanged)

        let eventExp = expectation(description: "dormant steady sample")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { eventExp.fulfill() }
        wait(for: [eventExp], timeout: 1.0)

        XCTAssertEqual(mockBattery.readCount, 1)
        XCTAssertEqual(mockBattery.healthDetailsScanCount, 0)
        XCTAssertEqual(chargeLimitCalls.value, beforeLimitCalls)
    }

    func testCaptureSingleSnapshotReadsFullDetailsAndDefaultsToMemoryOnlyCalibrator() {
        let mockBattery = MockSmartBatteryReader(
            reading: makeReading(currentCapacityPercent: 75, isExternalConnected: false, instantAmperageMA: -1_200)
        )
        let mockPorts = MockIOPortReader(entries: [])
        let mockSMC = SMCReader(keyReader: SilentSMCKeyReader())

        let snapshot = PowerMonitor.captureSingleSnapshot(
            smartBatteryReader: mockBattery,
            ioPortReader: mockPorts,
            smcReader: mockSMC,
            isLowPowerModeEnabled: false
        )

        XCTAssertTrue(snapshot.isDataAvailable)
        XCTAssertEqual(snapshot.flowMode, .batteryOnly)
        XCTAssertEqual(mockBattery.cellTopologyScanCount, 1)
        XCTAssertEqual(mockBattery.healthDetailsScanCount, 1)
        XCTAssertEqual(mockPorts.readCount, 1)
    }
}
