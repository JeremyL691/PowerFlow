import Foundation

/// Pure, deterministic telemetry fusion engine combining SMC samples, IOKit SmartBattery readings,
/// and IOPort physical topology into a unified `PowerSnapshot`.
final class PowerFlowResolver: @unchecked Sendable {
    typealias ChargeLimitProvider = @Sendable (_ notChargingReason: Int?) -> BatteryChargeLimitInfo

    let polarityCalibrator: SMCPolarityCalibrator
    private let timeEstimator: BatteryTimeEstimator
    private let chargeLimitProvider: ChargeLimitProvider
    private let outboundGate = OutboundPortGate()

    init(
        polarityCalibrator: SMCPolarityCalibrator = SMCPolarityCalibrator(),
        timeEstimator: BatteryTimeEstimator = BatteryTimeEstimator(),
        chargeLimitProvider: @escaping ChargeLimitProvider = { notChargingReason in
            BatteryChargeLimitResolver.resolveWithSystemDefaults(notChargingReason: notChargingReason)
        }
    ) {
        self.polarityCalibrator = polarityCalibrator
        self.timeEstimator = timeEstimator
        self.chargeLimitProvider = chargeLimitProvider
    }

    func resetEstimator() {
        timeEstimator.reset()
    }

    func resolve(
        reading: SmartBatteryReading?,
        smc: SMCPowerSample = .empty,
        portTopology: [IOPortTopologyEntry] = [],
        connectionPhase: PowerConnectionPhase,
        isLowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
        timestamp: Date = Date()
    ) -> PowerSnapshot {
        guard let reading else {
            return PowerSnapshot(
                timestamp: timestamp,
                isDataAvailable: false,
                telemetrySource: .unavailable,
                connectionPhase: .onBattery,
                flowMode: .unknown,
                isLowPowerModeEnabled: isLowPowerModeEnabled
            )
        }

        let effectiveOnAC = connectionPhase != .onBattery && reading.isExternalConnected
        let telemetrySource: PowerTelemetrySource = {
            if smc.hasAnyPowerReading {
                return .smcAndIOKit
            }
            if reading.hasPowerTelemetry {
                return .iokitTelemetry
            }
            return .iokitLegacy
        }()

        // 1. Outbound USB-C Power & Device Resolution
        let outboundPorts = outboundGate.filter(
            Self.resolveOutboundPorts(
                powerOutDetails: reading.powerOutDetails,
                fedDetails: reading.fedDetails,
                portTopology: portTopology,
                liveOutputs: smc.portOutputs
            ),
            at: timestamp
        )
        let totalOutboundPowerW = outboundPorts.reduce(0.0) { $0 + $1.powerW }
        let totalOutboundCurrentA = outboundPorts.reduce(0.0) { $0 + $1.currentA }

        // 2. Active & Standby Adapter Resolution (suppressed when onBattery to prevent stale glitches)
        let activeAdapter: AdapterSourceInfo?
        let standbyAdapters: [AdapterSourceInfo]
        let adapterInputVoltageV: Double
        let adapterInputCurrentA: Double
        let adapterInputPowerW: Double
        let adapterEfficiencyLossW: Double?

        if connectionPhase == .onBattery {
            activeAdapter = nil
            standbyAdapters = []
            adapterInputVoltageV = 0
            adapterInputCurrentA = 0
            adapterInputPowerW = 0
            adapterEfficiencyLossW = nil
        } else {
            let resolvedAdapters = Self.resolveAdapters(
                activeRaw: reading.activeAdapter,
                rawAdapters: reading.rawAdapters,
                portTopology: portTopology
            )
            activeAdapter = resolvedAdapters.active
            standbyAdapters = resolvedAdapters.standby

            let smcVoltage = smc.adapterInputVoltageV.flatMap { $0 > 0.5 ? $0 : nil }
            let iokitVoltage = reading.telemetrySystemVoltageInMV.flatMap { $0 > 500 ? Double($0) / 1000.0 : nil }
            let ratedVoltage = reading.activeAdapter.flatMap { $0.voltageMV > 500 ? Double($0.voltageMV) / 1000.0 : nil }
            adapterInputVoltageV = smcVoltage ?? iokitVoltage ?? ratedVoltage ?? 0

            let smcCurrent = smc.adapterInputCurrentA.flatMap { $0 >= 0 ? $0 : nil }
            let iokitCurrent = reading.telemetrySystemCurrentInMA.flatMap { $0 >= 0 ? Double($0) / 1000.0 : nil }

            let smcDeliveryW = smc.deliveryRateW.flatMap { $0 >= 0 ? $0 : nil }
            let iokitPowerInW = reading.telemetrySystemPowerInMW.flatMap { $0 >= 0 ? Double($0) / 1000.0 : nil }

            let rawCurrent = smcCurrent ?? iokitCurrent ?? 0
            let computedFromVI = (adapterInputVoltageV > 0.5 && rawCurrent > 0.005)
                ? adapterInputVoltageV * rawCurrent
                : 0
            let resolvedPowerIn = smcDeliveryW ?? iokitPowerInW ?? computedFromVI
            adapterInputPowerW = resolvedPowerIn < 0.05 ? 0 : resolvedPowerIn

            if rawCurrent >= 0.005 {
                adapterInputCurrentA = rawCurrent
            } else if adapterInputPowerW > 0.05 && adapterInputVoltageV > 1.0 {
                adapterInputCurrentA = adapterInputPowerW / adapterInputVoltageV
            } else {
                adapterInputCurrentA = 0
            }

            if let lossMW = reading.telemetryAdapterEfficiencyLossMW, lossMW >= 0 {
                adapterEfficiencyLossW = Double(lossMW) / 1000.0
            } else {
                adapterEfficiencyLossW = nil
            }
        }

        // 3. Battery Voltage, Current, and Power (Strictly Unified Sign Convention)
        let batteryVoltageV: Double = {
            if let smcV = smc.batteryVoltageV, smcV > 1.0 {
                return smcV
            }
            return reading.voltageMV > 0 ? Double(reading.voltageMV) / 1000.0 : 0
        }()

        let rawIOKitCurrentA: Double = {
            if reading.instantAmperageMA != 0 {
                return Double(reading.instantAmperageMA) / 1000.0
            }
            return Double(reading.amperageMA) / 1000.0
        }()
        let hasExplicitCurrentReading = smc.batteryCurrentA != nil
            || reading.instantAmperageMA != 0
            || reading.amperageMA != 0

        var batteryCurrentA = smc.batteryCurrentA ?? rawIOKitCurrentA
        if !effectiveOnAC && batteryCurrentA > 0.005 {
            batteryCurrentA = -abs(batteryCurrentA)
        }
        if abs(batteryCurrentA) < 0.005 {
            batteryCurrentA = 0
        }

        // Preliminary system load estimate for energy-balance cross-checking
        let preliminaryLoadW: Double = {
            if let smcLoad = smc.systemTotalW, smcLoad > 0.05 {
                return smcLoad
            }
            if let telemetryLoadMW = reading.telemetrySystemLoadMW, telemetryLoadMW > 0 {
                return Double(telemetryLoadMW) / 1000.0
            }
            return 0
        }()

        let telemetryPowerW: Double? = reading.telemetryBatteryPowerMW.map { rawTelemetryMW in
            Self.unifyIOKitBatteryPower(
                rawTelemetryW: Double(rawTelemetryMW) / 1000.0,
                isExternalConnected: effectiveOnAC,
                isCharging: reading.isCharging,
                batteryCurrentA: batteryCurrentA,
                adapterInputPowerW: adapterInputPowerW,
                systemLoadW: preliminaryLoadW
            )
        }
        let viPowerW: Double? = (batteryVoltageV > 1.0 && abs(batteryCurrentA) >= 0.005)
            ? (batteryVoltageV * batteryCurrentA)
            : nil
        let referencePowerW: Double = {
            if let telemetryPowerW, abs(telemetryPowerW) >= 1.0 {
                return telemetryPowerW
            }
            return viPowerW ?? 0
        }()

        var batteryPowerW: Double = {
            if let rawPPBR = smc.batteryRateW {
                let calibrated = polarityCalibrator.normalizeBatteryPower(
                    rawPPBR: rawPPBR,
                    isExternalConnected: effectiveOnAC,
                    isCharging: reading.isCharging
                )
                // On Apple Silicon models where PPBR is discharge-only (~0.0–0.8W while charging),
                // fall back to IOKit BatteryPower or V*I when PPBR severely under-reports active flow.
                if abs(referencePowerW) >= 1.5 && abs(calibrated) < abs(referencePowerW) * 0.35 {
                    if let telemetryPowerW, abs(telemetryPowerW) >= 1.0 {
                        return telemetryPowerW
                    }
                    if let viPowerW {
                        return viPowerW
                    }
                }
                return calibrated
            }

            if let telemetryPowerW {
                if abs(telemetryPowerW) >= 1.0 || viPowerW == nil {
                    return telemetryPowerW
                }
            }

            return viPowerW ?? 0
        }()

        // Cross-verify battery power & current sign consistency
        if !effectiveOnAC {
            batteryPowerW = -abs(batteryPowerW)
            if batteryCurrentA == 0 && abs(batteryPowerW) > 0.1 && batteryVoltageV > 1.0 {
                batteryCurrentA = batteryPowerW / batteryVoltageV
            }
        } else {
            // On AC: guard against telemetry lag falsely claiming hybrid discharge when current is 0.
            if !reading.isCharging && abs(batteryCurrentA) < 0.02 {
                if batteryPowerW < 0 {
                    // Unless SMC explicitly has no current sensor AND energy balance strongly proves deficit,
                    // zero out lagging negative telemetry to prevent false hybrid-discharge flicker.
                    let energyDeficit = preliminaryLoadW > adapterInputPowerW + 1.5
                    if hasExplicitCurrentReading || !energyDeficit {
                        batteryPowerW = 0
                    } else if batteryVoltageV > 1.0 {
                        batteryCurrentA = batteryPowerW / batteryVoltageV
                    }
                } else if batteryPowerW > 0 {
                    // On Apple Silicon, SMC PPBR often reports a ~0.5–0.8 W quiescent offset even
                    // when the charger is off (isCharging == false) and gas-gauge current is 0 A.
                    // Never classify residual positive PPBR as active charging in bypass/idle state.
                    batteryPowerW = 0
                }
            }

            // If both are active but disagree in sign due to sensor lag, anchor to physical current.
            if abs(batteryCurrentA) >= 0.03 && abs(batteryPowerW) >= 0.1 {
                if (batteryCurrentA > 0 && batteryPowerW < 0) || (batteryCurrentA < 0 && batteryPowerW > 0) {
                    batteryPowerW = batteryCurrentA > 0 ? abs(batteryPowerW) : -abs(batteryPowerW)
                }
            } else if batteryCurrentA == 0 && abs(batteryPowerW) > 0.25 && batteryVoltageV > 1.0 {
                // Synthesize current when only PPBR/power telemetry is present (e.g., B0AC unavailable).
                if reading.isCharging && batteryPowerW > 0 {
                    batteryCurrentA = batteryPowerW / batteryVoltageV
                }
            }
        }

        if abs(batteryPowerW) < 0.05 {
            batteryPowerW = 0
        }
        if abs(batteryCurrentA) < 0.005 {
            batteryCurrentA = 0
        }

        // 4. Total & Net System Load
        let totalSystemLoadW: Double = {
            // While the battery is idle the adapter feeds the whole system. `PSTR` trails `PDTR` by one
            // SMC update, so reading it here would show a load that disagrees with the input.
            if effectiveOnAC, smc.deliveryRateW != nil, adapterInputPowerW > 0.05,
               batteryPowerW == 0, batteryCurrentA == 0
            {
                return adapterInputPowerW
            }
            if let smcLoad = smc.systemTotalW, smcLoad > 0.05 {
                return smcLoad
            }
            if let telemetryLoadMW = reading.telemetrySystemLoadMW, telemetryLoadMW > 0 {
                return Double(telemetryLoadMW) / 1000.0
            }
            if !effectiveOnAC {
                return abs(batteryPowerW)
            }
            // Energy balance: AdapterIn = SystemLoad + BatteryCharge -> SystemLoad = AdapterIn - BatteryPower
            return max(0, adapterInputPowerW - batteryPowerW)
        }()

        let netSystemLoadW = max(0, totalSystemLoadW - totalOutboundPowerW)

        // 5. Flow Mode Resolution
        let flowMode = Self.resolveFlowMode(
            connectionPhase: connectionPhase,
            isExternalConnected: reading.isExternalConnected,
            isCharging: reading.isCharging,
            batteryPowerW: batteryPowerW,
            batteryCurrentA: batteryCurrentA,
            adapterInputPowerW: adapterInputPowerW
        )

        // 6. Battery Percent, Health, Charge Limit & Thermal
        let batteryPercent: Int = {
            if reading.maxCapacityPercent > 0 && reading.maxCapacityPercent != 100 {
                let scaled = (Double(reading.currentCapacityPercent) / Double(reading.maxCapacityPercent)) * 100.0
                return min(max(Int(scaled.rounded()), 0), 100)
            }
            return min(max(reading.currentCapacityPercent, 0), 100)
        }()

        let realHealthPercent: Double? = {
            guard let design = reading.designCapacityMAh, design > 0 else { return nil }
            guard let rawMax = reading.rawMaxCapacityMAh ?? reading.fullChargeCapacityMAh, rawMax > 0 else {
                return nil
            }
            let pct = (Double(rawMax) / Double(design)) * 100.0
            return min(max(pct, 0), 120.0)
        }()

        let macOSCapacityPercent: Int? = {
            guard let design = reading.designCapacityMAh, design > 0 else { return nil }
            guard let numerator = reading.nominalCapacityMAh
                ?? reading.rawMaxCapacityMAh
                ?? reading.fullChargeCapacityMAh,
                numerator > 0
            else {
                return nil
            }
            let pct = Int(((Double(numerator) / Double(design)) * 100.0).rounded())
            return min(max(pct, 0), 100)
        }()

        let health = BatteryHealthInfo(
            designCapacityMAh: reading.designCapacityMAh,
            rawMaxCapacityMAh: reading.rawMaxCapacityMAh ?? reading.fullChargeCapacityMAh,
            nominalCapacityMAh: reading.nominalCapacityMAh,
            currentChargeMAh: reading.currentChargeMAh,
            macOSCapacityPercent: macOSCapacityPercent,
            realHealthPercent: realHealthPercent,
            condition: reading.condition,
            cycleCount: reading.cycleCount ?? smc.cycleCount,
            designCycleCount: reading.designCycleCount,
            manufactureDate: reading.manufactureDate,
            batterySerial: reading.batterySerial,
            deviceName: reading.deviceName,
            lifetime: reading.lifetimeStats
        )

        let chargeLimit = chargeLimitProvider(reading.notChargingReason)
        let batteryTemperatureC = smc.batteryTemperatureC ?? reading.temperatureC

        // 7. Energy (Wh), Wall Power Estimate, Charging Hold Reason, System Breakdown & Physical Ports
        let nominalPackVoltageV: Double = {
            if let series = reading.cellTopology?.seriesCount, series > 0 {
                return Double(series) * 3.8
            }
            return 11.4
        }()
        let batteryRemainingWh = health.currentChargeMAh.map { Double($0) * nominalPackVoltageV / 1000.0 }
        let batteryDesignWh = health.designCapacityMAh.map { Double($0) * nominalPackVoltageV / 1000.0 }
        let batteryFullChargeWh = (health.rawMaxCapacityMAh ?? health.nominalCapacityMAh)
            .map { Double($0) * nominalPackVoltageV / 1000.0 }

        let wallPowerEstimateW: Double? = {
            guard connectionPhase != .onBattery, adapterInputPowerW > 0.05 else { return nil }
            if let loss = adapterEfficiencyLossW, loss >= 0 {
                return adapterInputPowerW + loss
            }
            if let wallMW = reading.telemetryWallEnergyEstimateMW, wallMW > 0 {
                let wallW = Double(wallMW) / 1000.0
                if wallW >= adapterInputPowerW {
                    return wallW
                }
            }
            return adapterInputPowerW
        }()

        let chargingHoldReason = Self.resolveChargingHoldReason(
            effectiveOnAC: effectiveOnAC,
            flowMode: flowMode,
            isFullyCharged: reading.isFullyCharged,
            batteryPercent: batteryPercent,
            chargeLimit: chargeLimit,
            notChargingReason: reading.notChargingReason,
            slowChargingReason: reading.slowChargingReason
        )

        let packagePowerW = smc.packagePowerW
        let displayPowerW = smc.displayPowerW
        let otherSystemW: Double? = {
            guard netSystemLoadW > 0, packagePowerW != nil || displayPowerW != nil else {
                return nil
            }
            return max(0, netSystemLoadW - (packagePowerW ?? 0) - (displayPowerW ?? 0))
        }()
        let systemBreakdown = SystemPowerBreakdown(
            packagePowerW: packagePowerW,
            displayPowerW: displayPowerW,
            otherSystemW: otherSystemW,
            cpuTemperatureC: smc.cpuTemperatureC,
            gpuTemperatureC: smc.gpuTemperatureC,
            thermalState: Self.mapThermalState(thermalState),
            fans: smc.fans
        )

        let physicalPorts = Self.resolvePhysicalPorts(
            portTopology: portTopology,
            connectionPhase: connectionPhase,
            activeAdapter: activeAdapter,
            standbyAdapters: standbyAdapters,
            outboundPorts: outboundPorts,
            adapterInputPowerW: adapterInputPowerW,
            adapterInputCurrentA: adapterInputCurrentA,
            adapterInputVoltageV: adapterInputVoltageV
        )

        // 8. Time Remaining Estimation
        let (timeRemainingMinutes, isTimeEstimateToFull) = resolveTimeRemaining(
            flowMode: flowMode,
            reading: reading,
            batteryPercent: batteryPercent,
            chargeLimitPercent: chargeLimit.limitPercent,
            isDrainingToLimit: Self.isDraining(flowMode: flowMode, percent: batteryPercent, to: chargeLimit),
            maxCapacityMAh: health.rawMaxCapacityMAh ?? health.nominalCapacityMAh ?? health.designCapacityMAh,
            batteryCurrentA: batteryCurrentA,
            batteryPowerW: batteryPowerW,
            batteryVoltageV: batteryVoltageV
        )

        return PowerSnapshot(
            timestamp: timestamp,
            isDataAvailable: true,
            telemetrySource: telemetrySource,
            connectionPhase: connectionPhase,
            flowMode: flowMode,
            batteryPercent: batteryPercent,
            rawStateOfCharge: reading.stateOfCharge,
            isExternalConnected: effectiveOnAC,
            isCharging: reading.isCharging && effectiveOnAC,
            isFullyCharged: reading.isFullyCharged,
            atCriticalLevel: reading.atCriticalLevel,
            isLowBatteryWarning: reading.isLowBatteryWarning,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            batteryCurrentA: batteryCurrentA,
            batteryVoltageV: batteryVoltageV,
            batteryPowerW: batteryPowerW,
            batteryTemperatureC: batteryTemperatureC,
            chargeLimitPercent: chargeLimit.limitPercent,
            chargeLimitSource: chargeLimit.source,
            timeRemainingMinutes: timeRemainingMinutes,
            isTimeEstimateToFull: isTimeEstimateToFull,
            totalSystemLoadW: totalSystemLoadW,
            netSystemLoadW: netSystemLoadW,
            adapterInputPowerW: adapterInputPowerW,
            adapterInputVoltageV: adapterInputVoltageV,
            adapterInputCurrentA: adapterInputCurrentA,
            adapterEfficiencyLossW: adapterEfficiencyLossW,
            activeAdapter: activeAdapter,
            standbyAdapters: standbyAdapters,
            outboundPorts: outboundPorts,
            totalOutboundPowerW: totalOutboundPowerW,
            totalOutboundCurrentA: totalOutboundCurrentA,
            health: health,
            cellTopology: reading.cellTopology,
            wallPowerEstimateW: wallPowerEstimateW,
            batteryRemainingWh: batteryRemainingWh,
            batteryDesignWh: batteryDesignWh,
            batteryFullChargeWh: batteryFullChargeWh,
            chargingHoldReason: chargingHoldReason,
            systemBreakdown: systemBreakdown,
            physicalPorts: physicalPorts
        )
    }

