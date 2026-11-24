import Foundation
import IOKit
import IOKit.ps

// MARK: - Provider Protocol

protocol SmartBatteryReadingProvider: Sendable {
    func readSmartBattery(includeCellTopology: Bool) -> SmartBatteryReading?
    func readExternalConnectedFast() -> Bool?
}

// MARK: - Smart Battery Reader

final class SmartBatteryReader: SmartBatteryReadingProvider, @unchecked Sendable {
    init() {}

    func readSmartBattery(includeCellTopology: Bool) -> SmartBatteryReading? {
        guard let properties = IOKitHelpers.copyIOServiceProperties(className: "AppleSmartBattery") else {
            return nil
        }
        let packProperties = IOKitHelpers.copyIOServiceProperties(className: "AppleSmartBatteryPack")
        let cellTopology = includeCellTopology
            ? readCellTopology(batteryProperties: properties, packProperties: packProperties)
            : nil
        let iopsCondition = Self.readBatteryConditionFromIOPS()

        return Self.parseSmartBattery(
            properties: properties,
            packProperties: packProperties,
            cellTopology: cellTopology,
            iopsCondition: iopsCondition,
            isLowBatteryWarning: IOPSGetBatteryWarningLevel() != kIOPSLowBatteryWarningNone
        )
    }

