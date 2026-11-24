import Foundation

enum PowerFlowMode: String, Sendable, Equatable, Hashable, Codable {
    case adapterBypass
    case adapterCharging
    case adapterBatteryHybrid
    case batteryOnly
    case connectingAC
    case unknown
}

enum PowerConnectionPhase: String, Sendable, Equatable, Hashable, Codable {
    case onBattery
    case connectingAC
    case onAC
}

enum PowerTelemetrySource: String, Sendable, Equatable, Hashable, Codable {
    case smcAndIOKit
    case iokitTelemetry
    case iokitLegacy
    case unavailable
}

enum BatteryCondition: String, Sendable, Equatable, Hashable, Codable {
    case normal
    case serviceRecommended
    case unknown
}

enum PowerPortKind: String, Sendable, Equatable, Hashable, Codable {
    case magSafe
    case usbC
    case unknown
}

enum BatteryChargeLimitSource: String, Sendable, Equatable, Hashable, Codable {
    case none
    case macOSSetting
    case optimizedCharging
    case alDente
}

enum ThermalPressureLevel: String, Sendable, Equatable, Hashable, Codable {
    case nominal
    case fair
    case serious
    case critical
}

enum PhysicalPortRole: String, Sendable, Equatable, Hashable, Codable {
    case powerInActive
    case powerInStandby
    case powerOut
    case dataOnly
    case idle
}

struct USBPDProfile: Sendable, Equatable, Hashable, Identifiable, Codable {
    let id: Int
    let index: Int
    let maxVoltageV: Double
    let maxCurrentA: Double
    let maxWatts: Double
    let isActive: Bool

    init(
        id: Int,
        index: Int,
        maxVoltageV: Double,
        maxCurrentA: Double,
        maxWatts: Double,
        isActive: Bool = false
    ) {
        self.id = id
        self.index = index
        self.maxVoltageV = maxVoltageV
        self.maxCurrentA = maxCurrentA
        self.maxWatts = maxWatts
        self.isActive = isActive
    }

    init(
        index: Int,
        maxVoltageV: Double,
        maxCurrentA: Double,
        maxWatts: Double,
        isActive: Bool = false
    ) {
        self.init(
            id: index,
            index: index,
            maxVoltageV: maxVoltageV,
            maxCurrentA: maxCurrentA,
            maxWatts: maxWatts,
            isActive: isActive
        )
    }
}

struct BatteryLifetimeStats: Sendable, Equatable, Hashable, Codable {
    let operatingHours: Int?
    let minTempC: Double?
    let avgTempC: Double?
    let maxTempC: Double?
    let minPackVoltageV: Double?
    let maxPackVoltageV: Double?
    let maxChargeCurrentA: Double?
    let maxDischargeCurrentA: Double?

    init(
        operatingHours: Int? = nil,
        minTempC: Double? = nil,
        avgTempC: Double? = nil,
        maxTempC: Double? = nil,
        minPackVoltageV: Double? = nil,
        maxPackVoltageV: Double? = nil,
        maxChargeCurrentA: Double? = nil,
        maxDischargeCurrentA: Double? = nil
    ) {
        self.operatingHours = operatingHours
        self.minTempC = minTempC
        self.avgTempC = avgTempC
        self.maxTempC = maxTempC
        self.minPackVoltageV = minPackVoltageV
        self.maxPackVoltageV = maxPackVoltageV
        self.maxChargeCurrentA = maxChargeCurrentA
        self.maxDischargeCurrentA = maxDischargeCurrentA
    }
}

struct FanReading: Sendable, Equatable, Hashable, Identifiable, Codable {
    let id: Int
    let index: Int
    let rpm: Double
    let maxRpm: Double?

    init(
        id: Int,
        index: Int,
        rpm: Double,
        maxRpm: Double? = nil
    ) {
        self.id = id
        self.index = index
        self.rpm = rpm
        self.maxRpm = maxRpm
    }

    init(
        index: Int,
        rpm: Double,
        maxRpm: Double? = nil
    ) {
        self.init(id: index, index: index, rpm: rpm, maxRpm: maxRpm)
    }

