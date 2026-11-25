import Foundation

/// Computes differential per-process power, CPU, P-core share, wakeup rate, disk rate,
/// and Activity Monitor-style Energy Impact with time-aware EMA smoothing and app grouping.
final class ProcessEnergyAggregator: @unchecked Sendable {
    static let minimumSampleWindowSeconds: TimeInterval = 0.1
    private static let maximumSmoothingWindowSeconds: TimeInterval = 10.0
    /// Fallback power estimate per 100% single-core CPU when `ri_energy_nj` is unavailable (e.g. Intel Macs).
    private static let cpuFallbackWattsPerCore: Double = 2.5

    private struct ProcessKey: Hashable, Sendable {
        let pid: Int32
        let startAbsTime: UInt64
    }

    private struct CounterBaseline: Sendable {
        let energyNJ: UInt64
        let pCoreEnergyNJ: UInt64
        let billedEnergyNJ: UInt64
        let cpuTimeNS: UInt64
        let pCoreTimeNS: UInt64
        let idleWakeups: UInt64
        let diskReadBytes: UInt64
        let diskWriteBytes: UInt64

        init(sample: RawProcessEnergySample) {
            self.energyNJ = sample.energyNJ
            self.pCoreEnergyNJ = sample.pCoreEnergyNJ
            self.billedEnergyNJ = sample.billedEnergyNJ
            self.cpuTimeNS = sample.cpuTimeNS
            self.pCoreTimeNS = sample.pCoreTimeNS
            self.idleWakeups = sample.idleWakeups
            self.diskReadBytes = sample.diskReadBytes
            self.diskWriteBytes = sample.diskWriteBytes
        }
    }

    private struct SmoothedMetrics: Sendable {
        let directPowerW: Double
        let billedPowerW: Double
        let pCoreShare: Double?
        let cpuPercent: Double
        let wakeupsPerSecond: Double
        let diskBytesPerSecond: Double

        var powerW: Double {
            directPowerW + billedPowerW
        }

        var energyImpact: Double {
            cpuPercent
                + 0.1 * wakeupsPerSecond
                + 0.002 * (diskBytesPerSecond / 1024.0)
                + 20.0 * billedPowerW
        }
    }

    private struct AppGroupAccumulator {
        let id: String
        var displayName: String?
        var iconPath: String?
        var bundleIdentifier: String?
        var appBundlePath: String?
        var processes: [ProcessEnergyMetrics] = []
    }

    private let lock = NSLock()
    private let smoothingTau: TimeInterval

    private var lastTimestamp: Date?
    private var previousBaselines: [ProcessKey: CounterBaseline] = [:]
    private var smoothedStates: [ProcessKey: SmoothedMetrics] = [:]
    private var lastReadySnapshot: EnergySnapshot?

    init(smoothingTau: TimeInterval = 2.5) {
        self.smoothingTau = max(smoothingTau, 0.05)
    }

    func reset() {
        lock.lock()
        lastTimestamp = nil
        previousBaselines.removeAll(keepingCapacity: false)
        smoothedStates.removeAll(keepingCapacity: false)
        lastReadySnapshot = nil
        lock.unlock()
    }

