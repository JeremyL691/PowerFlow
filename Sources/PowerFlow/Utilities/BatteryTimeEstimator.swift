import Foundation

/// Smooths battery time-to-empty / time-to-full estimates using an exponential moving average (EMA)
/// on current draw and a Constant-Voltage (CV) taper model above 80% SoC when charging.
final class BatteryTimeEstimator: @unchecked Sendable {
    static let emaResetGapSeconds: TimeInterval = 10.0

    private let lock = NSLock()
    private let emaAlpha: Double
    private let maxEstimateMinutes: Int

    private var smoothedCurrentMA: Double?
    private var lastWasCharging: Bool?
    private var lastSampleTimestamp: Date?

    init(emaAlpha: Double = 0.25, maxEstimateMinutes: Int = 99 * 60) {
        self.emaAlpha = min(max(emaAlpha, 0.05), 1.0)
        self.maxEstimateMinutes = max(60, maxEstimateMinutes)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        smoothedCurrentMA = nil
        lastWasCharging = nil
        lastSampleTimestamp = nil
    }

    /// Filters invalid macOS / IOKit time-remaining sentinels (0, negative, 65535, absurdly high).
    static func sanitizedOSMinutes(_ rawMinutes: Int?, maxMinutes: Int = 99 * 60) -> Int? {
        guard let rawMinutes, rawMinutes > 0, rawMinutes < 65535, rawMinutes <= maxMinutes else {
            return nil
        }
        return rawMinutes
    }

    /// Estimates remaining minutes to target charge limit (when charging) or to empty (when discharging).
    /// Returns `nil` when idle, already at target charge limit, or telemetry lacks usable current/power.
    func estimateMinutes(
        isCharging: Bool,
        batteryPercent: Int,
        chargeLimitPercent: Int = 100,
        currentChargeMAh: Int?,
        maxCapacityMAh: Int?,
        batteryCurrentA: Double,
        batteryPowerW: Double,
        batteryVoltageV: Double,
        at now: Date? = nil
    ) -> Int? {
        lock.lock()
        defer { lock.unlock() }

        if let now, let previousTimestamp = lastSampleTimestamp {
            let elapsed = now.timeIntervalSince(previousTimestamp)
            if elapsed > Self.emaResetGapSeconds || elapsed < 0 {
                smoothedCurrentMA = nil
            }
        }

        if let previousMode = lastWasCharging, previousMode != isCharging {
            smoothedCurrentMA = nil
        }
        lastWasCharging = isCharging

        let clampedSoc = min(max(batteryPercent, 0), 100)
        let clampedLimit = min(max(chargeLimitPercent, 20), 100)

        let instantCurrentMA: Double
        if isCharging {
            guard clampedSoc < clampedLimit else { return nil }
            if batteryCurrentA > 0.05 {
                instantCurrentMA = batteryCurrentA * 1000.0
            } else if batteryPowerW > 0.5, batteryVoltageV > 1.0 {
                instantCurrentMA = (batteryPowerW / batteryVoltageV) * 1000.0
            } else {
                return nil
            }
        } else {
            guard clampedSoc > 0 else { return nil }
            if batteryCurrentA < -0.05 {
                instantCurrentMA = abs(batteryCurrentA) * 1000.0
            } else if batteryPowerW < -0.5, batteryVoltageV > 1.0 {
                instantCurrentMA = (abs(batteryPowerW) / batteryVoltageV) * 1000.0
            } else {
                return nil
            }
        }

        guard instantCurrentMA.isFinite, instantCurrentMA > 50.0 else { return nil }

        let currentMA: Double
        if let previous = smoothedCurrentMA {
            currentMA = emaAlpha * instantCurrentMA + (1.0 - emaAlpha) * previous
        } else {
            currentMA = instantCurrentMA
        }
        smoothedCurrentMA = currentMA
        if let now {
            lastSampleTimestamp = now
        }

        let effectiveMaxMAh: Double
        if let maxCapacityMAh, maxCapacityMAh > 100 {
            effectiveMaxMAh = Double(maxCapacityMAh)
        } else {
            effectiveMaxMAh = 5000.0
        }

        let effectiveCurrentMAh: Double
        if let currentChargeMAh, currentChargeMAh >= 0 {
            effectiveCurrentMAh = min(Double(currentChargeMAh), effectiveMaxMAh)
        } else {
            effectiveCurrentMAh = effectiveMaxMAh * (Double(clampedSoc) / 100.0)
        }

        let hours: Double
        if isCharging {
            let targetFraction = Double(clampedLimit) / 100.0
            let targetMAh = effectiveMaxMAh * targetFraction
            let neededMAh = targetMAh - effectiveCurrentMAh
            guard neededMAh > 1.0 else { return nil }

            let cvThresholdFraction = 0.80
            let cvThresholdMAh = effectiveMaxMAh * cvThresholdFraction
            let currentFraction = effectiveCurrentMAh / effectiveMaxMAh

            if effectiveCurrentMAh >= cvThresholdMAh {
                // Already in CV taper zone: current is actively tapering down toward full.
                let remainingSpan = max(0.0, targetFraction - currentFraction)
                let cvSlopeMultiplier = 1.0 + 0.55 * (remainingSpan / 0.20)
                hours = (neededMAh * cvSlopeMultiplier) / currentMA
            } else if targetMAh > cvThresholdMAh {
                // Crosses CC -> CV boundary at 80% SoC.
                let ccMAh = cvThresholdMAh - effectiveCurrentMAh
                let cvMAh = targetMAh - cvThresholdMAh
                let cvDepth = min(1.0, max(0.0, (targetFraction - cvThresholdFraction) / 0.20))
                let cvMultiplier = 1.0 + 0.85 * cvDepth
                hours = (ccMAh + cvMAh * cvMultiplier) / currentMA
            } else {
                // Pure CC charging (e.g., target <= 80% charge limit).
                hours = neededMAh / currentMA
            }
        } else {
            let remainingMAh = max(0.0, effectiveCurrentMAh)
            hours = remainingMAh / currentMA
        }

        guard hours.isFinite, hours > 0 else { return nil }
        let rawMinutes = (hours * 60.0).rounded()
        let clampedMinutes = min(max(rawMinutes, 1.0), Double(maxEstimateMinutes))
        return Int(clampedMinutes)
    }

    func estimate(
        isCharging: Bool,
        batteryPercent: Int,
        chargeLimitPercent: Int = 100,
        currentChargeMAh: Int?,
        maxCapacityMAh: Int?,
        batteryCurrentA: Double,
        batteryPowerW: Double,
        batteryVoltageV: Double,
        at now: Date? = nil
    ) -> (minutes: Int, isToFull: Bool)? {
        guard let minutes = estimateMinutes(
            isCharging: isCharging,
            batteryPercent: batteryPercent,
            chargeLimitPercent: chargeLimitPercent,
            currentChargeMAh: currentChargeMAh,
            maxCapacityMAh: maxCapacityMAh,
            batteryCurrentA: batteryCurrentA,
            batteryPowerW: batteryPowerW,
            batteryVoltageV: batteryVoltageV,
            at: now
        ) else {
            return nil
        }
        return (minutes: minutes, isToFull: isCharging)
    }
}