    var percentMax: Double? {
        guard let maxRpm, maxRpm > 0, rpm.isFinite, maxRpm.isFinite else {
            return nil
        }
        return min(max((rpm / maxRpm) * 100.0, 0.0), 100.0)
    }
}

struct SystemPowerBreakdown: Sendable, Equatable, Hashable, Codable {
    let packagePowerW: Double?
    let displayPowerW: Double?
    let otherSystemW: Double?
    let cpuTemperatureC: Double?
    let gpuTemperatureC: Double?
    let thermalState: ThermalPressureLevel
    let fans: [FanReading]

    init(
        packagePowerW: Double? = nil,
        displayPowerW: Double? = nil,
        otherSystemW: Double? = nil,
        cpuTemperatureC: Double? = nil,
        gpuTemperatureC: Double? = nil,
        thermalState: ThermalPressureLevel = .nominal,
        fans: [FanReading] = []
    ) {
        self.packagePowerW = packagePowerW
        self.displayPowerW = displayPowerW
        self.otherSystemW = otherSystemW
        self.cpuTemperatureC = cpuTemperatureC
        self.gpuTemperatureC = gpuTemperatureC
        self.thermalState = thermalState
        self.fans = fans
    }
}

struct PhysicalPortStatus: Sendable, Equatable, Hashable, Identifiable, Codable {
    let id: String
    let portKind: PowerPortKind
    let portNumber: Int
    let portLabel: String
    let role: PhysicalPortRole
    let connectionActive: Bool
    let deviceName: String?
    let manufacturer: String?
    let cableType: String?
    let activeTransports: [String]
    let powerW: Double
    let currentA: Double
    let voltageV: Double
    let maxPDWatts: Double
    let vconnPowerW: Double
    let vconnCurrentA: Double

    init(
        id: String,
        portKind: PowerPortKind,
        portNumber: Int,
        portLabel: String,
        role: PhysicalPortRole,
        connectionActive: Bool,
        deviceName: String? = nil,
        manufacturer: String? = nil,
        cableType: String? = nil,
        activeTransports: [String] = [],
        powerW: Double = 0,
        currentA: Double = 0,
        voltageV: Double = 0,
        maxPDWatts: Double = 0,
        vconnPowerW: Double = 0,
        vconnCurrentA: Double = 0
    ) {
        self.id = id
        self.portKind = portKind
        self.portNumber = portNumber
        self.portLabel = portLabel
        self.role = role
        self.connectionActive = connectionActive
        self.deviceName = deviceName
        self.manufacturer = manufacturer
        self.cableType = cableType
        self.activeTransports = activeTransports
        self.powerW = powerW
        self.currentA = currentA
        self.voltageV = voltageV
        self.maxPDWatts = maxPDWatts
        self.vconnPowerW = vconnPowerW
        self.vconnCurrentA = vconnCurrentA
    }
}

struct AdapterSourceInfo: Sendable, Equatable, Hashable, Identifiable, Codable {
    let id: String
    let isActive: Bool
    let portKind: PowerPortKind
    let portNumber: Int?
    let portLabel: String
    let name: String?
    let manufacturer: String?
    let serialNumber: String?
    let model: String?
    let description: String?
    let ratedWatts: Double
    let ratedVoltageV: Double
    let ratedCurrentA: Double
    let connectedDeviceName: String?
    let firmwareVersion: String?
    let hardwareVersion: String?
    let adapterID: Int?
    let pdProfiles: [USBPDProfile]
    let activePDProfileIndex: Int?

    init(
        id: String,
        isActive: Bool,
        portKind: PowerPortKind,
        portNumber: Int? = nil,
        portLabel: String,
        name: String? = nil,
        manufacturer: String? = nil,
        serialNumber: String? = nil,
        model: String? = nil,
        description: String? = nil,
        ratedWatts: Double,
        ratedVoltageV: Double,
        ratedCurrentA: Double,
        connectedDeviceName: String? = nil,
        firmwareVersion: String? = nil,
        hardwareVersion: String? = nil,
        adapterID: Int? = nil,
        pdProfiles: [USBPDProfile] = [],
        activePDProfileIndex: Int? = nil
    ) {
        self.id = id
        self.isActive = isActive
        self.portKind = portKind
        self.portNumber = portNumber
        self.portLabel = portLabel
        self.name = name
        self.manufacturer = manufacturer
        self.serialNumber = serialNumber
        self.model = model
        self.description = description
        self.ratedWatts = ratedWatts
        self.ratedVoltageV = ratedVoltageV
        self.ratedCurrentA = ratedCurrentA
        self.connectedDeviceName = connectedDeviceName
        self.firmwareVersion = firmwareVersion
        self.hardwareVersion = hardwareVersion
        self.adapterID = adapterID
        self.pdProfiles = pdProfiles
        self.activePDProfileIndex = activePDProfileIndex
    }
}