    func ingest(samples: [RawProcessEnergySample], at timestamp: Date) -> EnergySnapshot {
        lock.lock()
        defer { lock.unlock() }

        guard let previousTimestamp = lastTimestamp else {
            storeBaseline(samples: samples, at: timestamp)
            return EnergySnapshot(
                timestamp: timestamp,
                phase: .warmingUp,
                windowSeconds: 0,
                sampledProcessCount: samples.count,
                totalMeasuredPowerW: 0,
                appConsumers: [],
                processConsumers: []
            )
        }

        let dt = timestamp.timeIntervalSince(previousTimestamp)
        if !dt.isFinite || dt < 0 {
            // Clock stepped backwards; establish a fresh baseline without bogus deltas.
            storeBaseline(samples: samples, at: timestamp)
            return EnergySnapshot(
                timestamp: timestamp,
                phase: .warmingUp,
                windowSeconds: 0,
                sampledProcessCount: samples.count,
                totalMeasuredPowerW: 0,
                appConsumers: [],
                processConsumers: []
            )
        }

        if dt < Self.minimumSampleWindowSeconds {
            if let existing = lastReadySnapshot {
                return existing
            }
            return EnergySnapshot(
                timestamp: timestamp,
                phase: .warmingUp,
                windowSeconds: dt,
                sampledProcessCount: samples.count,
                totalMeasuredPowerW: 0,
                appConsumers: [],
                processConsumers: []
            )
        }

        let alpha = 1.0 - exp(-min(dt, Self.maximumSmoothingWindowSeconds) / smoothingTau)
        let useCPUFallback = !samples.isEmpty
            && samples.allSatisfy { $0.energyNJ == 0 && $0.billedEnergyNJ == 0 }

        var nextBaselines: [ProcessKey: CounterBaseline] = [:]
        nextBaselines.reserveCapacity(samples.count)

        var nextSmoothed: [ProcessKey: SmoothedMetrics] = [:]
        nextSmoothed.reserveCapacity(samples.count)

        var measuredRecords: [(sample: RawProcessEnergySample, metrics: ProcessEnergyMetrics)] = []
        measuredRecords.reserveCapacity(samples.count)

        var totalMeasuredPowerW: Double = 0

        for sample in samples {
            let key = ProcessKey(pid: sample.pid, startAbsTime: sample.startAbsTime)
            nextBaselines[key] = CounterBaseline(sample: sample)

            guard let previous = previousBaselines[key] else {
                // Newly spawned process or reused PID with a different startAbsTime:
                // establish baseline first to prevent startup/PID-reuse spikes.
                continue
            }

            let deltaEnergyNJ = Self.safeDelta(current: sample.energyNJ, previous: previous.energyNJ)
            let deltaPCoreEnergyNJ = Self.safeDelta(current: sample.pCoreEnergyNJ, previous: previous.pCoreEnergyNJ)
            let deltaBilledNJ = Self.safeDelta(current: sample.billedEnergyNJ, previous: previous.billedEnergyNJ)
            let deltaCPUTimeNS = Self.safeDelta(current: sample.cpuTimeNS, previous: previous.cpuTimeNS)
            let deltaPCoreTimeNS = Self.safeDelta(current: sample.pCoreTimeNS, previous: previous.pCoreTimeNS)
            let deltaWakeups = Self.safeDelta(current: sample.idleWakeups, previous: previous.idleWakeups)
            let deltaDiskRead = Self.safeDelta(current: sample.diskReadBytes, previous: previous.diskReadBytes)
            let deltaDiskWrite = Self.safeDelta(current: sample.diskWriteBytes, previous: previous.diskWriteBytes)
            let deltaDiskBytes = Self.saturatingAdd(deltaDiskRead, deltaDiskWrite)

            let rawCPUPercent = Self.sanitizedNonNegative((Double(deltaCPUTimeNS) / 1e9 / dt) * 100.0)
            let rawWakeupsPerSec = Self.sanitizedNonNegative(Double(deltaWakeups) / dt)
            let rawDiskBytesPerSec = Self.sanitizedNonNegative(Double(deltaDiskBytes) / dt)

            let rawDirectPowerW: Double
            let rawBilledPowerW: Double
            if useCPUFallback {
                rawDirectPowerW = Self.sanitizedNonNegative((rawCPUPercent / 100.0) * Self.cpuFallbackWattsPerCore)
                rawBilledPowerW = 0
            } else {
                rawDirectPowerW = Self.sanitizedNonNegative(Double(deltaEnergyNJ) / 1e9 / dt)
                rawBilledPowerW = Self.sanitizedNonNegative(Double(deltaBilledNJ) / 1e9 / dt)
            }

            let rawPCoreShare: Double?
            if deltaEnergyNJ > 0 {
                rawPCoreShare = Self.clampedUnitInterval(Double(deltaPCoreEnergyNJ) / Double(deltaEnergyNJ))
            } else if deltaCPUTimeNS > 0 {
                rawPCoreShare = Self.clampedUnitInterval(Double(deltaPCoreTimeNS) / Double(deltaCPUTimeNS))
            } else {
                rawPCoreShare = nil
            }

            let smoothed: SmoothedMetrics
            if let prevSmoothed = smoothedStates[key] {
                let blendedPCoreShare: Double?
                switch (prevSmoothed.pCoreShare, rawPCoreShare) {
                case let (prevShare?, currShare?):
                    blendedPCoreShare = Self.clampedUnitInterval(Self.ema(prevShare, currShare, alpha: alpha))
                case let (nil, currShare?):
                    blendedPCoreShare = currShare
                case let (prevShare?, nil):
                    blendedPCoreShare = prevShare
                case (nil, nil):
                    blendedPCoreShare = nil
                }

                smoothed = SmoothedMetrics(
                    directPowerW: Self.sanitizedNonNegative(Self.ema(prevSmoothed.directPowerW, rawDirectPowerW, alpha: alpha)),
                    billedPowerW: Self.sanitizedNonNegative(Self.ema(prevSmoothed.billedPowerW, rawBilledPowerW, alpha: alpha)),
                    pCoreShare: blendedPCoreShare,
                    cpuPercent: Self.sanitizedNonNegative(Self.ema(prevSmoothed.cpuPercent, rawCPUPercent, alpha: alpha)),
                    wakeupsPerSecond: Self.sanitizedNonNegative(Self.ema(prevSmoothed.wakeupsPerSecond, rawWakeupsPerSec, alpha: alpha)),
                    diskBytesPerSecond: Self.sanitizedNonNegative(Self.ema(prevSmoothed.diskBytesPerSecond, rawDiskBytesPerSec, alpha: alpha))
                )
            } else {
                // First delta initializes EMA directly with no artificial ramp-up lag.
                smoothed = SmoothedMetrics(
                    directPowerW: rawDirectPowerW,
                    billedPowerW: rawBilledPowerW,
                    pCoreShare: rawPCoreShare,
                    cpuPercent: rawCPUPercent,
                    wakeupsPerSecond: rawWakeupsPerSec,
                    diskBytesPerSecond: rawDiskBytesPerSec
                )
            }

            nextSmoothed[key] = smoothed

            let normalizedAssertions = Self.normalizedAssertions(sample.sleepAssertionTypes)
            let isPreventingSleep = !normalizedAssertions.isEmpty
            let displayProcessName = Self.resolvedProcessName(for: sample)

            let processMetrics = ProcessEnergyMetrics(
                id: sample.pid,
                pid: sample.pid,
                name: displayProcessName,
                executablePath: sample.executablePath,
                appBundlePath: sample.appBundlePath,
                powerW: smoothed.powerW,
                directPowerW: smoothed.directPowerW,
                billedPowerW: smoothed.billedPowerW,
                pCoreShare: smoothed.pCoreShare,
                energyImpact: smoothed.energyImpact,
                cpuPercent: smoothed.cpuPercent,
                wakeupsPerSecond: smoothed.wakeupsPerSecond,
                diskBytesPerSecond: smoothed.diskBytesPerSecond,
                memoryBytes: sample.physFootprintBytes,
                isPreventingSleep: isPreventingSleep,
                sleepAssertionTypes: normalizedAssertions
            )

            totalMeasuredPowerW += processMetrics.powerW
            measuredRecords.append((sample: sample, metrics: processMetrics))
        }

        // Prune exited processes by replacing state maps with only live keys from this tick.
        previousBaselines = nextBaselines
        smoothedStates = nextSmoothed
        lastTimestamp = timestamp

        let processConsumers = buildProcessConsumers(from: measuredRecords)
        let appConsumers = buildAppConsumers(from: measuredRecords)

        let snapshot = EnergySnapshot(
            timestamp: timestamp,
            phase: .ready,
            windowSeconds: dt,
            sampledProcessCount: samples.count,
            totalMeasuredPowerW: Self.sanitizedNonNegative(totalMeasuredPowerW),
            appConsumers: appConsumers,
            processConsumers: processConsumers
        )
        lastReadySnapshot = snapshot
        return snapshot
    }

