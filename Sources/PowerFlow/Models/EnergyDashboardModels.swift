import Foundation

enum EnergyDashboardItemLimit: Int, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    case top3 = 3
    case top5 = 5
    case top8 = 8

    var id: Int { rawValue }
}

enum EnergyGroupingMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    case byApp
    case byProcess

    var id: String { rawValue }
}

enum EnergySamplingPhase: String, Codable, Equatable, Hashable, Sendable {
    case idle
    case warmingUp
    case ready
    case unavailable
}

enum HardwareEnergySegmentKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    case soc
    case display
    case outbound
    case other

    var id: String { rawValue }
}

struct HardwareEnergySegment: Sendable, Equatable, Hashable, Identifiable, Codable {
    let id: HardwareEnergySegmentKind
    var kind: HardwareEnergySegmentKind { id }
    let watts: Double
    let share: Double

    init(id: HardwareEnergySegmentKind, watts: Double, share: Double) {
        self.id = id
        self.watts = watts
        self.share = share
    }

    init(kind: HardwareEnergySegmentKind, watts: Double, share: Double) {
        self.init(id: kind, watts: watts, share: share)
    }
}

struct HardwareEnergyBreakdown: Sendable, Equatable, Hashable, Codable {
    private static let minimumResidualWatts = 0.05

    let totalWatts: Double
    let segments: [HardwareEnergySegment]

    var isAvailable: Bool {
        totalWatts.isFinite && totalWatts > 0 && !segments.isEmpty
    }

    init(totalWatts: Double, segments: [HardwareEnergySegment]) {
        self.totalWatts = totalWatts
        self.segments = segments
    }

    static let empty = HardwareEnergyBreakdown(totalWatts: 0, segments: [])

    static func from(snapshot: PowerSnapshot) -> Self {
        guard snapshot.isDataAvailable else { return .empty }

        let socW = sanitizedPositive(snapshot.systemBreakdown?.packagePowerW)
        let displayW = sanitizedPositive(snapshot.systemBreakdown?.displayPowerW)
        let outboundW = sanitizedPositive(snapshot.totalOutboundPowerW)

        let reportedTotalW = sanitizedPositive(snapshot.totalSystemLoadW)
        let reportedNetW = sanitizedPositive(snapshot.netSystemLoadW)
        let explicitTotalW: Double
        if reportedTotalW > 0 {
            explicitTotalW = reportedTotalW
        } else if reportedNetW > 0 {
            explicitTotalW = reportedNetW + outboundW
        } else {
            explicitTotalW = 0
        }

        let knownW = socW + displayW + outboundW
        let residualW: Double
        if explicitTotalW > 0 {
            residualW = max(0, explicitTotalW - knownW)
        } else {
            residualW = sanitizedPositive(snapshot.systemBreakdown?.otherSystemW)
        }

        var rawSegments: [(kind: HardwareEnergySegmentKind, watts: Double)] = []
        if socW > 0 {
            rawSegments.append((.soc, socW))
        }
        if displayW > 0 {
            rawSegments.append((.display, displayW))
        }
        if outboundW > 0 {
            rawSegments.append((.outbound, outboundW))
        }
        if residualW >= minimumResidualWatts {
            rawSegments.append((.other, residualW))
        }

        let segmentSum = rawSegments.reduce(0.0) { $0 + $1.watts }
        guard segmentSum.isFinite, segmentSum > 0 else { return .empty }

        let segments = rawSegments.map { entry in
            let rawShare = entry.watts / segmentSum
            let share = rawShare.isFinite ? min(max(rawShare, 0.0), 1.0) : 0.0
            return HardwareEnergySegment(id: entry.kind, watts: entry.watts, share: share)
        }

        let totalWatts = max(explicitTotalW, segmentSum)
        guard totalWatts.isFinite, totalWatts > 0 else { return .empty }

        return HardwareEnergyBreakdown(totalWatts: totalWatts, segments: segments)
    }

    private static func sanitizedPositive(_ value: Double?) -> Double {
        guard let value, value.isFinite, value > 0 else { return 0 }
        return value
    }
}

struct RawProcessEnergySample: Sendable, Equatable, Hashable {
    let pid: Int32
    let ppid: Int32
    let startAbsTime: UInt64
    let processName: String
    let executablePath: String
    let appBundlePath: String?
    let appDisplayName: String?
    let bundleIdentifier: String?
    let energyNJ: UInt64
    let pCoreEnergyNJ: UInt64
    let billedEnergyNJ: UInt64
    let cpuTimeNS: UInt64
    let pCoreTimeNS: UInt64
    let idleWakeups: UInt64
    let diskReadBytes: UInt64
    let diskWriteBytes: UInt64
    let physFootprintBytes: UInt64
    let sleepAssertionTypes: [String]