struct OutboundPortPower: Sendable, Equatable, Hashable, Identifiable, Codable {
    let id: String
    let portIndex: Int
    let portLabel: String
    let deviceName: String?
    let manufacturer: String?
    let isDisplayPortActive: Bool
    let currentA: Double
    let voltageV: Double
    let powerW: Double
    let configuredVoltageV: Double
    let configuredCurrentA: Double
    let maxPDWatts: Double
    let vconnCurrentA: Double
    let vconnPowerW: Double
    let filteredPowerW: Double?
    let activeTransports: [String]
    let cableType: String?
    let pdSpecRevision: Int?

    init(
        id: String,
        portIndex: Int,
        portLabel: String,
        deviceName: String? = nil,
        manufacturer: String? = nil,
        isDisplayPortActive: Bool = false,
        currentA: Double,
        voltageV: Double,
        powerW: Double,
        configuredVoltageV: Double = 0,
        configuredCurrentA: Double = 0,
        maxPDWatts: Double = 0,
        vconnCurrentA: Double = 0,
        vconnPowerW: Double = 0,
        filteredPowerW: Double? = nil,
        activeTransports: [String] = [],
        cableType: String? = nil,
        pdSpecRevision: Int? = nil
    ) {
        self.id = id
        self.portIndex = portIndex
        self.portLabel = portLabel
        self.deviceName = deviceName
        self.manufacturer = manufacturer
        self.isDisplayPortActive = isDisplayPortActive
        self.currentA = currentA
        self.voltageV = voltageV
        self.powerW = powerW
        self.configuredVoltageV = configuredVoltageV
        self.configuredCurrentA = configuredCurrentA
        self.maxPDWatts = maxPDWatts
        self.vconnCurrentA = vconnCurrentA
        self.vconnPowerW = vconnPowerW
        self.filteredPowerW = filteredPowerW
        self.activeTransports = activeTransports
        self.cableType = cableType
        self.pdSpecRevision = pdSpecRevision
    }
}

struct BatteryHealthInfo: Sendable, Equatable, Hashable, Codable {
    let designCapacityMAh: Int?
    let rawMaxCapacityMAh: Int?
    let nominalCapacityMAh: Int?
    let currentChargeMAh: Int?
    let macOSCapacityPercent: Int?
    let realHealthPercent: Double?
    let condition: BatteryCondition
    let cycleCount: Int?
    let designCycleCount: Int?
    let manufactureDate: String?
    let batterySerial: String?
    let deviceName: String?
    let lifetime: BatteryLifetimeStats?

    init(
        designCapacityMAh: Int? = nil,
        rawMaxCapacityMAh: Int? = nil,
        nominalCapacityMAh: Int? = nil,
        currentChargeMAh: Int? = nil,
        macOSCapacityPercent: Int? = nil,
        realHealthPercent: Double? = nil,
        condition: BatteryCondition = .unknown,
        cycleCount: Int? = nil,
        designCycleCount: Int? = nil,
        manufactureDate: String? = nil,
        batterySerial: String? = nil,
        deviceName: String? = nil,
        lifetime: BatteryLifetimeStats? = nil
    ) {
        self.designCapacityMAh = designCapacityMAh
        self.rawMaxCapacityMAh = rawMaxCapacityMAh
        self.nominalCapacityMAh = nominalCapacityMAh
        self.currentChargeMAh = currentChargeMAh
        self.macOSCapacityPercent = macOSCapacityPercent
        self.realHealthPercent = realHealthPercent
        self.condition = condition
        self.cycleCount = cycleCount
        self.designCycleCount = designCycleCount
        self.manufactureDate = manufactureDate
        self.batterySerial = batterySerial
        self.deviceName = deviceName
        self.lifetime = lifetime
    }