    // MARK: - Grouping & Filtering

    private func buildProcessConsumers(
        from records: [(sample: RawProcessEnergySample, metrics: ProcessEnergyMetrics)]
    ) -> [EnergyConsumerItem] {
        var items: [EnergyConsumerItem] = []
        items.reserveCapacity(records.count)

        for record in records {
            let m = record.metrics
            guard Self.passesNoiseFilter(
                powerW: m.powerW,
                cpuPercent: m.cpuPercent,
                wakeupsPerSecond: m.wakeupsPerSecond,
                diskBytesPerSecond: m.diskBytesPerSecond,
                isPreventingSleep: m.isPreventingSleep
            ) else {
                continue
            }

            let iconPath = Self.nonEmpty(record.sample.appBundlePath) ?? Self.nonEmpty(record.sample.executablePath)
            items.append(
                EnergyConsumerItem(
                    id: "pid:\(m.pid)",
                    displayName: m.name,
                    iconPath: iconPath,
                    bundleIdentifier: Self.nonEmpty(record.sample.bundleIdentifier),
                    primaryPID: m.pid,
                    powerW: m.powerW,
                    directPowerW: m.directPowerW,
                    billedPowerW: m.billedPowerW,
                    pCoreShare: m.pCoreShare,
                    energyImpact: m.energyImpact,
                    cpuPercent: m.cpuPercent,
                    wakeupsPerSecond: m.wakeupsPerSecond,
                    diskBytesPerSecond: m.diskBytesPerSecond,
                    memoryBytes: m.memoryBytes,
                    isPreventingSleep: m.isPreventingSleep,
                    sleepAssertionTypes: m.sleepAssertionTypes,
                    processCount: 1,
                    processes: [m]
                )
            )
        }

        return items.sorted(by: Self.sortConsumers)
    }

