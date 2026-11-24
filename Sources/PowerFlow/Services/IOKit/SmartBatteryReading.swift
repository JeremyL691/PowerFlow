import Foundation

// MARK: - Raw Adapter / Outbound / Fed Entries

struct RawAdapterEntry: Sendable, Equatable {
    let index: Int
    let name: String?
    let manufacturer: String?
    let serialNumber: String?
    let model: String?
    let description: String?
    let watts: Double
    let voltageMV: Int
    let currentMA: Int
    let adapterID: Int?
    let firmwareVersion: String?
    let hardwareVersion: String?
    let activeHvcIndex: Int?
    let pdProfiles: [USBPDProfile]

    init(
        index: Int,
        name: String?,
        manufacturer: String?,
        serialNumber: String?,
        model: String?,
        description: String?,
        watts: Double,
        voltageMV: Int,
        currentMA: Int,
        adapterID: Int?,
        firmwareVersion: String? = nil,
        hardwareVersion: String? = nil,
        activeHvcIndex: Int? = nil,
        pdProfiles: [USBPDProfile] = []
    ) {
        self.index = index
        self.name = name
        self.manufacturer = manufacturer
        self.serialNumber = serialNumber
        self.model = model
        self.description = description
        self.watts = watts
        self.voltageMV = voltageMV
        self.currentMA = currentMA
        self.adapterID = adapterID
        self.firmwareVersion = firmwareVersion
        self.hardwareVersion = hardwareVersion
        self.activeHvcIndex = activeHvcIndex
        self.pdProfiles = pdProfiles
    }
}

struct RawPowerOutEntry: Sendable, Equatable {
    let portIndex: Int
    let wattsMW: Int
    let filteredPowerMW: Int
    let currentMA: Int
    let voltageMV: Int
    let configuredVoltageMV: Int
    let configuredCurrentMA: Int
    let pdPowerMW: Int
    let vconnCurrentMA: Int
    let vconnPowerMW: Int
}

struct RawFedPortEntry: Sendable, Equatable {
    let arrayIndex: Int
    let portPowerRole: Int
    let vendorID: Int
    let productID: Int
    let externalConnected: Bool
    let pdSpecRevision: Int?

    init(
        arrayIndex: Int,
        portPowerRole: Int,
        vendorID: Int,
        productID: Int,
        externalConnected: Bool,
        pdSpecRevision: Int? = nil
    ) {
        self.arrayIndex = arrayIndex
        self.portPowerRole = portPowerRole
        self.vendorID = vendorID
        self.productID = productID
        self.externalConnected = externalConnected
        self.pdSpecRevision = pdSpecRevision
    }
}

// MARK: - Smart Battery Reading

struct SmartBatteryReading: Sendable, Equatable {
    // Charge & Connection State
    let currentCapacityPercent: Int
    let maxCapacityPercent: Int
    let stateOfCharge: Int?
    let dailyMinSoc: Int?
    let dailyMaxSoc: Int?
    let isExternalConnected: Bool
    let isCharging: Bool
    let isFullyCharged: Bool
    let atCriticalLevel: Bool
    /// `IOPSGetBatteryWarningLevel()` reports an early or final warning.
    let isLowBatteryWarning: Bool
    let notChargingReason: Int?
    let slowChargingReason: Int?
    let timeRemainingMinutes: Int?
    let avgTimeToEmptyMinutes: Int?

    // Instant Electrical & Thermal
    let voltageMV: Int
    let instantAmperageMA: Int
    let amperageMA: Int
    let temperatureC: Double?

    // PowerTelemetryData (Apple Silicon mW / mV / mA)
    let telemetrySystemPowerInMW: Int?
    let telemetrySystemLoadMW: Int?
    let telemetryBatteryPowerMW: Int?
    let telemetrySystemVoltageInMV: Int?
    let telemetrySystemCurrentInMA: Int?
    let telemetryAdapterEfficiencyLossMW: Int?
    let telemetryWallEnergyEstimateMW: Int?

    // Adapters & Outbound Ports
    let activeAdapter: RawAdapterEntry?
    let rawAdapters: [RawAdapterEntry]
    let powerOutDetails: [RawPowerOutEntry]
    let fedDetails: [RawFedPortEntry]

    // Battery Health & Identity
    let designCapacityMAh: Int?
    let rawMaxCapacityMAh: Int?
    let fullChargeCapacityMAh: Int?
    let nominalCapacityMAh: Int?
    let currentChargeMAh: Int?
    let cycleCount: Int?
    let designCycleCount: Int?
    let condition: BatteryCondition
    let manufactureDate: String?
    let batterySerial: String?
    let deviceName: String?
    let lifetimeStats: BatteryLifetimeStats?