    // MARK: - Sign Unification & Flow Mode Helpers

    static func unifyIOKitBatteryPower(
        rawTelemetryW: Double,
        isExternalConnected: Bool,
        isCharging: Bool,
        batteryCurrentA: Double,
        adapterInputPowerW: Double,
        systemLoadW: Double
    ) -> Double {
        guard rawTelemetryW.isFinite, abs(rawTelemetryW) >= 0.05 else { return 0 }

        if !isExternalConnected {
            return -abs(rawTelemetryW)
        }

        if batteryCurrentA > 0.02 {
            return abs(rawTelemetryW)
        }
        if batteryCurrentA < -0.02 {
            return -abs(rawTelemetryW)
        }

        if isCharging {
            return abs(rawTelemetryW)
        }

        // External connected, not charging, and near-zero current:
        // Do not mislabel positive magnitude or telemetry lag as hybrid discharge.
        if rawTelemetryW < -0.5 && systemLoadW > adapterInputPowerW + 1.5 {
            return rawTelemetryW
        }
        return 0
    }

    /// A connected charger that is not feeding the Mac still reads a few tenths of a watt.
    static let idleAdapterPowerW = 1.0

    static func resolveFlowMode(
        connectionPhase: PowerConnectionPhase,
        isExternalConnected: Bool,
        isCharging: Bool,
        batteryPowerW: Double,
        batteryCurrentA: Double,
        adapterInputPowerW: Double
    ) -> PowerFlowMode {
        if connectionPhase == .connectingAC {
            return .connectingAC
        }
        if connectionPhase == .onBattery || !isExternalConnected {
            return .batteryOnly
        }

        // On AC:
        if batteryPowerW > 0.1 || batteryCurrentA > 0.02 {
            return .adapterCharging
        }
        // Require consistent negative battery power AND negative current to classify as hybrid discharge.
        if batteryPowerW < -0.25 && batteryCurrentA < -0.02 {
            return adapterInputPowerW < Self.idleAdapterPowerW ? .batteryWhilePluggedIn : .adapterBatteryHybrid
        }
        if isCharging && batteryPowerW >= 0 && batteryCurrentA >= 0 {
            return .adapterCharging
        }
        return .adapterBypass
    }

