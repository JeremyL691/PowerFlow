import XCTest
@testable import PowerFlow

/// Plug and unplug events that happen while nothing is polling must still settle on their own.
@MainActor
final class PowerTransitionTests: XCTestCase {
    private var battery: MockSmartBatteryReader!
    private var ports: MockIOPortReader!
    private var notifier: MockPowerEventNotifier!

    private func makeMonitor(
        isExternalConnected: Bool,
        clock: @escaping @Sendable () -> Date = Date.init,
        isDisplayAsleepProvider: @escaping @Sendable () -> Bool = { false },
        uptimeProvider: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) -> PowerMonitor {
        battery = MockSmartBatteryReader(reading: makeReading(isExternalConnected: isExternalConnected))
        ports = MockIOPortReader(entries: [])
        notifier = MockPowerEventNotifier()
        return PowerMonitor(
            settingsStore: PowerSettingsStore(userDefaults: nil, manageLaunchAtLogin: false),
            smartBatteryReader: battery,
            ioPortReader: ports,
            smcReader: SMCReader(keyReader: SilentSMCKeyReader()),
            notifier: notifier,
            resolver: makeIsolatedResolver(),
            clock: clock,
            isDisplayAsleepProvider: isDisplayAsleepProvider,
            uptimeProvider: uptimeProvider
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval,
        _ condition: @escaping @MainActor () -> Bool
    ) {
        let settled = expectation(description: description)
        func poll() {
            if condition() {
                settled.fulfill()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    MainActor.assumeIsolated { poll() }
                }
            }
        }
        poll()
        wait(for: [settled], timeout: timeout)
    }

    func testUnplugDuringSleepIsCorrectRightAfterWake() {
        let monitor = makeMonitor(isExternalConnected: true)
        defer { monitor.stop() }
        monitor.start()
        waitUntil("first sample", timeout: 1) { monitor.snapshot.isDataAvailable }

        notifier.emit(.systemWillSleep)
        waitUntil("asleep", timeout: 1) { monitor.activePollingTier == .suspended }
        battery.setReading(makeReading(isExternalConnected: false))
        notifier.emit(.powerSourceChanged)
        notifier.emit(.systemDidWake)
        notifier.emit(.screensDidWake)

        waitUntil("on battery after wake", timeout: 1) {
            !monitor.snapshot.isEffectivelyOnAC && monitor.snapshot.flowMode == .batteryOnly
        }
        XCTAssertEqual(NativeBatteryIconRenderer.overlay(for: monitor.snapshot), .none)
    }

    func testPlugDuringSleepIsCorrectRightAfterWake() {
        let monitor = makeMonitor(isExternalConnected: false)
        defer { monitor.stop() }
        monitor.start()
        waitUntil("first sample", timeout: 1) { monitor.snapshot.isDataAvailable }

        notifier.emit(.systemWillSleep)
        waitUntil("asleep", timeout: 1) { monitor.activePollingTier == .suspended }
        battery.setReading(
            makeReading(isExternalConnected: true, isCharging: true, instantAmperageMA: 2_000, amperageMA: 2_000)
        )
        notifier.emit(.systemDidWake)

        waitUntil("charging after wake", timeout: 1) {
            monitor.snapshot.connectionPhase == .onAC && monitor.snapshot.flowMode == .adapterCharging
        }
        XCTAssertEqual(NativeBatteryIconRenderer.overlay(for: monitor.snapshot), .chargingBolt)
    }

    func testUnplugFollowedByClosingThePopoverStillSettles() {
        let monitor = makeMonitor(isExternalConnected: true)
        defer { monitor.stop() }
        monitor.start()
        monitor.setPopoverVisible(true)
        waitUntil("first sample", timeout: 1) { monitor.snapshot.isDataAvailable }

        battery.setReading(makeReading(isExternalConnected: false))
        notifier.emit(.powerSourceChanged)
        waitUntil("unplug seen", timeout: 1) { !monitor.snapshot.isExternalConnected }
        monitor.setPopoverVisible(false)

        XCTAssertEqual(NativeBatteryIconRenderer.overlay(for: monitor.snapshot), .none)
        waitUntil("debounce settled while dormant", timeout: 5) { monitor.snapshot.connectionPhase == .onBattery }
        XCTAssertEqual(monitor.activePollingTier, .dormant)
        XCTAssertFalse(monitor.hasActiveTimer)
    }