    init(
        pid: Int32,
        ppid: Int32 = 0,
        startAbsTime: UInt64 = 0,
        processName: String = "",
        executablePath: String = "",
        appBundlePath: String? = nil,
        appDisplayName: String? = nil,
        bundleIdentifier: String? = nil,
        energyNJ: UInt64 = 0,
        pCoreEnergyNJ: UInt64 = 0,
        billedEnergyNJ: UInt64 = 0,
        cpuTimeNS: UInt64 = 0,
        pCoreTimeNS: UInt64 = 0,
        idleWakeups: UInt64 = 0,
        diskReadBytes: UInt64 = 0,
        diskWriteBytes: UInt64 = 0,
        physFootprintBytes: UInt64 = 0,
        sleepAssertionTypes: [String] = []
    ) {
        self.pid = pid
        self.ppid = ppid
        self.startAbsTime = startAbsTime
        self.processName = processName
        self.executablePath = executablePath
        self.appBundlePath = appBundlePath
        self.appDisplayName = appDisplayName
        self.bundleIdentifier = bundleIdentifier
        self.energyNJ = energyNJ
        self.pCoreEnergyNJ = pCoreEnergyNJ
        self.billedEnergyNJ = billedEnergyNJ
        self.cpuTimeNS = cpuTimeNS
        self.pCoreTimeNS = pCoreTimeNS
        self.idleWakeups = idleWakeups
        self.diskReadBytes = diskReadBytes
        self.diskWriteBytes = diskWriteBytes
        self.physFootprintBytes = physFootprintBytes
        self.sleepAssertionTypes = sleepAssertionTypes
    }
}

struct ProcessEnergyMetrics: Sendable, Equatable, Hashable, Identifiable, Codable {
    let id: Int32
    let pid: Int32
    let name: String
    let executablePath: String
    let appBundlePath: String?
    let powerW: Double
    let directPowerW: Double
    let billedPowerW: Double
    let pCoreShare: Double?
    let energyImpact: Double
    let cpuPercent: Double
    let wakeupsPerSecond: Double
    let diskBytesPerSecond: Double
    let memoryBytes: UInt64
    let isPreventingSleep: Bool
    let sleepAssertionTypes: [String]

    init(
        id: Int32,
        pid: Int32,
        name: String,
        executablePath: String = "",
        appBundlePath: String? = nil,
        powerW: Double = 0,
        directPowerW: Double = 0,
        billedPowerW: Double = 0,
        pCoreShare: Double? = nil,
        energyImpact: Double = 0,
        cpuPercent: Double = 0,
        wakeupsPerSecond: Double = 0,
        diskBytesPerSecond: Double = 0,
        memoryBytes: UInt64 = 0,
        isPreventingSleep: Bool = false,
        sleepAssertionTypes: [String] = []
    ) {
        self.id = id
        self.pid = pid
        self.name = name
        self.executablePath = executablePath
        self.appBundlePath = appBundlePath
        self.powerW = powerW
        self.directPowerW = directPowerW
        self.billedPowerW = billedPowerW
        self.pCoreShare = pCoreShare
        self.energyImpact = energyImpact
        self.cpuPercent = cpuPercent
        self.wakeupsPerSecond = wakeupsPerSecond
        self.diskBytesPerSecond = diskBytesPerSecond
        self.memoryBytes = memoryBytes
        self.isPreventingSleep = isPreventingSleep
        self.sleepAssertionTypes = sleepAssertionTypes
    }

    init(
        pid: Int32,
        name: String,
        executablePath: String = "",
        appBundlePath: String? = nil,
        powerW: Double = 0,
        directPowerW: Double = 0,
        billedPowerW: Double = 0,
        pCoreShare: Double? = nil,
        energyImpact: Double = 0,
        cpuPercent: Double = 0,
        wakeupsPerSecond: Double = 0,
        diskBytesPerSecond: Double = 0,
        memoryBytes: UInt64 = 0,
        isPreventingSleep: Bool = false,
        sleepAssertionTypes: [String] = []
    ) {
        self.init(
            id: pid,
            pid: pid,
            name: name,
            executablePath: executablePath,
            appBundlePath: appBundlePath,
            powerW: powerW,
            directPowerW: directPowerW,
            billedPowerW: billedPowerW,
            pCoreShare: pCoreShare,
            energyImpact: energyImpact,
            cpuPercent: cpuPercent,
            wakeupsPerSecond: wakeupsPerSecond,
            diskBytesPerSecond: diskBytesPerSecond,
            memoryBytes: memoryBytes,
            isPreventingSleep: isPreventingSleep,
            sleepAssertionTypes: sleepAssertionTypes
        )
    }
}