    // Cell Topology
    let cellTopology: BatteryCellTopology?

    init(
        currentCapacityPercent: Int,
        maxCapacityPercent: Int,
        stateOfCharge: Int?,
        dailyMinSoc: Int?,
        dailyMaxSoc: Int?,
        isExternalConnected: Bool,
        isCharging: Bool,
        isFullyCharged: Bool,
        atCriticalLevel: Bool,
        isLowBatteryWarning: Bool = false,
        notChargingReason: Int?,
        slowChargingReason: Int?,
        timeRemainingMinutes: Int?,
        avgTimeToEmptyMinutes: Int?,
        voltageMV: Int,
        instantAmperageMA: Int,
        amperageMA: Int,
        temperatureC: Double?,
        telemetrySystemPowerInMW: Int?,
        telemetrySystemLoadMW: Int?,
        telemetryBatteryPowerMW: Int?,
        telemetrySystemVoltageInMV: Int?,
        telemetrySystemCurrentInMA: Int?,
        telemetryAdapterEfficiencyLossMW: Int?,
        telemetryWallEnergyEstimateMW: Int? = nil,
        activeAdapter: RawAdapterEntry?,
        rawAdapters: [RawAdapterEntry],
        powerOutDetails: [RawPowerOutEntry],
        fedDetails: [RawFedPortEntry],
        designCapacityMAh: Int?,
        rawMaxCapacityMAh: Int?,
        fullChargeCapacityMAh: Int?,
        nominalCapacityMAh: Int?,
        currentChargeMAh: Int?,
        cycleCount: Int?,
        designCycleCount: Int?,
        condition: BatteryCondition,
        manufactureDate: String?,
        batterySerial: String?,
        deviceName: String?,
        lifetimeStats: BatteryLifetimeStats? = nil,
        cellTopology: BatteryCellTopology?
    ) {
        self.currentCapacityPercent = currentCapacityPercent
        self.maxCapacityPercent = maxCapacityPercent
        self.stateOfCharge = stateOfCharge
        self.dailyMinSoc = dailyMinSoc
        self.dailyMaxSoc = dailyMaxSoc
        self.isExternalConnected = isExternalConnected
        self.isCharging = isCharging
        self.isFullyCharged = isFullyCharged
        self.atCriticalLevel = atCriticalLevel
        self.isLowBatteryWarning = isLowBatteryWarning
        self.notChargingReason = notChargingReason
        self.slowChargingReason = slowChargingReason
        self.timeRemainingMinutes = timeRemainingMinutes
        self.avgTimeToEmptyMinutes = avgTimeToEmptyMinutes
        self.voltageMV = voltageMV
        self.instantAmperageMA = instantAmperageMA
        self.amperageMA = amperageMA
        self.temperatureC = temperatureC
        self.telemetrySystemPowerInMW = telemetrySystemPowerInMW
        self.telemetrySystemLoadMW = telemetrySystemLoadMW
        self.telemetryBatteryPowerMW = telemetryBatteryPowerMW
        self.telemetrySystemVoltageInMV = telemetrySystemVoltageInMV
        self.telemetrySystemCurrentInMA = telemetrySystemCurrentInMA
        self.telemetryAdapterEfficiencyLossMW = telemetryAdapterEfficiencyLossMW
        self.telemetryWallEnergyEstimateMW = telemetryWallEnergyEstimateMW
        self.activeAdapter = activeAdapter
        self.rawAdapters = rawAdapters
        self.powerOutDetails = powerOutDetails
        self.fedDetails = fedDetails
        self.designCapacityMAh = designCapacityMAh
        self.rawMaxCapacityMAh = rawMaxCapacityMAh
        self.fullChargeCapacityMAh = fullChargeCapacityMAh
        self.nominalCapacityMAh = nominalCapacityMAh
        self.currentChargeMAh = currentChargeMAh
        self.cycleCount = cycleCount
        self.designCycleCount = designCycleCount
        self.condition = condition
        self.manufactureDate = manufactureDate
        self.batterySerial = batterySerial
        self.deviceName = deviceName
        self.lifetimeStats = lifetimeStats
        self.cellTopology = cellTopology
    }

    var hasPowerTelemetry: Bool {
        telemetrySystemPowerInMW != nil
            || telemetrySystemLoadMW != nil
            || telemetryBatteryPowerMW != nil
    }
}