    func testFollowUpBurstsEnd() {
        let monitor = makeMonitor(isExternalConnected: true)
        defer { monitor.stop() }
        monitor.start()
        waitUntil("first sample", timeout: 1) { monitor.snapshot.isDataAvailable }

        battery.setReading(makeReading(isExternalConnected: false))
        notifier.emit(.powerSourceChanged)
        waitUntil("bursts scheduled", timeout: 1) { monitor.hasPendingBurstRefreshes }
        waitUntil("bursts finished", timeout: 5) { !monitor.hasPendingBurstRefreshes }

        battery.resetCounters()
        let quiet = expectation(description: "quiet period")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { quiet.fulfill() }
        wait(for: [quiet], timeout: 2)
        XCTAssertEqual(battery.readCount, 0)
    }

    func testDailyMaximumChargeIsNotTreatedAsALimit() {
        let snapshot = makeIsolatedResolver().resolve(
            reading: makeReading(
                currentCapacityPercent: 88,
                dailyMaxSoc: 90,
                isExternalConnected: true,
                isCharging: true,
                instantAmperageMA: 2_000,
                amperageMA: 2_000
            ),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )
        XCTAssertEqual(snapshot.chargeLimitPercent, 100)
        XCTAssertEqual(snapshot.chargeLimitSource, .none)
        XCTAssertNotNil(snapshot.timeRemainingMinutes)
    }

    func testIdleBatteryLoadMatchesAdapterInput() {
        let snapshot = makeIsolatedResolver().resolve(
            reading: makeReading(isExternalConnected: true),
            smc: SMCPowerSample(deliveryRateW: 19.5, systemTotalW: 24.2, batteryCurrentA: 0),
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )
        XCTAssertEqual(snapshot.adapterInputPowerW, 19.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.totalSystemLoadW, 19.5, accuracy: 0.001)
    }