    // MARK: - Time Remaining Resolution

    private func resolveTimeRemaining(
        flowMode: PowerFlowMode,
        reading: SmartBatteryReading,
        batteryPercent: Int,
        chargeLimitPercent: Int,
        isDrainingToLimit: Bool,
        maxCapacityMAh: Int?,
        batteryCurrentA: Double,
        batteryPowerW: Double,
        batteryVoltageV: Double
    ) -> (minutes: Int?, isToFull: Bool) {
        switch flowMode {
        case .adapterCharging:
            let estimatorMinutes = timeEstimator.estimateMinutes(
                isCharging: true,
                batteryPercent: batteryPercent,
                chargeLimitPercent: chargeLimitPercent,
                currentChargeMAh: reading.currentChargeMAh,
                maxCapacityMAh: maxCapacityMAh,
                batteryCurrentA: batteryCurrentA,
                batteryPowerW: batteryPowerW,
                batteryVoltageV: batteryVoltageV
            )
            let osMinutes = BatteryTimeEstimator.sanitizedOSMinutes(reading.timeRemainingMinutes)
            if chargeLimitPercent < 100 {
                // OS estimate targets 100%; prefer estimator targeting the active charge limit.
                return (estimatorMinutes ?? osMinutes, true)
            }
            return (osMinutes ?? estimatorMinutes, true)

        case .batteryWhilePluggedIn where isDrainingToLimit:
            // Discharge stops at the limit, so a time to empty would be misleading.
            return (nil, false)

        case .batteryOnly, .adapterBatteryHybrid, .batteryWhilePluggedIn:
            let osMinutes = BatteryTimeEstimator.sanitizedOSMinutes(
                reading.timeRemainingMinutes ?? reading.avgTimeToEmptyMinutes
            )
            let estimatorMinutes = timeEstimator.estimateMinutes(
                isCharging: false,
                batteryPercent: batteryPercent,
                chargeLimitPercent: chargeLimitPercent,
                currentChargeMAh: reading.currentChargeMAh,
                maxCapacityMAh: maxCapacityMAh,
                batteryCurrentA: batteryCurrentA,
                batteryPowerW: batteryPowerW,
                batteryVoltageV: batteryVoltageV
            )
            return (osMinutes ?? estimatorMinutes, false)

        case .adapterBypass, .connectingAC, .unknown:
            return (nil, false)
        }
    }