    func readExternalConnectedFast() -> Bool? {
        guard let matching = IOServiceMatching("AppleSmartBattery") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        if let cfVal = IORegistryEntryCreateCFProperty(
            service,
            "ExternalConnected" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue(),
            let connected = IOKitHelpers.extractBool(cfVal)
        {
            return connected
        }

        if let cfVal = IORegistryEntryCreateCFProperty(
            service,
            "AppleRawExternalConnected" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue(),
            let connected = IOKitHelpers.extractBool(cfVal)
        {
            return connected
        }

        return nil
    }

    // MARK: - Pure Parser (Unit Testable)

    static func parseSmartBattery(
        properties: [String: Any],
        packProperties: [String: Any]? = nil,
        cellTopology: BatteryCellTopology? = nil,
        iopsCondition: BatteryCondition? = nil,
        isLowBatteryWarning: Bool = false,
        referenceDate: Date = Date()
    ) -> SmartBatteryReading {
        let batteryData = IOKitHelpers.extractDict(properties, key: "BatteryData")
        let packBatteryData = packProperties.flatMap { IOKitHelpers.extractDict($0, key: "BatteryData") }
        let chargerData = IOKitHelpers.extractDict(properties, key: "ChargerData")
        let telemetry = IOKitHelpers.extractDict(properties, key: "PowerTelemetryData")

        func lookupInt(_ keys: [String], positiveOnly: Bool = false) -> Int? {
            let sources: [[String: Any]?] = [properties, batteryData, packBatteryData, packProperties]
            for key in keys {
                for source in sources {
                    guard let source, let val = IOKitHelpers.extractInt(source, key: key) else {
                        continue
                    }
                    if positiveOnly && val <= 0 {
                        continue
                    }
                    return val
                }
            }
            return nil
        }

        func lookupBool(_ keys: [String]) -> Bool? {
            let sources: [[String: Any]?] = [properties, chargerData, batteryData, packBatteryData]
            for key in keys {
                for source in sources {
                    if let source, let val = IOKitHelpers.extractBool(source, key: key) {
                        return val
                    }
                }
            }
            return nil
        }

        func lookupString(_ keys: [String]) -> String? {
            let sources: [[String: Any]?] = [properties, batteryData, packBatteryData, packProperties]
            for key in keys {
                for source in sources {
                    if let source, let val = IOKitHelpers.extractString(source, key: key) {
                        return val
                    }
                }
            }
            return nil
        }

        // Charge & Status
        let currentCapacityPercent = lookupInt(["CurrentCapacity"]) ?? 0
        let maxCapacityPercent = lookupInt(["MaxCapacity"], positiveOnly: true) ?? 100
        let stateOfCharge = lookupInt(["StateOfCharge"])
        let dailyMinSoc = lookupInt(["DailyMinSoc"])
        let dailyMaxSoc = lookupInt(["DailyMaxSoc"])

        let isExternalConnected = lookupBool(["ExternalConnected", "AppleRawExternalConnected"]) ?? false
        let isCharging = lookupBool(["IsCharging"]) ?? false
        let isFullyCharged = lookupBool(["FullyCharged"]) ?? false
        let atCriticalLevel = lookupBool(["AtCriticalLevel"]) ?? false

        let notChargingReason = chargerData.flatMap { IOKitHelpers.extractInt($0, key: "NotChargingReason") }
        let slowChargingReason = chargerData.flatMap { IOKitHelpers.extractInt($0, key: "SlowChargingReason") }

        let rawTimeRemaining = lookupInt(["TimeRemaining"])
        let timeRemainingMinutes = normalizeOSMinutes(rawTimeRemaining)
        let rawAvgTimeToEmpty = lookupInt(["AvgTimeToEmpty"])
        let avgTimeToEmptyMinutes = normalizeOSMinutes(rawAvgTimeToEmpty)

        // Instant Electrical & Thermal
        let voltageMV = lookupInt(["Voltage", "AppleRawBatteryVoltage"], positiveOnly: true) ?? 0
        let instantAmperageMA = lookupInt(["InstantAmperage", "Amperage"]) ?? 0
        let amperageMA = lookupInt(["Amperage", "InstantAmperage"]) ?? 0
        let temperatureC = parseTemperatureC(
            topLevel: properties,
            batteryData: batteryData,
            packBatteryData: packBatteryData
        )

        // PowerTelemetryData
        let telemetrySystemPowerInMW = telemetry.flatMap { IOKitHelpers.extractInt($0, key: "SystemPowerIn") }
        let telemetrySystemLoadMW = telemetry.flatMap { IOKitHelpers.extractInt($0, key: "SystemLoad") }
        let telemetryBatteryPowerMW = telemetry.flatMap { IOKitHelpers.extractInt($0, key: "BatteryPower") }
            ?? batteryData.flatMap { IOKitHelpers.extractInt($0, key: "BatteryPower") }
            ?? packBatteryData.flatMap { IOKitHelpers.extractInt($0, key: "BatteryPower") }
        let telemetrySystemVoltageInMV = telemetry.flatMap { IOKitHelpers.extractInt($0, key: "SystemVoltageIn") }
        let telemetrySystemCurrentInMA = telemetry.flatMap { IOKitHelpers.extractInt($0, key: "SystemCurrentIn") }
        let telemetryAdapterEfficiencyLossMW = telemetry.flatMap {
            IOKitHelpers.extractInt($0, key: "AdapterEfficiencyLoss")
        }
        let telemetryWallEnergyEstimateMW = telemetry.flatMap {
            IOKitHelpers.extractInt($0, key: "WallEnergyEstimate")
        }

        // Adapters
        let activeAdapter = IOKitHelpers.extractDict(properties, key: "AdapterDetails")
            .flatMap { parseAdapterEntry($0, index: 0) }
        let rawAdapters: [RawAdapterEntry] = (IOKitHelpers.extractDictArray(properties, key: "AppleRawAdapterDetails") ?? [])
            .enumerated()
            .compactMap { index, dict in parseAdapterEntry(dict, index: index) }

        // Outbound & Fed Ports
        let powerOutDetails: [RawPowerOutEntry] = (IOKitHelpers.extractDictArray(properties, key: "PowerOutDetails") ?? [])
            .compactMap { parsePowerOutEntry($0) }
        let fedDetails: [RawFedPortEntry] = (IOKitHelpers.extractDictArray(properties, key: "FedDetails") ?? [])
            .enumerated()
            .map { index, dict in parseFedPortEntry(dict, index: index) }

        // Capacities & Health (top-level -> BatteryData -> Pack.BatteryData)
        let designCapacityMAh = lookupInt(["DesignCapacity"], positiveOnly: true)
        let rawMaxCapacityMAh = lookupInt(["AppleRawMaxCapacity", "FullChargeCapacity"], positiveOnly: true)
        let fullChargeCapacityMAh = lookupInt(["FullChargeCapacity", "AppleRawMaxCapacity"], positiveOnly: true)
        let nominalCapacityMAh = lookupInt(["NominalChargeCapacity"], positiveOnly: true)
        let currentChargeMAh = lookupInt(["AppleRawCurrentCapacity", "RemainingCapacity"], positiveOnly: true)
        let cycleCount = lookupInt(["CycleCount"])
        let designCycleCount = lookupInt(["DesignCycleCount9C", "DesignCycleCount"], positiveOnly: true)

        let condition = resolveBatteryCondition(
            permanentFailureStatus: lookupInt(["PermanentFailureStatus"]),
            batteryHealthString: lookupString(["BatteryHealth"]),
            iopsCondition: iopsCondition
        )

        let manufactureDate = lookupInt(["ManufactureDate"], positiveOnly: true)
            .flatMap { IOKitHelpers.formatBatteryManufactureDate($0, relativeTo: referenceDate) }
        let batterySerial = lookupString(["Serial", "BatterySerialNumber"])
        let deviceName = lookupString(["DeviceName"])
        let lifetimeStats = parseLifetimeStats(
            packBatteryData: packBatteryData,
            batteryData: batteryData,
            topLevel: properties
        )

        let resolvedCellTopology = cellTopology
            ?? parseLegacyCellTopology(batteryData: batteryData ?? packBatteryData)

        return SmartBatteryReading(
            currentCapacityPercent: currentCapacityPercent,
            maxCapacityPercent: maxCapacityPercent,
            stateOfCharge: stateOfCharge,
            dailyMinSoc: dailyMinSoc,
            dailyMaxSoc: dailyMaxSoc,
            isExternalConnected: isExternalConnected,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            atCriticalLevel: atCriticalLevel,
            isLowBatteryWarning: isLowBatteryWarning,
            notChargingReason: notChargingReason,
            slowChargingReason: slowChargingReason,
            timeRemainingMinutes: timeRemainingMinutes,
            avgTimeToEmptyMinutes: avgTimeToEmptyMinutes,
            voltageMV: voltageMV,
            instantAmperageMA: instantAmperageMA,
            amperageMA: amperageMA,
            temperatureC: temperatureC,
            telemetrySystemPowerInMW: telemetrySystemPowerInMW,
            telemetrySystemLoadMW: telemetrySystemLoadMW,
            telemetryBatteryPowerMW: telemetryBatteryPowerMW,
            telemetrySystemVoltageInMV: telemetrySystemVoltageInMV,
            telemetrySystemCurrentInMA: telemetrySystemCurrentInMA,
            telemetryAdapterEfficiencyLossMW: telemetryAdapterEfficiencyLossMW,
            telemetryWallEnergyEstimateMW: telemetryWallEnergyEstimateMW,
            activeAdapter: activeAdapter,
            rawAdapters: rawAdapters,
            powerOutDetails: powerOutDetails,
            fedDetails: fedDetails,
            designCapacityMAh: designCapacityMAh,
            rawMaxCapacityMAh: rawMaxCapacityMAh,
            fullChargeCapacityMAh: fullChargeCapacityMAh,
            nominalCapacityMAh: nominalCapacityMAh,
            currentChargeMAh: currentChargeMAh,
            cycleCount: cycleCount,
            designCycleCount: designCycleCount,
            condition: condition,
            manufactureDate: manufactureDate,
            batterySerial: batterySerial,
            deviceName: deviceName,
            lifetimeStats: lifetimeStats,
            cellTopology: resolvedCellTopology
        )
    }

    // MARK: - Sub-Parsers

    static func parseAdapterEntry(_ dict: [String: Any], index: Int) -> RawAdapterEntry? {
        let watts = Double(IOKitHelpers.extractInt(dict, key: "Watts") ?? 0)
        let voltageMV = IOKitHelpers.extractInt(dict, key: "AdapterVoltage") ?? 0
        let currentMA = IOKitHelpers.extractInt(dict, key: "Current") ?? 0
        let name = IOKitHelpers.extractString(dict, key: "Name")
        let manufacturer = IOKitHelpers.extractString(dict, key: "Manufacturer")
        let serialNumber = IOKitHelpers.extractString(dict, key: "SerialString")
        let model = IOKitHelpers.extractString(dict, key: "Model")
        let description = IOKitHelpers.extractString(dict, key: "Description")
        let adapterID = IOKitHelpers.extractInt(dict, key: "AdapterID")
        let firmwareVersion = IOKitHelpers.extractString(dict, key: "FwVersion")
        let hardwareVersion = IOKitHelpers.extractString(dict, key: "HwVersion")

        let rawActiveHvcIndex = IOKitHelpers.extractInt(dict, key: "UsbHvcHvcIndex")
        let activeHvcIndex = rawActiveHvcIndex.flatMap { ($0 >= 0 && $0 < 255) ? $0 : nil }
        let pdProfiles = parseUSBPDProfiles(
            from: IOKitHelpers.extractDictArray(dict, key: "UsbHvcMenu"),
            activeIndex: activeHvcIndex
        )

        // Skip completely empty placeholder dictionaries.
        if watts <= 0, voltageMV <= 0, currentMA <= 0, name == nil, description == nil {
            return nil
        }

        return RawAdapterEntry(
            index: index,
            name: name,
            manufacturer: manufacturer,
            serialNumber: serialNumber,
            model: model,
            description: description,
            watts: watts,
            voltageMV: voltageMV,
            currentMA: currentMA,
            adapterID: adapterID,
            firmwareVersion: firmwareVersion,
            hardwareVersion: hardwareVersion,
            activeHvcIndex: activeHvcIndex,
            pdProfiles: pdProfiles
        )
    }

    static func parseUSBPDProfiles(
        from rawMenu: [[String: Any]]?,
        activeIndex: Int?
    ) -> [USBPDProfile] {
        guard let rawMenu, !rawMenu.isEmpty else { return [] }

        var profiles: [USBPDProfile] = []
        profiles.reserveCapacity(rawMenu.count)

        for (offset, item) in rawMenu.enumerated() {
            let profileIndex = IOKitHelpers.extractInt(item, key: "Index") ?? offset
            guard let maxVoltageMV = IOKitHelpers.extractInt(item, key: "MaxVoltage"),
                  let maxCurrentMA = IOKitHelpers.extractInt(item, key: "MaxCurrent"),
                  maxVoltageMV > 0,
                  maxCurrentMA > 0
            else {
                continue
            }

            let maxVoltageV = Double(maxVoltageMV) / 1000.0
            let maxCurrentA = Double(maxCurrentMA) / 1000.0
            let maxWatts = maxVoltageV * maxCurrentA

            profiles.append(
                USBPDProfile(
                    id: profileIndex,
                    index: profileIndex,
                    maxVoltageV: maxVoltageV,
                    maxCurrentA: maxCurrentA,
                    maxWatts: maxWatts,
                    isActive: activeIndex != nil && profileIndex == activeIndex
                )
            )
        }

        return profiles.sorted { $0.index < $1.index }
    }

    static func parseLifetimeStats(
        packBatteryData: [String: Any]?,
        batteryData: [String: Any]?,
        topLevel: [String: Any]? = nil
    ) -> BatteryLifetimeStats? {
        let lifetime = packBatteryData.flatMap { IOKitHelpers.extractDict($0, key: "LifetimeData") }
            ?? batteryData.flatMap { IOKitHelpers.extractDict($0, key: "LifetimeData") }
            ?? topLevel.flatMap { IOKitHelpers.extractDict($0, key: "LifetimeData") }
        guard let lifetime else { return nil }

        let operatingHours = IOKitHelpers.extractInt(lifetime, key: "TotalOperatingTime")
            .flatMap { $0 > 0 ? $0 : nil }
        let minTempC = normalizeLifetimeTempC(IOKitHelpers.extractInt(lifetime, key: "MinimumTemperature"))
        let avgTempC = normalizeLifetimeTempC(IOKitHelpers.extractInt(lifetime, key: "AverageTemperature"))
        let maxTempC = normalizeLifetimeTempC(IOKitHelpers.extractInt(lifetime, key: "MaximumTemperature"))

        let minPackVoltageV = IOKitHelpers.extractInt(lifetime, key: "MinimumPackVoltage")
            .flatMap { $0 > 0 ? Double($0) / 1000.0 : nil }
        let maxPackVoltageV = IOKitHelpers.extractInt(lifetime, key: "MaximumPackVoltage")
            .flatMap { $0 > 0 ? Double($0) / 1000.0 : nil }

        let maxChargeCurrentA = IOKitHelpers.extractInt(lifetime, key: "MaximumChargeCurrent")
            .flatMap { $0 != 0 ? abs(Double($0)) / 1000.0 : nil }
        let maxDischargeCurrentA = IOKitHelpers.extractInt(lifetime, key: "MaximumDischargeCurrent")
            .flatMap { $0 != 0 ? abs(Double($0)) / 1000.0 : nil }

        if operatingHours == nil,
           minTempC == nil,
           avgTempC == nil,
           maxTempC == nil,
           minPackVoltageV == nil,
           maxPackVoltageV == nil,
           maxChargeCurrentA == nil,
           maxDischargeCurrentA == nil
        {
            return nil
        }

        return BatteryLifetimeStats(
            operatingHours: operatingHours,
            minTempC: minTempC,
            avgTempC: avgTempC,
            maxTempC: maxTempC,
            minPackVoltageV: minPackVoltageV,
            maxPackVoltageV: maxPackVoltageV,
            maxChargeCurrentA: maxChargeCurrentA,
            maxDischargeCurrentA: maxDischargeCurrentA
        )
    }

    private static func normalizeLifetimeTempC(_ raw: Int?) -> Double? {
        guard let raw else { return nil }
        let celsius: Double
        if abs(raw) > 100 {
            celsius = Double(raw) / 10.0
        } else {
            celsius = Double(raw)
        }
        guard celsius >= -40.0, celsius <= 120.0 else { return nil }
        return celsius
    }

    static func parsePowerOutEntry(_ dict: [String: Any]) -> RawPowerOutEntry? {
        guard let portIndex = IOKitHelpers.extractInt(dict, key: "PortIndex") else {
            return nil
        }
        return RawPowerOutEntry(
            portIndex: portIndex,
            wattsMW: max(0, IOKitHelpers.extractInt(dict, key: "Watts") ?? 0),
            filteredPowerMW: max(0, IOKitHelpers.extractInt(dict, key: "FilteredPower") ?? 0),
            currentMA: max(0, IOKitHelpers.extractInt(dict, key: "Current") ?? 0),
            voltageMV: max(0, IOKitHelpers.extractInt(dict, key: "AdapterVoltage") ?? 0),
            configuredVoltageMV: max(0, IOKitHelpers.extractInt(dict, key: "ConfiguredVoltage") ?? 0),
            configuredCurrentMA: max(0, IOKitHelpers.extractInt(dict, key: "ConfiguredCurrent") ?? 0),
            pdPowerMW: max(0, IOKitHelpers.extractInt(dict, key: "PDPowermW") ?? 0),
            vconnCurrentMA: max(0, IOKitHelpers.extractInt(dict, key: "VConnCurrent") ?? 0),
            vconnPowerMW: max(0, IOKitHelpers.extractInt(dict, key: "VConnPower") ?? 0)
        )
    }

    static func parseFedPortEntry(_ dict: [String: Any], index: Int) -> RawFedPortEntry {
        let pdSpecRevision = IOKitHelpers.extractInt(dict, key: "FedPdSpecRevision")
            .flatMap { $0 > 0 ? $0 : nil }
        return RawFedPortEntry(
            arrayIndex: index,
            portPowerRole: IOKitHelpers.extractInt(dict, key: "FedPortPowerRole") ?? 0,
            vendorID: IOKitHelpers.extractInt(dict, key: "FedVendorID") ?? 0,
            productID: IOKitHelpers.extractInt(dict, key: "FedProductID") ?? 0,
            externalConnected: IOKitHelpers.extractBool(dict, key: "FedExternalConnected") ?? false,
            pdSpecRevision: pdSpecRevision
        )
    }

    /// Parses temperature across macOS formats:
    /// - Centi-Kelvin (`>= 20_000`, e.g. `31084` -> `37.69°C`) on top-level `AppleSmartBattery.Temperature`.
    /// - Centi-Celsius (`100...10_000`, e.g. `2759` -> `27.59°C`, `3769` -> `37.69°C`) in `BatteryData.Temperature`.
    static func parseTemperatureC(
        topLevel: [String: Any],
        batteryData: [String: Any]?,
        packBatteryData: [String: Any]?
    ) -> Double? {
        let candidates: [Int?] = [
            IOKitHelpers.extractInt(topLevel, key: "Temperature"),
            batteryData.flatMap { IOKitHelpers.extractInt($0, key: "Temperature") },
            packBatteryData.flatMap { IOKitHelpers.extractInt($0, key: "Temperature") },
            batteryData.flatMap { IOKitHelpers.extractInt($0, key: "VirtualTemperature") },
            packBatteryData.flatMap { IOKitHelpers.extractInt($0, key: "VirtualTemperature") }
        ]

        for candidate in candidates {
            guard let raw = candidate, raw > 0 else { continue }
            let celsius: Double
            if raw >= 20_000 {
                celsius = Double(raw) / 100.0 - 273.15
            } else if raw >= 100 && raw <= 10_000 {
                celsius = Double(raw) / 100.0
            } else {
                continue
            }
            if celsius >= -10.0 && celsius <= 100.0 {
                return celsius
            }
        }
        return nil
    }

    static func resolveBatteryCondition(
        permanentFailureStatus: Int?,
        batteryHealthString: String?,
        iopsCondition: BatteryCondition?
    ) -> BatteryCondition {
        if let failure = permanentFailureStatus, failure > 0 {
            return .serviceRecommended
        }
        if let health = batteryHealthString?.lowercased() {
            if health == "good" || health == "normal" {
                return .normal
            }
            if !health.isEmpty {
                return .serviceRecommended
            }
        }
        if let iopsCondition, iopsCondition != .unknown {
            return iopsCondition
        }
        if let failure = permanentFailureStatus, failure == 0 {
            return .normal
        }
        return .unknown
    }

    static func normalizeOSMinutes(_ raw: Int?) -> Int? {
        guard let raw, raw >= 0, raw < 65_535 else { return nil }
        return raw
    }

    // MARK: - Cell Topology (AppleSmartBatteryBank + Legacy Fallback)

    private func readCellTopology(
        batteryProperties: [String: Any],
        packProperties: [String: Any]?
    ) -> BatteryCellTopology? {
        let bankEntries = IOKitHelpers.copyAllIOServiceProperties(className: "AppleSmartBatteryBank")
        if !bankEntries.isEmpty {
            let cellEntries = IOKitHelpers.copyAllIOServiceProperties(className: "AppleSmartBatteryCell")
            if let topology = Self.parseBankCellTopology(
                bankProperties: bankEntries,
                cellProperties: cellEntries
            ) {
                return topology
            }
        }

        let batteryData = IOKitHelpers.extractDict(batteryProperties, key: "BatteryData")
            ?? packProperties.flatMap { IOKitHelpers.extractDict($0, key: "BatteryData") }
        return Self.parseLegacyCellTopology(batteryData: batteryData)
    }

    static func parseBankCellTopology(
        bankProperties: [[String: Any]],
        cellProperties: [[String: Any]]
    ) -> BatteryCellTopology? {
        guard !bankProperties.isEmpty else { return nil }

        let sortedBanks = bankProperties.sorted { lhs, rhs in
            (IOKitHelpers.extractInt(lhs, key: "BankID") ?? 0)
                < (IOKitHelpers.extractInt(rhs, key: "BankID") ?? 0)
        }

        var voltages: [Int] = []
        var qmaxValues: [Int] = []
        for bank in sortedBanks {
            let data = IOKitHelpers.extractDict(bank, key: "BatteryData") ?? bank
            if let voltage = IOKitHelpers.extractInt(data, key: "CellVoltage"), voltage > 0 {
                voltages.append(voltage)
            }
            if let qmax = IOKitHelpers.extractInt(data, key: "Qmax"), qmax > 0 {
                qmaxValues.append(qmax)
            }
        }

        let seriesCount = sortedBanks.count
        var parallelCount = 1
        if !cellProperties.isEmpty {
            var cellsPerBank: [Int: Int] = [:]
            for cell in cellProperties {
                let bankID = IOKitHelpers.extractInt(cell, key: "BankID") ?? 0
                cellsPerBank[bankID, default: 0] += 1
            }
            if let maxCells = cellsPerBank.values.max(), maxCells > 0 {
                parallelCount = maxCells
            }
        }

        return BatteryCellTopology(
            seriesCount: seriesCount,
            parallelCount: parallelCount,
            voltagesMV: voltages,
            qmaxMAh: qmaxValues
        )
    }

    static func parseLegacyCellTopology(batteryData: [String: Any]?) -> BatteryCellTopology? {
        guard let batteryData else { return nil }
        let voltages = (IOKitHelpers.extractIntArray(batteryData, key: "CellVoltage") ?? [])
            .filter { $0 > 0 }
        let qmax = (IOKitHelpers.extractIntArray(batteryData, key: "Qmax") ?? [])
            .filter { $0 > 0 }
        guard !voltages.isEmpty else { return nil }
        return BatteryCellTopology(
            seriesCount: voltages.count,
            parallelCount: 1,
            voltagesMV: voltages,
            qmaxMAh: qmax
        )
    }

    // MARK: - IOPS Battery Health

    static func readBatteryConditionFromIOPS() -> BatteryCondition {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return .unknown
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue()
                as? [String: Any]
            else {
                continue
            }
            if let health = desc[kIOPSBatteryHealthKey] as? String {
                let normalized = health.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalized == "good" {
                    return .normal
                }
                if !normalized.isEmpty {
                    return .serviceRecommended
                }
            }
        }

        return .unknown
    }
}