    static let empty = BatteryHealthInfo()
}

struct BatteryCellTopology: Sendable, Equatable, Hashable, Codable {
    let seriesCount: Int
    let parallelCount: Int
    let voltagesMV: [Int]
    let qmaxMAh: [Int]

    init(
        seriesCount: Int,
        parallelCount: Int,
        voltagesMV: [Int] = [],
        qmaxMAh: [Int] = []
    ) {
        self.seriesCount = seriesCount
        self.parallelCount = parallelCount
        self.voltagesMV = voltagesMV
        self.qmaxMAh = qmaxMAh
    }

    var label: String {
        if seriesCount > 0 && parallelCount > 0 {
            return "\(seriesCount)S\(parallelCount)P"
        }
        if seriesCount > 0 {
            return "\(seriesCount)S"
        }
        if !voltagesMV.isEmpty {
            return "\(voltagesMV.count)S"
        }
        return "—"
    }

    var voltageSpreadMV: Int? {
        let valid = voltagesMV.filter { $0 > 0 }
        guard valid.count >= 2, let minV = valid.min(), let maxV = valid.max() else {
            return nil
        }
        return maxV - minV
    }
}

struct PowerSnapshot: Sendable, Equatable, Hashable, Codable {
    let timestamp: Date
    let isDataAvailable: Bool
    let telemetrySource: PowerTelemetrySource
    let connectionPhase: PowerConnectionPhase
    let flowMode: PowerFlowMode
    let batteryPercent: Int
    let rawStateOfCharge: Int?
    let isExternalConnected: Bool
    let isCharging: Bool
    let isFullyCharged: Bool
    let atCriticalLevel: Bool
    /// The system low-battery warning that turns the menu bar battery red.
    let isLowBatteryWarning: Bool
    let isLowPowerModeEnabled: Bool
    /// Positive (>0) when charging, negative (<0) when discharging.
    let batteryCurrentA: Double
    let batteryVoltageV: Double
    /// Positive (>0) when charging, negative (<0) when discharging.
    let batteryPowerW: Double
    let batteryTemperatureC: Double?
    let chargeLimitPercent: Int
    let chargeLimitSource: BatteryChargeLimitSource
    let timeRemainingMinutes: Int?
    let isTimeEstimateToFull: Bool
    let totalSystemLoadW: Double
    let netSystemLoadW: Double
    let adapterInputPowerW: Double
    let adapterInputVoltageV: Double
    let adapterInputCurrentA: Double
    let adapterEfficiencyLossW: Double?
    let activeAdapter: AdapterSourceInfo?
    let standbyAdapters: [AdapterSourceInfo]
    let outboundPorts: [OutboundPortPower]
    let totalOutboundPowerW: Double
    let totalOutboundCurrentA: Double
    let health: BatteryHealthInfo
    let cellTopology: BatteryCellTopology?
    let wallPowerEstimateW: Double?
    let batteryRemainingWh: Double?
    let batteryDesignWh: Double?
    let batteryFullChargeWh: Double?
    let chargingHoldReason: String?
    let systemBreakdown: SystemPowerBreakdown?
    let physicalPorts: [PhysicalPortStatus]