struct EnergyConsumerItem: Sendable, Equatable, Hashable, Identifiable, Codable {
    let id: String
    let displayName: String
    let iconPath: String?
    let bundleIdentifier: String?
    let primaryPID: Int32
    let powerW: Double
    let directPowerW: Double
    let billedPowerW: Double
    let pCoreShare: Double?
    let energyImpact: Double
    let cpuPercent: Double
    let wakeupsPerSecond: Double
    let diskBytesPerSecond: Double
    let memoryBytes: UInt64
    let isPreventingSleep: Bool
    let sleepAssertionTypes: [String]
    let processCount: Int
    let processes: [ProcessEnergyMetrics]

    init(
        id: String,
        displayName: String,
        iconPath: String? = nil,
        bundleIdentifier: String? = nil,
        primaryPID: Int32 = 0,
        powerW: Double = 0,
        directPowerW: Double = 0,
        billedPowerW: Double = 0,
        pCoreShare: Double? = nil,
        energyImpact: Double = 0,
        cpuPercent: Double = 0,
        wakeupsPerSecond: Double = 0,
        diskBytesPerSecond: Double = 0,
        memoryBytes: UInt64 = 0,
        isPreventingSleep: Bool = false,
        sleepAssertionTypes: [String] = [],
        processCount: Int = 1,
        processes: [ProcessEnergyMetrics] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.iconPath = iconPath
        self.bundleIdentifier = bundleIdentifier
        self.primaryPID = primaryPID
        self.powerW = powerW
        self.directPowerW = directPowerW
        self.billedPowerW = billedPowerW
        self.pCoreShare = pCoreShare
        self.energyImpact = energyImpact
        self.cpuPercent = cpuPercent
        self.wakeupsPerSecond = wakeupsPerSecond
        self.diskBytesPerSecond = diskBytesPerSecond
        self.memoryBytes = memoryBytes
        self.isPreventingSleep = isPreventingSleep
        self.sleepAssertionTypes = sleepAssertionTypes
        self.processCount = processCount
        self.processes = processes
    }
}

struct EnergySnapshot: Sendable, Equatable, Hashable, Codable {
    let timestamp: Date
    let phase: EnergySamplingPhase
    let windowSeconds: TimeInterval
    let sampledProcessCount: Int
    let totalMeasuredPowerW: Double
    let appConsumers: [EnergyConsumerItem]
    let processConsumers: [EnergyConsumerItem]

    init(
        timestamp: Date = .distantPast,
        phase: EnergySamplingPhase = .idle,
        windowSeconds: TimeInterval = 0,
        sampledProcessCount: Int = 0,
        totalMeasuredPowerW: Double = 0,
        appConsumers: [EnergyConsumerItem] = [],
        processConsumers: [EnergyConsumerItem] = []
    ) {
        self.timestamp = timestamp
        self.phase = phase
        self.windowSeconds = windowSeconds
        self.sampledProcessCount = sampledProcessCount
        self.totalMeasuredPowerW = totalMeasuredPowerW
        self.appConsumers = appConsumers
        self.processConsumers = processConsumers
    }

    static let empty = EnergySnapshot(
        timestamp: .distantPast,
        phase: .idle,
        windowSeconds: 0,
        sampledProcessCount: 0,
        totalMeasuredPowerW: 0,
        appConsumers: [],
        processConsumers: []
    )

    func consumers(for mode: EnergyGroupingMode, limit: Int) -> [EnergyConsumerItem] {
        guard limit > 0 else { return [] }
        let source: [EnergyConsumerItem]
        switch mode {
        case .byApp:
            source = appConsumers
        case .byProcess:
            source = processConsumers
        }
        return Array(source.prefix(limit))
    }

    func consumers(for mode: EnergyGroupingMode, limit: EnergyDashboardItemLimit) -> [EnergyConsumerItem] {
        consumers(for: mode, limit: limit.rawValue)
    }
}
