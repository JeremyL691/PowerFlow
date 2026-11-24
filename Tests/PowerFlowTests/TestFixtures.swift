import XCTest
@testable import PowerFlow

extension XCTestCase {
    func makeReading(
        currentCapacityPercent: Int = 80,
        maxCapacityPercent: Int = 100,
        stateOfCharge: Int? = 80,
        dailyMaxSoc: Int? = nil,
        isExternalConnected: Bool = true,
        isCharging: Bool = false,
        isFullyCharged: Bool = false,
        atCriticalLevel: Bool = false,
        isLowBatteryWarning: Bool = false,
        notChargingReason: Int? = nil,
        timeRemainingMinutes: Int? = nil,
        avgTimeToEmptyMinutes: Int? = nil,
        voltageMV: Int = 13_100,
        instantAmperageMA: Int = 0,
        amperageMA: Int = 0,
        temperatureC: Double? = 37.7,
        telemetrySystemPowerInMW: Int? = nil,
        telemetrySystemLoadMW: Int? = nil,
        telemetryBatteryPowerMW: Int? = nil,
        telemetrySystemVoltageInMV: Int? = nil,
        telemetrySystemCurrentInMA: Int? = nil,
        telemetryAdapterEfficiencyLossMW: Int? = nil,
        telemetryWallEnergyEstimateMW: Int? = nil,
        activeAdapter: RawAdapterEntry? = nil,
        rawAdapters: [RawAdapterEntry] = [],
        powerOutDetails: [RawPowerOutEntry] = [],
        fedDetails: [RawFedPortEntry] = [],
        designCapacityMAh: Int? = 6_249,
        rawMaxCapacityMAh: Int? = 6_132,
        fullChargeCapacityMAh: Int? = 6_132,
        nominalCapacityMAh: Int? = 6_284,
        currentChargeMAh: Int? = 5_906,
        cycleCount: Int? = 35,
        designCycleCount: Int? = 1_000,
        condition: BatteryCondition = .normal,
        lifetimeStats: BatteryLifetimeStats? = nil,
        cellTopology: BatteryCellTopology? = nil
    ) -> SmartBatteryReading {
        SmartBatteryReading(
            currentCapacityPercent: currentCapacityPercent,
            maxCapacityPercent: maxCapacityPercent,
            stateOfCharge: stateOfCharge,
            dailyMinSoc: nil,
            dailyMaxSoc: dailyMaxSoc,
            isExternalConnected: isExternalConnected,
            isCharging: isCharging,
            isFullyCharged: isFullyCharged,
            atCriticalLevel: atCriticalLevel,
            isLowBatteryWarning: isLowBatteryWarning,
            notChargingReason: notChargingReason,
            slowChargingReason: nil,
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
            manufactureDate: "2024-06-01",
            batterySerial: "BATT0000002",
            deviceName: "bq40z651",
            lifetimeStats: lifetimeStats,
            cellTopology: cellTopology
        )
    }

    func makeIsolatedResolver(
        chargeLimit: BatteryChargeLimitInfo = .unlimited
    ) -> PowerFlowResolver {
        let calibrator = SMCPolarityCalibrator(userDefaults: nil, modelIdentifier: "TestMac")
        return PowerFlowResolver(
            polarityCalibrator: calibrator,
            timeEstimator: BatteryTimeEstimator(),
            chargeLimitProvider: { reason in
                if chargeLimit != .unlimited {
                    return chargeLimit
                }
                return BatteryChargeLimitResolver.resolve(notChargingReason: reason)
            }
        )
    }
}