    init(
        timestamp: Date = Date(),
        isDataAvailable: Bool = false,
        telemetrySource: PowerTelemetrySource = .unavailable,
        connectionPhase: PowerConnectionPhase = .onBattery,
        flowMode: PowerFlowMode = .unknown,
        batteryPercent: Int = 0,
        rawStateOfCharge: Int? = nil,
        isExternalConnected: Bool = false,
        isCharging: Bool = false,
        isFullyCharged: Bool = false,
        atCriticalLevel: Bool = false,
        isLowBatteryWarning: Bool = false,
        isLowPowerModeEnabled: Bool = false,
        batteryCurrentA: Double = 0,
        batteryVoltageV: Double = 0,
        batteryPowerW: Double = 0,
        batteryTemperatureC: Double? = nil,
        chargeLimitPercent: Int = 100,
        chargeLimitSource: BatteryChargeLimitSource = .none,
        timeRemainingMinutes: Int? = nil,
        isTimeEstimateToFull: Bool = false,
        totalSystemLoadW: Double = 0,
        netSystemLoadW: Double = 0,
        adapterInputPowerW: Double = 0,
        adapterInputVoltageV: Double = 0,
        adapterInputCurrentA: Double = 0,
        adapterEfficiencyLossW: Double? = nil,
        activeAdapter: AdapterSourceInfo? = nil,
        standbyAdapters: [AdapterSourceInfo] = [],
        outboundPorts: [OutboundPortPower] = [],
        totalOutboundPowerW: Double = 0,
        totalOutboundCurrentA: Double = 0,
        health: BatteryHealthInfo = .empty,
        cellTopology: BatteryCellTopology? = nil,
        wallPowerEstimateW: Double? = nil,
        batteryRemainingWh: Double? = nil,
        batteryDesignWh: Double? = nil,
        batteryFullChargeWh: Double? = nil,
        chargingHoldReason: String? = nil,
        systemBreakdown: SystemPowerBreakdown? = nil,
        physicalPorts: [PhysicalPortStatus] = []
    ) {
        self.timestamp = timestamp
        self.isDataAvailable = isDataAvailable
        self.telemetrySource = telemetrySource
        self.connectionPhase = connectionPhase
        self.flowMode = flowMode
        self.batteryPercent = batteryPercent
        self.rawStateOfCharge = rawStateOfCharge
        self.isExternalConnected = isExternalConnected
        self.isCharging = isCharging
        self.isFullyCharged = isFullyCharged
        self.atCriticalLevel = atCriticalLevel
        self.isLowBatteryWarning = isLowBatteryWarning
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.batteryCurrentA = batteryCurrentA
        self.batteryVoltageV = batteryVoltageV
        self.batteryPowerW = batteryPowerW
        self.batteryTemperatureC = batteryTemperatureC
        self.chargeLimitPercent = chargeLimitPercent
        self.chargeLimitSource = chargeLimitSource
        self.timeRemainingMinutes = timeRemainingMinutes
        self.isTimeEstimateToFull = isTimeEstimateToFull
        self.totalSystemLoadW = totalSystemLoadW
        self.netSystemLoadW = netSystemLoadW
        self.adapterInputPowerW = adapterInputPowerW
        self.adapterInputVoltageV = adapterInputVoltageV
        self.adapterInputCurrentA = adapterInputCurrentA
        self.adapterEfficiencyLossW = adapterEfficiencyLossW
        self.activeAdapter = activeAdapter
        self.standbyAdapters = standbyAdapters
        self.outboundPorts = outboundPorts
        self.totalOutboundPowerW = totalOutboundPowerW
        self.totalOutboundCurrentA = totalOutboundCurrentA
        self.health = health
        self.cellTopology = cellTopology
        self.wallPowerEstimateW = wallPowerEstimateW
        self.batteryRemainingWh = batteryRemainingWh
        self.batteryDesignWh = batteryDesignWh
        self.batteryFullChargeWh = batteryFullChargeWh
        self.chargingHoldReason = chargingHoldReason
        self.systemBreakdown = systemBreakdown
        self.physicalPorts = physicalPorts
    }

    static let empty = PowerSnapshot(
        timestamp: .distantPast,
        isDataAvailable: false,
        telemetrySource: .unavailable,
        connectionPhase: .onBattery,
        flowMode: .unknown
    )

    var isEffectivelyOnAC: Bool {
        isExternalConnected || connectionPhase != .onBattery
    }

    var isBatteryCharging: Bool {
        batteryPowerW > 0.1 || batteryCurrentA > 0.02
    }

    var isBatteryDischarging: Bool {
        batteryPowerW < -0.1 || batteryCurrentA < -0.02
    }

    var hasActiveOutboundPower: Bool {
        totalOutboundPowerW > 0.05
            || totalOutboundCurrentA > 0.01
            || outboundPorts.contains { $0.powerW > 0.05 || $0.currentA > 0.01 }
    }

    var batteryChargeRateW: Double {
        max(0, batteryPowerW)
    }

    var batteryDischargeRateW: Double {
        max(0, -batteryPowerW)
    }
}