    func testDarkWakeWithDisplayAsleepStaysSuspendedUntilScreenWakes() {
        let displayAsleep = LockedBox(false)
        let monitor = makeMonitor(
            isExternalConnected: true,
            isDisplayAsleepProvider: { displayAsleep.value }
        )
        defer { monitor.stop() }
        monitor.settingsStore.settings.menuBarDisplayMode = .iconAndWatts
        monitor.start()
        waitUntil("first sample", timeout: 1) { monitor.snapshot.isDataAvailable }

        notifier.emit(.systemWillSleep)
        waitUntil("suspended on sleep", timeout: 1) { monitor.activePollingTier == .suspended }
        battery.resetCounters()
        ports.resetCounters()

        // Dark wake (clamshell/Power Nap): system wakes while display remains asleep.
        displayAsleep.value = true
        notifier.emit(.systemDidWake)
        let darkWait = expectation(description: "dark wake processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { darkWait.fulfill() }
        wait(for: [darkWait], timeout: 1)

        XCTAssertEqual(monitor.activePollingTier, .suspended)
        XCTAssertFalse(monitor.hasActiveTimer)
        XCTAssertEqual(battery.readCount, 0)

        // When display finally wakes, summary polling resumes and performs the deferred post-wake full scan.
        displayAsleep.value = false
        notifier.emit(.screensDidWake)
        waitUntil("resumed after screen wake", timeout: 1) {
            monitor.activePollingTier == .summary(interval: PowerMonitor.summaryRefreshInterval)
                && self.battery.readCount >= 1
        }
        XCTAssertTrue(monitor.hasActiveTimer)
        XCTAssertGreaterThanOrEqual(ports.readCount, 1)
    }

    func testBackToBackSystemAndScreenWakeCoalescesIntoSingleRefresh() {
        let uptime = LockedBox<TimeInterval>(100.0)
        let monitor = makeMonitor(
            isExternalConnected: true,
            isDisplayAsleepProvider: { false },
            uptimeProvider: { uptime.value }
        )
        defer { monitor.stop() }
        monitor.start()
        waitUntil("first sample", timeout: 1) { monitor.snapshot.isDataAvailable }

        notifier.emit(.systemWillSleep)
        waitUntil("suspended", timeout: 1) { monitor.activePollingTier == .suspended }
        battery.resetCounters()
        ports.resetCounters()

        // Back-to-back systemDidWake + screensDidWake within coalesce window -> single refresh.
        uptime.value = 200.0
        notifier.emit(.systemDidWake)
        uptime.value = 200.1
        notifier.emit(.screensDidWake)

        let waitExp = expectation(description: "wake refreshes settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { waitExp.fulfill() }
        wait(for: [waitExp], timeout: 1)

        XCTAssertEqual(battery.readCount, 1)
        XCTAssertEqual(ports.readCount, 1)
    }

    func testPortTopologyRefreshesOnAdapterChangeAndPeriodicStaleness() {
        let now = LockedBox(Date(timeIntervalSince1970: 10_000))
        let adapterA = RawAdapterEntry(
            index: 0, name: "70W", manufacturer: nil, serialNumber: nil, model: nil,
            description: nil, watts: 70, voltageMV: 20_000, currentMA: 3_500, adapterID: 1001
        )
        let adapterB = RawAdapterEntry(
            index: 1, name: "15W", manufacturer: nil, serialNumber: nil, model: nil,
            description: nil, watts: 15, voltageMV: 5_000, currentMA: 3_000, adapterID: 2002
        )
        let monitor = makeMonitor(isExternalConnected: true, clock: { now.value })
        defer { monitor.stop() }
        battery.setReading(makeReading(isExternalConnected: true, activeAdapter: adapterA, rawAdapters: [adapterA]))
        monitor.start()
        waitUntil("first sample", timeout: 1) { monitor.snapshot.isDataAvailable }
        ports.resetCounters()

        // Plugging in a 2nd charger while already on AC (isExternalConnected stays true) refreshes port topology.
        now.value = now.value.addingTimeInterval(2.0)
        battery.setReading(makeReading(isExternalConnected: true, activeAdapter: adapterA, rawAdapters: [adapterA, adapterB]))
        notifier.emit(.powerSourceChanged)
        waitUntil("port scan on adapter change", timeout: 1) { self.ports.readCount == 1 }

        // Steady-state event 5s later (< 30s) reuses cache without scanning.
        ports.resetCounters()
        now.value = now.value.addingTimeInterval(5.0)
        notifier.emit(.powerSourceChanged)
        let waitCache = expectation(description: "cached port topology reused")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { waitCache.fulfill() }
        wait(for: [waitCache], timeout: 1)
        XCTAssertEqual(ports.readCount, 0)

        // Event after >= 30s refreshes stale portTopologyCache.
        now.value = now.value.addingTimeInterval(31.0)
        notifier.emit(.powerSourceChanged)
        waitUntil("periodic port scan after 30s", timeout: 1) { self.ports.readCount == 1 }
    }

    func testPlugEdgeLandingDuringBurstWindowStillConverges() {
        let monitor = makeMonitor(isExternalConnected: true)
        defer { monitor.stop() }
        monitor.start()
        waitUntil("first sample", timeout: 1) { monitor.snapshot.isDataAvailable }

        // Start unplug bursts; once settled to onBattery, flip back to plugged-in without IOPS event
        // so the remaining burst item observes externalConnectedChanged and restarts bursts to converge.
        battery.setReading(makeReading(isExternalConnected: false))
        notifier.emit(.powerSourceChanged)
        waitUntil("settled on battery", timeout: 3) { monitor.snapshot.connectionPhase == .onBattery }

        battery.setReading(
            makeReading(isExternalConnected: true, isCharging: true, instantAmperageMA: 2_000, amperageMA: 2_000)
        )
        waitUntil("burst caught re-plug and converged to onAC", timeout: 5) {
            monitor.snapshot.connectionPhase == .onAC && monitor.snapshot.flowMode == .adapterCharging
        }
    }
}