    private func buildAppConsumers(
        from records: [(sample: RawProcessEnergySample, metrics: ProcessEnergyMetrics)]
    ) -> [EnergyConsumerItem] {
        var groups: [String: AppGroupAccumulator] = [:]
        groups.reserveCapacity(records.count)

        for record in records {
            let sample = record.sample
            let groupID = Self.appGroupID(for: sample)
            var group = groups[groupID] ?? AppGroupAccumulator(
                id: groupID,
                displayName: nil,
                iconPath: nil,
                bundleIdentifier: nil,
                appBundlePath: Self.nonEmpty(sample.appBundlePath)
            )

            if group.displayName == nil, let appDisplayName = Self.nonEmpty(sample.appDisplayName) {
                group.displayName = appDisplayName
            }
            if group.bundleIdentifier == nil, let bundleID = Self.nonEmpty(sample.bundleIdentifier) {
                group.bundleIdentifier = bundleID
            }
            if group.appBundlePath == nil, let bundlePath = Self.nonEmpty(sample.appBundlePath) {
                group.appBundlePath = bundlePath
            }
            if group.iconPath == nil {
                group.iconPath = Self.nonEmpty(sample.appBundlePath) ?? Self.nonEmpty(sample.executablePath)
            }
            group.processes.append(record.metrics)
            groups[groupID] = group
        }

        var items: [EnergyConsumerItem] = []
        items.reserveCapacity(groups.count)

        for group in groups.values {
            let sortedChildren = group.processes.sorted(by: Self.sortProcessMetrics)
            guard let primary = sortedChildren.first else { continue }

            var directPowerW: Double = 0
            var billedPowerW: Double = 0
            var cpuPercent: Double = 0
            var wakeupsPerSecond: Double = 0
            var diskBytesPerSecond: Double = 0
            var energyImpact: Double = 0
            var memoryBytes: UInt64 = 0
            var assertionSet = Set<String>()

            for child in sortedChildren {
                directPowerW += child.directPowerW
                billedPowerW += child.billedPowerW
                cpuPercent += child.cpuPercent
                wakeupsPerSecond += child.wakeupsPerSecond
                diskBytesPerSecond += child.diskBytesPerSecond
                energyImpact += child.energyImpact
                memoryBytes = Self.saturatingAdd(memoryBytes, child.memoryBytes)
                for assertion in child.sleepAssertionTypes {
                    assertionSet.insert(assertion)
                }
            }

            let totalPowerW = Self.sanitizedNonNegative(directPowerW + billedPowerW)
            let sleepAssertions = assertionSet.sorted()
            let isPreventingSleep = !sleepAssertions.isEmpty

            guard Self.passesNoiseFilter(
                powerW: totalPowerW,
                cpuPercent: cpuPercent,
                wakeupsPerSecond: wakeupsPerSecond,
                diskBytesPerSecond: diskBytesPerSecond,
                isPreventingSleep: isPreventingSleep
            ) else {
                continue
            }

            let displayName = group.displayName
                ?? group.appBundlePath.flatMap { path -> String? in
                    let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                    return Self.nonEmpty(stem)
                }
                ?? primary.name

            items.append(
                EnergyConsumerItem(
                    id: group.id,
                    displayName: displayName,
                    iconPath: group.iconPath,
                    bundleIdentifier: group.bundleIdentifier,
                    primaryPID: primary.pid,
                    powerW: totalPowerW,
                    directPowerW: Self.sanitizedNonNegative(directPowerW),
                    billedPowerW: Self.sanitizedNonNegative(billedPowerW),
                    pCoreShare: Self.aggregatePCoreShare(for: sortedChildren),
                    energyImpact: Self.sanitizedNonNegative(energyImpact),
                    cpuPercent: Self.sanitizedNonNegative(cpuPercent),
                    wakeupsPerSecond: Self.sanitizedNonNegative(wakeupsPerSecond),
                    diskBytesPerSecond: Self.sanitizedNonNegative(diskBytesPerSecond),
                    memoryBytes: memoryBytes,
                    isPreventingSleep: isPreventingSleep,
                    sleepAssertionTypes: sleepAssertions,
                    processCount: sortedChildren.count,
                    processes: sortedChildren
                )
            )
        }

        return items.sorted(by: Self.sortConsumers)
    }

    // MARK: - Private Math & Helpers

