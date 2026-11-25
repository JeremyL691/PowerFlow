import Foundation
import XCTest
@testable import PowerFlow

final class EnergyDashboardTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 1. Outer App Bundle Path Extraction

    func testExtractOuterAppBundlePath() {
        XCTAssertEqual(
            ProcessEnergyReader.extractOuterAppBundlePath(
                from: "/Applications/Safari.app/Contents/MacOS/Safari"
            ),
            "/Applications/Safari.app"
        )

        XCTAssertEqual(
            ProcessEnergyReader.extractOuterAppBundlePath(
                from: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/120.0/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
            ),
            "/Applications/Google Chrome.app"
        )

        XCTAssertEqual(
            ProcessEnergyReader.extractOuterAppBundlePath(
                from: "/Applications/Slack.app/Contents/XPCServices/SlackHelper.xpc/Contents/MacOS/SlackHelper"
            ),
            "/Applications/Slack.app"
        )

        XCTAssertEqual(
            ProcessEnergyReader.extractOuterAppBundlePath(
                from: "/Applications/MyApp.APP/Contents/MacOS/MyApp"
            ),
            "/Applications/MyApp.APP"
        )

        XCTAssertNil(ProcessEnergyReader.extractOuterAppBundlePath(from: "/usr/local/bin/python3"))
        XCTAssertNil(ProcessEnergyReader.extractOuterAppBundlePath(from: "/opt/homebrew/bin/node"))
        XCTAssertNil(ProcessEnergyReader.extractOuterAppBundlePath(from: ""))
        XCTAssertNil(ProcessEnergyReader.extractOuterAppBundlePath(from: "/.app/Contents/MacOS/foo"))
    }

    // MARK: - 2. ProcessEnergyAggregator Differential Math

    func testAggregatorDifferentialMathAndEnergyImpact() throws {
        let aggregator = ProcessEnergyAggregator(smoothingTau: 2.5)
        let t0 = baseDate
        let t1 = baseDate.addingTimeInterval(2.0)

        let baseline = RawProcessEnergySample(
            pid: 101,
            ppid: 1,
            startAbsTime: 5_000,
            processName: "Renderer",
            executablePath: "/Applications/Browser.app/Contents/MacOS/Renderer",
            appBundlePath: "/Applications/Browser.app",
            appDisplayName: "Browser",
            bundleIdentifier: "com.example.browser",
            energyNJ: 1_000_000_000,      // 1.0 J
            pCoreEnergyNJ: 600_000_000,   // 0.6 J
            billedEnergyNJ: 200_000_000,  // 0.2 J
            cpuTimeNS: 500_000_000,       // 0.5 s
            pCoreTimeNS: 300_000_000,
            idleWakeups: 100,
            diskReadBytes: 10_240,
            diskWriteBytes: 5_120,
            physFootprintBytes: 256 * 1024 * 1024,
            sleepAssertionTypes: []
        )

        let warmSnap = aggregator.ingest(samples: [baseline], at: t0)
        XCTAssertEqual(warmSnap.phase, .warmingUp)
        XCTAssertEqual(warmSnap.windowSeconds, 0)
        XCTAssertEqual(warmSnap.sampledProcessCount, 1)
        XCTAssertEqual(warmSnap.totalMeasuredPowerW, 0)
        XCTAssertTrue(warmSnap.appConsumers.isEmpty)
        XCTAssertTrue(warmSnap.processConsumers.isEmpty)

        // Over dt = 2.0s:
        // deltaEnergyNJ = 4.0 J -> 2.0 W direct
        // deltaPCoreEnergyNJ = 3.0 J -> pCoreShare = 0.75
        // deltaBilledNJ = 1.0 J -> 0.5 W billed
        // total powerW = 2.5 W
        // deltaCPUTimeNS = 1.0 s -> 50.0% CPU
        // deltaWakeups = 400 -> 200.0 /s
        // deltaDisk = 204_800 B -> 102_400 B/s = 100 KB/s
        // energyImpact = 50.0 + 0.1 * 200.0 + 0.002 * 100.0 + 20.0 * 0.5 = 50 + 20 + 0.2 + 10 = 80.2
        let next = RawProcessEnergySample(
            pid: 101,
            ppid: 1,
            startAbsTime: 5_000,
            processName: "Renderer",
            executablePath: "/Applications/Browser.app/Contents/MacOS/Renderer",
            appBundlePath: "/Applications/Browser.app",
            appDisplayName: "Browser",
            bundleIdentifier: "com.example.browser",
            energyNJ: 5_000_000_000,
            pCoreEnergyNJ: 3_600_000_000,
            billedEnergyNJ: 1_200_000_000,
            cpuTimeNS: 1_500_000_000,
            pCoreTimeNS: 900_000_000,
            idleWakeups: 500,
            diskReadBytes: 112_640,
            diskWriteBytes: 107_520,
            physFootprintBytes: 300 * 1024 * 1024,
            sleepAssertionTypes: []
        )

        let readySnap = aggregator.ingest(samples: [next], at: t1)
        XCTAssertEqual(readySnap.phase, .ready)
        XCTAssertEqual(readySnap.windowSeconds, 2.0, accuracy: 0.0001)
        XCTAssertEqual(readySnap.sampledProcessCount, 1)
        XCTAssertEqual(readySnap.totalMeasuredPowerW, 2.5, accuracy: 0.0001)

        let item = try XCTUnwrap(readySnap.processConsumers.first)
        XCTAssertEqual(item.directPowerW, 2.0, accuracy: 0.0001)
        XCTAssertEqual(item.billedPowerW, 0.5, accuracy: 0.0001)
        XCTAssertEqual(item.powerW, 2.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(item.pCoreShare), 0.75, accuracy: 0.0001)
        XCTAssertEqual(item.cpuPercent, 50.0, accuracy: 0.0001)
        XCTAssertEqual(item.wakeupsPerSecond, 200.0, accuracy: 0.0001)
        XCTAssertEqual(item.diskBytesPerSecond, 102_400.0, accuracy: 0.0001)
        XCTAssertEqual(item.energyImpact, 80.2, accuracy: 0.0001)
        XCTAssertEqual(item.memoryBytes, 300 * 1024 * 1024)
    }

    func testAggregatorCPUFallbackWhenEnergyCountersAreAllZero() throws {
        let aggregator = ProcessEnergyAggregator()
        let t0 = baseDate
        let t1 = baseDate.addingTimeInterval(1.0)

        let s0 = RawProcessEnergySample(
            pid: 202,
            startAbsTime: 100,
            processName: "swiftc",
            executablePath: "/usr/bin/swiftc",
            cpuTimeNS: 0,
            pCoreTimeNS: 0
        )
        let s1 = RawProcessEnergySample(
            pid: 202,
            startAbsTime: 100,
            processName: "swiftc",
            executablePath: "/usr/bin/swiftc",
            cpuTimeNS: 1_000_000_000, // 100% CPU over 1.0s -> 2.5W fallback
            pCoreTimeNS: 800_000_000  // 0.8 pCoreShare from CPU time
        )

        _ = aggregator.ingest(samples: [s0], at: t0)
        let snap = aggregator.ingest(samples: [s1], at: t1)
        XCTAssertEqual(snap.phase, .ready)

        let item = try XCTUnwrap(snap.processConsumers.first)
        XCTAssertEqual(item.cpuPercent, 100.0, accuracy: 0.001)
        XCTAssertEqual(item.directPowerW, 2.5, accuracy: 0.001)
        XCTAssertEqual(item.billedPowerW, 0.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(item.pCoreShare), 0.8, accuracy: 0.001)
    }

    // MARK: - 3. PID Reuse & Counter Regression Safety

    func testAggregatorHandlesPIDReuseWithChangedStartAbsTime() throws {
        let aggregator = ProcessEnergyAggregator()

        // T0: PID 300 with startAbsTime = 1000
        _ = aggregator.ingest(
            samples: [
                RawProcessEnergySample(
                    pid: 300,
                    startAbsTime: 1000,
                    processName: "old-proc",
                    executablePath: "/usr/bin/old-proc",
                    energyNJ: 90_000_000_000,
                    cpuTimeNS: 50_000_000_000
                )
            ],
            at: baseDate
        )

        // T1: PID 300 reused with startAbsTime = 2000 -> must NOT diff against old process!
        let snapT1 = aggregator.ingest(
            samples: [
                RawProcessEnergySample(
                    pid: 300,
                    startAbsTime: 2000,
                    processName: "new-proc",
                    executablePath: "/usr/bin/new-proc",
                    energyNJ: 1_000_000_000,
                    cpuTimeNS: 100_000_000
                )
            ],
            at: baseDate.addingTimeInterval(1.0)
        )
        XCTAssertEqual(snapT1.phase, .ready)
        XCTAssertTrue(snapT1.processConsumers.isEmpty)
        XCTAssertEqual(snapT1.totalMeasuredPowerW, 0)

        // T2: same reused PID (startAbsTime = 2000) advances by 2.0 J / 1.0 s -> 2.0 W
        let snapT2 = aggregator.ingest(
            samples: [
                RawProcessEnergySample(
                    pid: 300,
                    startAbsTime: 2000,
                    processName: "new-proc",
                    executablePath: "/usr/bin/new-proc",
                    energyNJ: 3_000_000_000,
                    cpuTimeNS: 600_000_000
                )
            ],
            at: baseDate.addingTimeInterval(2.0)
        )
        let item = try XCTUnwrap(snapT2.processConsumers.first)
        XCTAssertEqual(item.displayName, "new-proc")
        XCTAssertEqual(item.powerW, 2.0, accuracy: 0.001)
        XCTAssertEqual(item.cpuPercent, 50.0, accuracy: 0.001)
    }

    func testAggregatorMonotonicCounterRegressionSafetyAndBackwardClock() {
        let aggregator = ProcessEnergyAggregator()

        let high = RawProcessEnergySample(
            pid: 400,
            startAbsTime: 10,
            processName: "worker",
            executablePath: "/usr/bin/worker",
            energyNJ: 5_000_000_000,
            pCoreEnergyNJ: 2_000_000_000,
            billedEnergyNJ: 1_000_000_000,
            cpuTimeNS: 2_000_000_000,
            pCoreTimeNS: 1_000_000_000,
            idleWakeups: 500,
            diskReadBytes: 100_000,
            diskWriteBytes: 50_000
        )
        _ = aggregator.ingest(samples: [high], at: baseDate)

        // Regressed counters (all smaller than baseline) -> safeDelta must clamp to 0 without underflow.
        let regressed = RawProcessEnergySample(
            pid: 400,
            startAbsTime: 10,
            processName: "worker",
            executablePath: "/usr/bin/worker",
            energyNJ: 100,
            pCoreEnergyNJ: 50,
            billedEnergyNJ: 10,
            cpuTimeNS: 100,
            pCoreTimeNS: 50,
            idleWakeups: 5,
            diskReadBytes: 100,
            diskWriteBytes: 50
        )
        let snap = aggregator.ingest(samples: [regressed], at: baseDate.addingTimeInterval(1.0))
        XCTAssertEqual(snap.phase, .ready)
        XCTAssertEqual(snap.totalMeasuredPowerW, 0)
        XCTAssertTrue(snap.processConsumers.isEmpty)

        // Backward clock resets baseline cleanly without crashing or bogus negative dt.
        let backInTime = aggregator.ingest(samples: [high], at: baseDate.addingTimeInterval(-5.0))
        XCTAssertEqual(backInTime.phase, .warmingUp)
    }

    // MARK: - 4. EMA Smoothing Convergence & Pruning

    func testAggregatorEMASmoothingConvergenceAndExitedProcessPruning() throws {
        let tau: TimeInterval = 2.0
        let aggregator = ProcessEnergyAggregator(smoothingTau: tau)

        func sample(pid: Int32, start: UInt64, energyNJ: UInt64) -> RawProcessEnergySample {
            RawProcessEnergySample(
                pid: pid,
                startAbsTime: start,
                processName: "proc-\(pid)",
                executablePath: "/usr/bin/proc-\(pid)",
                energyNJ: energyNJ
            )
        }

        // T0 baseline: PID 1 & PID 2
        _ = aggregator.ingest(
            samples: [sample(pid: 1, start: 1, energyNJ: 0), sample(pid: 2, start: 2, energyNJ: 0)],
            at: baseDate
        )

        // T1 (+1.0s): PID 1 uses 10.0 J (10.0 W), PID 2 uses 2.0 J (2.0 W) -> first delta initializes EMA directly
        let s1 = aggregator.ingest(
            samples: [
                sample(pid: 1, start: 1, energyNJ: 10_000_000_000),
                sample(pid: 2, start: 2, energyNJ: 2_000_000_000),
            ],
            at: baseDate.addingTimeInterval(1.0)
        )
        XCTAssertEqual(try XCTUnwrap(s1.processConsumers.first { $0.primaryPID == 1 }).powerW, 10.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(s1.processConsumers.first { $0.primaryPID == 2 }).powerW, 2.0, accuracy: 0.0001)

        // T2 (+1.0s): PID 1 drops to 0.0 W; PID 2 has exited
        let alpha = 1.0 - exp(-1.0 / tau)
        let expectedT2 = 10.0 + alpha * (0.0 - 10.0)
        let s2 = aggregator.ingest(
            samples: [sample(pid: 1, start: 1, energyNJ: 10_000_000_000)],
            at: baseDate.addingTimeInterval(2.0)
        )
        XCTAssertNil(s2.processConsumers.first { $0.primaryPID == 2 })
        let p1T2 = try XCTUnwrap(s2.processConsumers.first { $0.primaryPID == 1 }).powerW
        XCTAssertEqual(p1T2, expectedT2, accuracy: 0.0001)

        // T3 (+1.0s): PID 1 remains at 0.0 W -> continues converging toward 0; PID 2 reappears (pruned earlier -> baseline only)
        let expectedT3 = expectedT2 + alpha * (0.0 - expectedT2)
        let s3 = aggregator.ingest(
            samples: [
                sample(pid: 1, start: 1, energyNJ: 10_000_000_000),
                sample(pid: 2, start: 2, energyNJ: 5_000_000_000),
            ],
            at: baseDate.addingTimeInterval(3.0)
        )
        let p1T3 = try XCTUnwrap(s3.processConsumers.first { $0.primaryPID == 1 }).powerW
        XCTAssertEqual(p1T3, expectedT3, accuracy: 0.0001)
        XCTAssertLessThan(p1T3, p1T2)
        XCTAssertNil(s3.processConsumers.first { $0.primaryPID == 2 })
    }

    // MARK: - 5. .byApp Grouping vs .byProcess

    func testByAppGroupingMergesHelpersAndCLIWorkersWhileByProcessKeepsIndividualPIDs() throws {
        let aggregator = ProcessEnergyAggregator()
        let t0 = baseDate
        let t1 = baseDate.addingTimeInterval(1.0)

        let baseline: [RawProcessEnergySample] = [
            RawProcessEnergySample(
                pid: 10,
                ppid: 1,
                startAbsTime: 1,
                processName: "Safari",
                executablePath: "/Applications/Safari.app/Contents/MacOS/Safari",
                appBundlePath: "/Applications/Safari.app",
                appDisplayName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                energyNJ: 0,
                cpuTimeNS: 0,
                idleWakeups: 0,
                diskReadBytes: 0,
                diskWriteBytes: 0,
                physFootprintBytes: 100_000_000,
                sleepAssertionTypes: []
            ),
            RawProcessEnergySample(
                pid: 11,
                ppid: 10,
                startAbsTime: 2,
                processName: "com.apple.WebKit.WebContent",
                executablePath: "/Applications/Safari.app/Contents/XPCServices/WebContent.xpc/Contents/MacOS/WebContent",
                appBundlePath: "/Applications/Safari.app",
                appDisplayName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                energyNJ: 0,
                cpuTimeNS: 0,
                idleWakeups: 0,
                diskReadBytes: 0,
                diskWriteBytes: 0,
                physFootprintBytes: 300_000_000,
                sleepAssertionTypes: ["PreventUserIdleDisplaySleep"]
            ),
            RawProcessEnergySample(
                pid: 20,
                ppid: 1,
                startAbsTime: 3,
                processName: "clang",
                executablePath: "/usr/bin/clang",
                energyNJ: 0,
                cpuTimeNS: 0,
                physFootprintBytes: 50_000_000
            ),
            RawProcessEnergySample(
                pid: 21,
                ppid: 1,
                startAbsTime: 4,
                processName: "clang",
                executablePath: "/usr/bin/clang",
                energyNJ: 0,
                cpuTimeNS: 0,
                physFootprintBytes: 70_000_000
            ),
        ]

        let next: [RawProcessEnergySample] = [
            RawProcessEnergySample(
                pid: 10,
                ppid: 1,
                startAbsTime: 1,
                processName: "Safari",
                executablePath: "/Applications/Safari.app/Contents/MacOS/Safari",
                appBundlePath: "/Applications/Safari.app",
                appDisplayName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                energyNJ: 1_000_000_000, // 1.0 W
                cpuTimeNS: 100_000_000,  // 10%
                idleWakeups: 20,
                diskReadBytes: 10_000,
                diskWriteBytes: 5_000,
                physFootprintBytes: 100_000_000,
                sleepAssertionTypes: ["PreventUserIdleSystemSleep"]
            ),
            RawProcessEnergySample(
                pid: 11,
                ppid: 10,
                startAbsTime: 2,
                processName: "com.apple.WebKit.WebContent",
                executablePath: "/Applications/Safari.app/Contents/XPCServices/WebContent.xpc/Contents/MacOS/WebContent",
                appBundlePath: "/Applications/Safari.app",
                appDisplayName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                energyNJ: 3_000_000_000, // 3.0 W (higher than main process!)
                cpuTimeNS: 300_000_000,  // 30%
                idleWakeups: 50,
                diskReadBytes: 20_000,
                diskWriteBytes: 5_000,
                physFootprintBytes: 300_000_000,
                sleepAssertionTypes: ["PreventUserIdleDisplaySleep"]
            ),
            RawProcessEnergySample(
                pid: 20,
                ppid: 1,
                startAbsTime: 3,
                processName: "clang",
                executablePath: "/usr/bin/clang",
                energyNJ: 1_500_000_000, // 1.5 W
                cpuTimeNS: 400_000_000,
                physFootprintBytes: 50_000_000
            ),
            RawProcessEnergySample(
                pid: 21,
                ppid: 1,
                startAbsTime: 4,
                processName: "clang",
                executablePath: "/usr/bin/clang",
                energyNJ: 500_000_000, // 0.5 W
                cpuTimeNS: 200_000_000,
                physFootprintBytes: 70_000_000
            ),
        ]

        _ = aggregator.ingest(samples: baseline, at: t0)
        let snap = aggregator.ingest(samples: next, at: t1)

        XCTAssertEqual(snap.appConsumers.count, 2)
        XCTAssertEqual(snap.processConsumers.count, 4)

        let safari = try XCTUnwrap(snap.consumers(for: .byApp, limit: .top5).first)
        XCTAssertEqual(safari.displayName, "Safari")
        XCTAssertEqual(safari.processCount, 2)
        XCTAssertEqual(safari.primaryPID, 11) // highest-power child first
        XCTAssertEqual(safari.processes.map(\.pid), [11, 10])
        XCTAssertEqual(safari.powerW, 4.0, accuracy: 0.0001)
        XCTAssertEqual(safari.cpuPercent, 40.0, accuracy: 0.0001)
        XCTAssertEqual(safari.wakeupsPerSecond, 70.0, accuracy: 0.0001)
        XCTAssertEqual(safari.diskBytesPerSecond, 40_000.0, accuracy: 0.0001)
        XCTAssertEqual(safari.memoryBytes, 400_000_000)
        XCTAssertTrue(safari.isPreventingSleep)
        XCTAssertEqual(
            safari.sleepAssertionTypes,
            ["PreventUserIdleDisplaySleep", "PreventUserIdleSystemSleep"]
        )

        let clang = try XCTUnwrap(snap.appConsumers.last)
        XCTAssertEqual(clang.id, "bin:/usr/bin/clang")
        XCTAssertEqual(clang.processCount, 2)
        XCTAssertEqual(clang.powerW, 2.0, accuracy: 0.0001)
        XCTAssertEqual(clang.memoryBytes, 120_000_000)

        XCTAssertEqual(snap.consumers(for: .byProcess, limit: .top3).count, 3)
        XCTAssertEqual(snap.consumers(for: .byProcess, limit: .top5).count, 4)
        XCTAssertEqual(snap.consumers(for: .byProcess, limit: 0), [])
    }

    // MARK: - 6. HardwareEnergyBreakdown

    func testHardwareEnergyBreakdownAcrossModesAndMissingSensors() {
        XCTAssertFalse(HardwareEnergyBreakdown.from(snapshot: .empty).isAvailable)

        // AC + Outbound + Display + SoC + Other (>= 0.05 W residual)
        let fullSnap = PowerSnapshot(
            isDataAvailable: true,
            telemetrySource: .smcAndIOKit,
            connectionPhase: .onAC,
            flowMode: .adapterBypass,
            totalSystemLoadW: 25.0,
            netSystemLoadW: 20.0,
            totalOutboundPowerW: 5.0,
            systemBreakdown: SystemPowerBreakdown(
                packagePowerW: 12.0,
                displayPowerW: 4.0,
                otherSystemW: 4.0
            )
        )
        let full = HardwareEnergyBreakdown.from(snapshot: fullSnap)
        XCTAssertTrue(full.isAvailable)
        XCTAssertEqual(full.totalWatts, 25.0, accuracy: 0.001)
        XCTAssertEqual(full.segments.map(\.kind), [.soc, .display, .outbound, .other])
        XCTAssertEqual(full.segments.reduce(0.0) { $0 + $1.share }, 1.0, accuracy: 0.0001)
        XCTAssertTrue(full.segments.allSatisfy { $0.share.isFinite && $0.share >= 0 && $0.watts >= 0 })

        // Battery-only with tiny residual (< 0.05 W) -> .other omitted
        let batterySnap = PowerSnapshot(
            isDataAvailable: true,
            telemetrySource: .smcAndIOKit,
            connectionPhase: .onBattery,
            flowMode: .batteryOnly,
            totalSystemLoadW: 10.02,
            netSystemLoadW: 10.02,
            totalOutboundPowerW: 0,
            systemBreakdown: SystemPowerBreakdown(
                packagePowerW: 7.0,
                displayPowerW: 3.0,
                otherSystemW: 0.02
            )
        )
        let battery = HardwareEnergyBreakdown.from(snapshot: batterySnap)
        XCTAssertEqual(battery.segments.map(\.kind), [.soc, .display])
        XCTAssertEqual(battery.segments.reduce(0.0) { $0 + $1.share }, 1.0, accuracy: 0.0001)

        // Missing SMC sensors (systemBreakdown == nil) with netSystemLoadW + outbound only
        let missingSMCSnap = PowerSnapshot(
            isDataAvailable: true,
            telemetrySource: .iokitTelemetry,
            connectionPhase: .onBattery,
            flowMode: .batteryOnly,
            totalSystemLoadW: 0,
            netSystemLoadW: 12.0,
            totalOutboundPowerW: 3.0,
            systemBreakdown: nil
        )
        let missingSMC = HardwareEnergyBreakdown.from(snapshot: missingSMCSnap)
        XCTAssertTrue(missingSMC.isAvailable)
        XCTAssertEqual(missingSMC.segments.map(\.kind), [.outbound, .other])
        XCTAssertEqual(missingSMC.segments.reduce(0.0) { $0 + $1.share }, 1.0, accuracy: 0.0001)

        // Non-finite / negative values must not produce NaN or negative shares
        let corruptSnap = PowerSnapshot(
            isDataAvailable: true,
            telemetrySource: .smcAndIOKit,
            connectionPhase: .onBattery,
            flowMode: .batteryOnly,
            totalSystemLoadW: .nan,
            netSystemLoadW: -.infinity,
            totalOutboundPowerW: -2.0,
            systemBreakdown: SystemPowerBreakdown(
                packagePowerW: .nan,
                displayPowerW: -1.0,
                otherSystemW: .infinity
            )
        )
        let corrupt = HardwareEnergyBreakdown.from(snapshot: corruptSnap)
        XCTAssertFalse(corrupt.isAvailable)
        XCTAssertEqual(corrupt, .empty)
    }

    // MARK: - 7. PowerFormatters & PowerSettings Backward-Compatible JSON

    func testEnergyDashboardFormatters() {
        XCTAssertEqual(PowerFormatters.adaptiveWatts(0), "0 W")
        XCTAssertEqual(PowerFormatters.adaptiveWatts(0.0004), "0 W")
        XCTAssertEqual(PowerFormatters.adaptiveWatts(0.25), "250 mW")
        XCTAssertEqual(PowerFormatters.adaptiveWatts(2.346), "2.35 W")
        XCTAssertEqual(PowerFormatters.adaptiveWatts(12.34), "12.3 W")
        XCTAssertEqual(PowerFormatters.adaptiveWatts(-0.5), "—")
        XCTAssertEqual(PowerFormatters.adaptiveWatts(.nan), "—")
        XCTAssertEqual(PowerFormatters.adaptiveWatts(.infinity), "—")

        XCTAssertEqual(PowerFormatters.cpuPercent(0.02), "0%")
        XCTAssertEqual(PowerFormatters.cpuPercent(4.56), "4.6%")
        XCTAssertEqual(PowerFormatters.cpuPercent(142.4), "142%")
        XCTAssertEqual(PowerFormatters.cpuPercent(-1), "—")
        XCTAssertEqual(PowerFormatters.cpuPercent(.nan), "—")

        XCTAssertEqual(PowerFormatters.energyImpact(0.01), "0")
        XCTAssertEqual(PowerFormatters.energyImpact(12.34), "12.3")
        XCTAssertEqual(PowerFormatters.energyImpact(1234.6), "1,235")
        XCTAssertEqual(PowerFormatters.energyImpact(-1), "—")

        XCTAssertEqual(PowerFormatters.wakeupsPerSecond(0.2), "0/s")
        XCTAssertEqual(PowerFormatters.wakeupsPerSecond(42.3), "42/s")
        XCTAssertEqual(PowerFormatters.wakeupsPerSecond(1_500), "1.5k/s")
        XCTAssertEqual(PowerFormatters.wakeupsPerSecond(150_000), "150k/s")
        XCTAssertEqual(PowerFormatters.wakeupsPerSecond(2_500_000), "2.5M/s")
        XCTAssertEqual(PowerFormatters.wakeupsPerSecond(-1), "—")

        XCTAssertEqual(PowerFormatters.byteRate(0.1), "0 B/s")
        XCTAssertEqual(PowerFormatters.byteRate(512), "512 B/s")
        XCTAssertEqual(PowerFormatters.byteRate(2_048), "2.0 KB/s")
        XCTAssertEqual(PowerFormatters.byteRate(5 * 1024 * 1024), "5.0 MB/s")
        XCTAssertEqual(PowerFormatters.byteRate(-1), "—")

        XCTAssertEqual(PowerFormatters.memoryBytes(0), "0 B")
        XCTAssertEqual(PowerFormatters.memoryBytes(512), "512 B")
        XCTAssertEqual(PowerFormatters.memoryBytes(1_536), "1.5 KB")
        XCTAssertEqual(PowerFormatters.memoryBytes(2 * 1024 * 1024 * 1024), "2.0 GB")
    }

    func testPowerSettingsBackwardCompatibleJSONDecode() throws {
        let legacyJSON = """
        {
          "menuBarDisplayMode": "iconAndWatts",
          "batteryIconStyle": "minimal",
          "liveRefreshInterval": 2.0,
          "temperatureUnit": "fahrenheit",
          "maskSerialNumbers": true,
          "appLanguage": "simplifiedChinese"
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(PowerSettings.self, from: data)
        XCTAssertEqual(decoded.menuBarDisplayMode, .iconAndWatts)
        XCTAssertEqual(decoded.temperatureUnit, .fahrenheit)
        XCTAssertTrue(decoded.maskSerialNumbers)
        XCTAssertTrue(decoded.showEnergyDashboard)
        XCTAssertEqual(decoded.energyDashboardLimit, .top5)

        var custom = decoded
        custom.showEnergyDashboard = false
        custom.energyDashboardLimit = .top8
        let encoded = try JSONEncoder().encode(custom)
        let roundTripped = try JSONDecoder().decode(PowerSettings.self, from: encoded)
        XCTAssertFalse(roundTripped.showEnergyDashboard)
        XCTAssertEqual(roundTripped.energyDashboardLimit, .top8)
    }

    // MARK: - 8. PowerMonitor Zero-Polling & Lifecycle Invariants

    @MainActor
    func testPowerMonitorZeroPollingInDormantAndSummaryModesAndWarmupOnPopoverOpen() {
        let defaults = InMemoryUserDefaults()
        let store = PowerSettingsStore(
            userDefaults: defaults,
            storageKey: "test.energy.monitor.1",
            manageLaunchAtLogin: false
        )
        let mockBattery = MockSmartBatteryReader(
            reading: makeReading(isExternalConnected: false, instantAmperageMA: -1_200)
        )
        let mockPorts = MockIOPortReader(entries: [])
        let mockSMC = SMCReader(keyReader: SilentSMCKeyReader())
        let mockNotifier = MockPowerEventNotifier()

        let t0Samples = [
            RawProcessEnergySample(
                pid: 501,
                startAbsTime: 100,
                processName: "RenderApp",
                executablePath: "/Applications/RenderApp.app/Contents/MacOS/RenderApp",
                appBundlePath: "/Applications/RenderApp.app",
                appDisplayName: "RenderApp",
                energyNJ: 1_000_000_000,
                cpuTimeNS: 100_000_000
            )
        ]
        let t1Samples = [
            RawProcessEnergySample(
                pid: 501,
                startAbsTime: 100,
                processName: "RenderApp",
                executablePath: "/Applications/RenderApp.app/Contents/MacOS/RenderApp",
                appBundlePath: "/Applications/RenderApp.app",
                appDisplayName: "RenderApp",
                energyNJ: 2_500_000_000,
                cpuTimeNS: 300_000_000
            )
        ]
        let mockProcessReader = MockProcessEnergyReader(
            queuedResponses: [t0Samples, t1Samples],
            fallback: t1Samples
        )

        let monitor = PowerMonitor(
            settingsStore: store,
            smartBatteryReader: mockBattery,
            ioPortReader: mockPorts,
            smcReader: mockSMC,
            notifier: mockNotifier,
            resolver: makeIsolatedResolver(),
            isDisplayAsleepProvider: { false },
            processEnergyReader: mockProcessReader
        )
        defer { monitor.stop() }

        monitor.start()

        // Dormant mode: never scans processes
        let dormantExp = expectation(description: "dormant startup settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { dormantExp.fulfill() }
        wait(for: [dormantExp], timeout: 1.0)
        XCTAssertEqual(monitor.activePollingTier, .dormant)
        XCTAssertEqual(mockProcessReader.readCount, 0)
        XCTAssertEqual(monitor.energySnapshot, .empty)

        // Summary mode (.iconAndWatts with popover hidden): still never scans processes
        store.settings.menuBarDisplayMode = .iconAndWatts
        let summaryExp = expectation(description: "summary mode settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { summaryExp.fulfill() }
        wait(for: [summaryExp], timeout: 1.0)
        XCTAssertEqual(monitor.activePollingTier, .summary(interval: 3.0))
        XCTAssertEqual(mockProcessReader.readCount, 0)
        XCTAssertEqual(monitor.energySnapshot, .empty)

        // Opening popover with showEnergyDashboard=true triggers baseline + 350ms warm-up -> .ready
        monitor.setPopoverVisible(true)
        let warmupExp = expectation(description: "energy dashboard reaches ready after warmup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { warmupExp.fulfill() }
        wait(for: [warmupExp], timeout: 2.0)

        XCTAssertGreaterThanOrEqual(mockProcessReader.readCount, 2)
        XCTAssertEqual(monitor.energySnapshot.phase, .ready)
        XCTAssertFalse(monitor.energySnapshot.appConsumers.isEmpty)

        // Closing popover resets energySnapshot to .empty and stops process scanning
        monitor.setPopoverVisible(false)
        XCTAssertEqual(monitor.energySnapshot, .empty)
        let countAfterClose = mockProcessReader.readCount
        let afterCloseExp = expectation(description: "no process scans after popover close")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { afterCloseExp.fulfill() }
        wait(for: [afterCloseExp], timeout: 1.5)
        XCTAssertEqual(mockProcessReader.readCount, countAfterClose)
    }

    @MainActor
    func testPowerMonitorSuppressesProcessScanningWhenDashboardDisabledOrScreenAsleep() {
        let defaults = InMemoryUserDefaults()
        let store = PowerSettingsStore(
            userDefaults: defaults,
            storageKey: "test.energy.monitor.2",
            manageLaunchAtLogin: false
        )
        store.settings.showEnergyDashboard = false

        let mockBattery = MockSmartBatteryReader(
            reading: makeReading(isExternalConnected: false, instantAmperageMA: -1_000)
        )
        let mockPorts = MockIOPortReader(entries: [])
        let mockSMC = SMCReader(keyReader: SilentSMCKeyReader())
        let mockNotifier = MockPowerEventNotifier()
        let mockProcessReader = MockProcessEnergyReader(samples: [
            RawProcessEnergySample(
                pid: 601,
                startAbsTime: 10,
                processName: "App",
                executablePath: "/Applications/App.app/Contents/MacOS/App",
                appBundlePath: "/Applications/App.app",
                energyNJ: 1_000_000_000
            )
        ])

        let monitor = PowerMonitor(
            settingsStore: store,
            smartBatteryReader: mockBattery,
            ioPortReader: mockPorts,
            smcReader: mockSMC,
            notifier: mockNotifier,
            resolver: makeIsolatedResolver(),
            isDisplayAsleepProvider: { false },
            processEnergyReader: mockProcessReader
        )
        defer { monitor.stop() }

        monitor.start()
        monitor.setPopoverVisible(true)

        let disabledExp = expectation(description: "popover open with dashboard disabled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { disabledExp.fulfill() }
        wait(for: [disabledExp], timeout: 1.5)

        XCTAssertEqual(mockProcessReader.readCount, 0)
        XCTAssertEqual(monitor.energySnapshot, .empty)

        // Enable dashboard while popover is visible -> starts scanning and reaches .ready
        store.settings.showEnergyDashboard = true
        let enabledExp = expectation(description: "dashboard enabled while popover visible")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { enabledExp.fulfill() }
        wait(for: [enabledExp], timeout: 2.0)

        XCTAssertGreaterThanOrEqual(mockProcessReader.readCount, 2)
        XCTAssertEqual(monitor.energySnapshot.phase, .ready)

        // Screen sleep while popover visible resets energySnapshot to .empty and stops scanning
        mockNotifier.emit(.screensDidSleep)
        let sleepExp = expectation(description: "screen sleep processed")
        DispatchQueue.main.async { sleepExp.fulfill() }
        wait(for: [sleepExp], timeout: 1.0)

        XCTAssertEqual(monitor.energySnapshot, .empty)
        let countAtSleep = mockProcessReader.readCount
        let postSleepExp = expectation(description: "no process scans during screen sleep")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { postSleepExp.fulfill() }
        wait(for: [postSleepExp], timeout: 1.5)
        XCTAssertEqual(mockProcessReader.readCount, countAtSleep)
    }

    @MainActor
    func testPowerMonitorSuppressesProcessScansOnNonEnergyTabs() {
        let store = PowerSettingsStore(userDefaults: nil, manageLaunchAtLogin: false)
        store.settings = PowerSettings(
            menuBarDisplayMode: .iconOnly,
            liveRefreshInterval: .standard,
            showEnergyDashboard: true
        )

        let mockBattery = MockSmartBatteryReader(
            reading: makeReading(isExternalConnected: false, instantAmperageMA: -1_000)
        )
        let mockPorts = MockIOPortReader(entries: [])
        let mockSMC = SMCReader(keyReader: SilentSMCKeyReader())
        let mockNotifier = MockPowerEventNotifier()
        let mockProcessReader = MockProcessEnergyReader(samples: [
            RawProcessEnergySample(
                pid: 701,
                startAbsTime: 10,
                processName: "App",
                executablePath: "/Applications/App.app/Contents/MacOS/App",
                appBundlePath: "/Applications/App.app",
                energyNJ: 1_000_000_000
            )
        ])

        let monitor = PowerMonitor(
            settingsStore: store,
            smartBatteryReader: mockBattery,
            ioPortReader: mockPorts,
            smcReader: mockSMC,
            notifier: mockNotifier,
            resolver: makeIsolatedResolver(),
            isDisplayAsleepProvider: { false },
            processEnergyReader: mockProcessReader
        )
        defer { monitor.stop() }

        monitor.start()
        monitor.setEnergyTabVisible(false)
        monitor.setPopoverVisible(true)

        let nonEnergyExp = expectation(description: "popover open on battery tab performs zero process scans")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { nonEnergyExp.fulfill() }
        wait(for: [nonEnergyExp], timeout: 1.5)

        XCTAssertEqual(mockProcessReader.readCount, 0)
        XCTAssertEqual(monitor.energySnapshot, .empty)

        // Switching to the Energy tab starts baseline + warm-up immediately
        monitor.setEnergyTabVisible(true)
        let energyTabExp = expectation(description: "energy tab reaches ready state")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { energyTabExp.fulfill() }
        wait(for: [energyTabExp], timeout: 2.0)

        XCTAssertGreaterThanOrEqual(mockProcessReader.readCount, 2)
        XCTAssertEqual(monitor.energySnapshot.phase, .ready)

        // Switching away immediately resets snapshot and stops scanning
        monitor.setEnergyTabVisible(false)
        XCTAssertEqual(monitor.energySnapshot, .empty)
        let countAfterLeave = mockProcessReader.readCount
        let afterLeaveExp = expectation(description: "no further scans after leaving energy tab")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { afterLeaveExp.fulfill() }
        wait(for: [afterLeaveExp], timeout: 1.5)
        XCTAssertEqual(mockProcessReader.readCount, countAfterLeave)
    }
}