    // MARK: - Thermal & Charging Hold

    static func mapThermalState(_ state: ProcessInfo.ThermalState) -> ThermalPressureLevel {
        switch state {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .nominal
        }
    }

    static func isDraining(
        flowMode: PowerFlowMode,
        percent: Int,
        to limit: BatteryChargeLimitInfo
    ) -> Bool {
        flowMode == .batteryWhilePluggedIn && limit.drainsToLimit && percent > limit.limitPercent
    }

    static func resolveChargingHoldReason(
        effectiveOnAC: Bool,
        flowMode: PowerFlowMode,
        isFullyCharged: Bool,
        batteryPercent: Int,
        chargeLimit: BatteryChargeLimitInfo,
        notChargingReason: Int?,
        slowChargingReason: Int?
    ) -> String? {
        guard effectiveOnAC else { return nil }

        if flowMode == .connectingAC {
            return nil
        }

        if flowMode == .adapterCharging {
            if let slow = slowChargingReason, slow != 0 {
                return "Slow Charging"
            }
            return nil
        }

        if isDraining(flowMode: flowMode, percent: batteryPercent, to: chargeLimit) {
            return "Draining to \(chargeLimit.limitPercent)%"
        }

        if flowMode != .batteryWhilePluggedIn && isFullyCharged && batteryPercent >= 100 {
            return "Fully Charged"
        }

        switch chargeLimit.source {
        case .alDente:
            return "Charge Limit (\(chargeLimit.limitPercent)% · AlDente)"
        case .optimizedCharging:
            return "Optimized Battery Charging"
        case .macOSSetting:
            return "Charge Limit (\(chargeLimit.limitPercent)%)"
        case .none:
            break
        }

        if let reason = notChargingReason, reason != 0 {
            if (reason & 0x0100_0000) != 0 || (reason & 0x0480) != 0 {
                return "Optimized Battery Charging"
            }
            if (reason & 0x0000_0004) != 0 || (reason & 0x0000_0020) != 0 {
                return "Thermal Protection"
            }
            if (reason & 0x0040_0000) != 0 {
                return "Fully Charged"
            }
            if (reason & 0x0000_0008) != 0 {
                return "Charging On Hold"
            }
        }

        if isFullyCharged || batteryPercent >= 100 {
            return "Fully Charged"
        }

        return nil
    }
}