    private func storeBaseline(samples: [RawProcessEnergySample], at timestamp: Date) {
        var baselines: [ProcessKey: CounterBaseline] = [:]
        baselines.reserveCapacity(samples.count)
        for sample in samples {
            let key = ProcessKey(pid: sample.pid, startAbsTime: sample.startAbsTime)
            baselines[key] = CounterBaseline(sample: sample)
        }
        previousBaselines = baselines
        smoothedStates.removeAll(keepingCapacity: false)
        lastTimestamp = timestamp
        lastReadySnapshot = nil
    }

    private static func appGroupID(for sample: RawProcessEnergySample) -> String {
        if let bundlePath = nonEmpty(sample.appBundlePath) {
            return "app:\(bundlePath)"
        }
        if let execPath = nonEmpty(sample.executablePath) {
            return "bin:\(execPath)"
        }
        return "proc:\(resolvedProcessName(for: sample))"
    }

    private static func resolvedProcessName(for sample: RawProcessEnergySample) -> String {
        if let name = nonEmpty(sample.processName) {
            return name
        }
        if let execPath = nonEmpty(sample.executablePath) {
            let last = (execPath as NSString).lastPathComponent
            if let clean = nonEmpty(last) {
                return clean
            }
        }
        return "pid:\(sample.pid)"
    }

    private static func aggregatePCoreShare(for children: [ProcessEnergyMetrics]) -> Double? {
        var powerWeightedSum: Double = 0
        var powerWeightTotal: Double = 0
        var cpuWeightedSum: Double = 0
        var cpuWeightTotal: Double = 0
        var simpleSum: Double = 0
        var simpleCount: Int = 0

        for child in children {
            guard let share = child.pCoreShare, share.isFinite else { continue }
            if child.directPowerW > 0 {
                powerWeightedSum += share * child.directPowerW
                powerWeightTotal += child.directPowerW
            }
            if child.cpuPercent > 0 {
                cpuWeightedSum += share * child.cpuPercent
                cpuWeightTotal += child.cpuPercent
            }
            simpleSum += share
            simpleCount += 1
        }

        if powerWeightTotal > 0 {
            return clampedUnitInterval(powerWeightedSum / powerWeightTotal)
        }
        if cpuWeightTotal > 0 {
            return clampedUnitInterval(cpuWeightedSum / cpuWeightTotal)
        }
        if simpleCount > 0 {
            return clampedUnitInterval(simpleSum / Double(simpleCount))
        }
        return nil
    }

    private static func passesNoiseFilter(
        powerW: Double,
        cpuPercent: Double,
        wakeupsPerSecond: Double,
        diskBytesPerSecond: Double,
        isPreventingSleep: Bool
    ) -> Bool {
        if isPreventingSleep { return true }
        return powerW >= 0.0005
            || cpuPercent >= 0.05
            || wakeupsPerSecond >= 1.0
            || diskBytesPerSecond >= 1024.0
    }

    private static func sortConsumers(_ lhs: EnergyConsumerItem, _ rhs: EnergyConsumerItem) -> Bool {
        if lhs.powerW != rhs.powerW {
            return lhs.powerW > rhs.powerW
        }
        if lhs.energyImpact != rhs.energyImpact {
            return lhs.energyImpact > rhs.energyImpact
        }
        if lhs.cpuPercent != rhs.cpuPercent {
            return lhs.cpuPercent > rhs.cpuPercent
        }
        return lhs.id < rhs.id
    }

    private static func sortProcessMetrics(_ lhs: ProcessEnergyMetrics, _ rhs: ProcessEnergyMetrics) -> Bool {
        if lhs.powerW != rhs.powerW {
            return lhs.powerW > rhs.powerW
        }
        if lhs.energyImpact != rhs.energyImpact {
            return lhs.energyImpact > rhs.energyImpact
        }
        if lhs.cpuPercent != rhs.cpuPercent {
            return lhs.cpuPercent > rhs.cpuPercent
        }
        return lhs.pid < rhs.pid
    }

    private static func safeDelta(current: UInt64, previous: UInt64) -> UInt64 {
        current >= previous ? (current - previous) : 0
    }

    private static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }

    private static func ema(_ previous: Double, _ current: Double, alpha: Double) -> Double {
        previous + alpha * (current - previous)
    }

    private static func sanitizedNonNegative(_ value: Double) -> Double {
        value.isFinite ? max(0.0, value) : 0.0
    }

    private static func clampedUnitInterval(_ value: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return min(max(value, 0.0), 1.0)
    }

    private static func normalizedAssertions(_ raw: [String]) -> [String] {
        guard !raw.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(raw.count)
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, seen.insert(trimmed).inserted {
                result.append(trimmed)
            }
        }
        return result.sorted()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
