import XCTest
@testable import PowerFlow

/// Plug and unplug events that happen while nothing is polling must still settle on their own.
@MainActor
final class PowerTransitionTests: XCTestCase {
    private var battery: MockSmartBatteryReader!
    private var notifier: MockPowerEventNotifier!

    private func makeMonitor(isExternalConnected: Bool) -> PowerMonitor {
        battery = MockSmartBatteryReader(reading: makeReading(isExternalConnected: isExternalConnected))
        notifier = MockPowerEventNotifier()
        return PowerMonitor(
            settingsStore: PowerSettingsStore(userDefaults: nil, manageLaunchAtLogin: false),
            smartBatteryReader: battery,
            ioPortReader: MockIOPortReader(entries: []),
            smcReader: SMCReader(keyReader: SilentSMCKeyReader()),
            notifier: notifier,
            resolver: makeIsolatedResolver()
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
        waitUntil("debounce settled while dormant", timeout: 5) { !monitor.snapshot.isEffectivelyOnAC }
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
}
