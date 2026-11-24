import Foundation

// MARK: - SMC Power Sample

/// Live per-port USB-C output sampled from the SMC (`D<n>JI` current, `D<n>JV` voltage).
struct SMCPortOutput: Sendable, Equatable {
    let currentA: Double
    let voltageV: Double
}

struct SMCPowerSample: Sendable, Equatable {
    let deliveryRateW: Double?
    let systemTotalW: Double?
    let batteryRateW: Double?
    let adapterInputVoltageV: Double?
    let adapterInputCurrentA: Double?
    let batteryVoltageV: Double?
    let batteryCurrentA: Double?
    let batteryTemperatureC: Double?
    let cycleCount: Int?
    let packagePowerW: Double?
    let displayPowerW: Double?
    let cpuTemperatureC: Double?
    let gpuTemperatureC: Double?
    let fans: [FanReading]
    let portOutputs: [Int: SMCPortOutput]

    init(
        deliveryRateW: Double? = nil,
        systemTotalW: Double? = nil,
        batteryRateW: Double? = nil,
        adapterInputVoltageV: Double? = nil,
        adapterInputCurrentA: Double? = nil,
        batteryVoltageV: Double? = nil,
        batteryCurrentA: Double? = nil,
        batteryTemperatureC: Double? = nil,
        cycleCount: Int? = nil,
        packagePowerW: Double? = nil,
        displayPowerW: Double? = nil,
        cpuTemperatureC: Double? = nil,
        gpuTemperatureC: Double? = nil,
        fans: [FanReading] = [],
        portOutputs: [Int: SMCPortOutput] = [:]
    ) {
        self.deliveryRateW = deliveryRateW
        self.systemTotalW = systemTotalW
        self.batteryRateW = batteryRateW
        self.adapterInputVoltageV = adapterInputVoltageV
        self.adapterInputCurrentA = adapterInputCurrentA
        self.batteryVoltageV = batteryVoltageV
        self.batteryCurrentA = batteryCurrentA
        self.batteryTemperatureC = batteryTemperatureC
        self.cycleCount = cycleCount
        self.packagePowerW = packagePowerW
        self.displayPowerW = displayPowerW
        self.cpuTemperatureC = cpuTemperatureC
        self.gpuTemperatureC = gpuTemperatureC
        self.fans = fans
        self.portOutputs = portOutputs
    }

    static let empty = SMCPowerSample()

    var hasAnyPowerReading: Bool {
        deliveryRateW != nil || systemTotalW != nil || batteryRateW != nil
    }
}

// MARK: - SMC Reader

final class SMCReader: @unchecked Sendable {
    private enum Key {
        static let deliveryRate = "PDTR"
        static let systemTotal = "PSTR"
        static let batteryRate = "PPBR"
        static let adapterVoltage = "VD0R"
        static let adapterCurrent = "ID0R"
        static let batteryCurrent = "B0AC"
        static let batteryVoltage = "B0AV"
        static let batteryVoltageFallback = "SBAV"
        static let batteryTemperature = "TB0T"
        static let cycleCount = "B0CT"
        static let displayPower = "PDBR"
        static let fanCount = "FNum"

        static let packagePowerCandidates = ["PHPC", "PCPC", "PCPT", "PC0R", "PCPR"]
        static let cpuTemperatureCandidates = [
            "Tp09", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b", "Tp0T",
            "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Te05", "Te0L", "Te0P", "Te0S"
        ]
        static let gpuTemperatureCandidates = [
            "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg04", "Tg0C", "Tg0K", "Tg0S", "Tg0f", "Tg0j"
        ]
    }

    private enum Bounds {
        static let maxPowerW: Double = 400.0
        static let maxVoltageV: Double = 60.0
        static let maxCurrentA: Double = 30.0
        static let minTempC: Double = 0.0
        static let maxTempC: Double = 100.0
        static let minDieTempC: Double = 5.0
        static let maxDieTempC: Double = 130.0
        static let maxCycleCount: Int = 10_000
        static let maxFanCount: Int = 16
        static let maxFanRPM: Double = 25_000.0
        static let maxPortCurrentA: Double = 10.0
        static let portNumbers: ClosedRange<Int> = 1...4
    }

    private let keyReader: SMCKeyReading
    private let useLittleEndianBatteryKeys: Bool
    private let cacheLock = NSLock()
    private var cachedPackagePowerKey: String?
    private var cachedFanCount: Int?
    private var cachedFanMaxRPM: [Int: Double] = [:]

    init(keyReader: SMCKeyReading? = nil, useLittleEndianBatteryKeys: Bool? = nil) {
        self.keyReader = keyReader ?? SMCConnection()
        if let explicit = useLittleEndianBatteryKeys {
            self.useLittleEndianBatteryKeys = explicit
        } else {
            #if arch(arm64)
            self.useLittleEndianBatteryKeys = (keyReader == nil)
            #else
            self.useLittleEndianBatteryKeys = false
            #endif
        }
    }

    func readSample(full: Bool) -> SMCPowerSample {
        let deliveryRateW = readSanitizedPower(Key.deliveryRate, allowNegative: false)
        let systemTotalW = readSanitizedPower(Key.systemTotal, allowNegative: false)
        let batteryRateW = readSanitizedPower(Key.batteryRate, allowNegative: true)

        guard full else {
            return SMCPowerSample(
                deliveryRateW: deliveryRateW,
                systemTotalW: systemTotalW,
                batteryRateW: batteryRateW
            )
        }

        let adapterInputVoltageV = readSanitizedVoltage(Key.adapterVoltage, isBatteryKey: false)
        let adapterInputCurrentA = readSanitizedCurrent(Key.adapterCurrent, allowNegative: false, isBatteryKey: false)
        let batteryVoltageV = readSanitizedVoltage(Key.batteryVoltageFallback, isBatteryKey: false)
            ?? readSanitizedVoltage(Key.batteryVoltage, isBatteryKey: true)
        let batteryCurrentA = readSanitizedCurrent(Key.batteryCurrent, allowNegative: true, isBatteryKey: true)
        let batteryTemperatureC = readSanitizedTemperature(Key.batteryTemperature)
        let cycleCount = readSanitizedCycleCount(Key.cycleCount)
        let packagePowerW = readPackagePower()
        let displayPowerW = readSanitizedPower(Key.displayPower, allowNegative: false)
        let cpuTemperatureC = readMaxDieTemperature(candidates: Key.cpuTemperatureCandidates)
        let gpuTemperatureC = readMaxDieTemperature(candidates: Key.gpuTemperatureCandidates)
        let fans = readFans()
        let portOutputs = readPortOutputs()

        return SMCPowerSample(
            deliveryRateW: deliveryRateW,
            systemTotalW: systemTotalW,
            batteryRateW: batteryRateW,
            adapterInputVoltageV: adapterInputVoltageV,
            adapterInputCurrentA: adapterInputCurrentA,
            batteryVoltageV: batteryVoltageV,
            batteryCurrentA: batteryCurrentA,
            batteryTemperatureC: batteryTemperatureC,
            cycleCount: cycleCount,
            packagePowerW: packagePowerW,
            displayPowerW: displayPowerW,
            cpuTemperatureC: cpuTemperatureC,
            gpuTemperatureC: gpuTemperatureC,
            fans: fans,
            portOutputs: portOutputs
        )
    }

    // MARK: - Dynamic Cached Discovery Helpers

    /// Pins the first package power key that yields a valid value. Until then every
    /// candidate is probed on each call. Once pinned, only that key is read.
    private func readPackagePower() -> Double? {
        cacheLock.lock()
        let pinnedKey = cachedPackagePowerKey
        cacheLock.unlock()

        if let pinnedKey {
            return readSanitizedPower(pinnedKey, allowNegative: false)
        }

        for candidate in Key.packagePowerCandidates {
            if let value = readSanitizedPower(candidate, allowNegative: false) {
                cacheLock.lock()
                cachedPackagePowerKey = candidate
                cacheLock.unlock()
                return value
            }
        }
        return nil
    }

    /// Reads every candidate on each full sample and returns the hottest valid value.
    /// Non-existent keys are cheap because SMCConnection caches their absence.
    private func readMaxDieTemperature(candidates: [String]) -> Double? {
        var maxTemp: Double?
        for candidate in candidates {
            if let temp = readSanitizedDieTemperature(candidate) {
                maxTemp = max(maxTemp ?? temp, temp)
            }
        }
        return maxTemp
    }

    private func readFans() -> [FanReading] {
        cacheLock.lock()
        let knownCount = cachedFanCount
        cacheLock.unlock()

        let fanCount: Int
        if let knownCount {
            fanCount = knownCount
        } else {
            // Only a valid FNum read is cached. A failed read retries on the next sample.
            guard let raw = keyReader.readKey(Key.fanCount)?.floatValue(),
                  raw.isFinite,
                  raw >= 0,
                  raw <= Double(Bounds.maxFanCount)
            else {
                return []
            }
            let discovered = Int(raw.rounded())
            cacheLock.lock()
            cachedFanCount = discovered
            cacheLock.unlock()
            fanCount = discovered
        }

        guard fanCount > 0 else { return [] }

        var readings: [FanReading] = []
        readings.reserveCapacity(fanCount)

        for index in 0..<fanCount {
            guard let rpm = readSanitizedFanRPM("F\(index)Ac") else { continue }

            cacheLock.lock()
            var maxRPM = cachedFanMaxRPM[index]
            cacheLock.unlock()

            if maxRPM == nil {
                if let discoveredMax = readSanitizedFanRPM("F\(index)Mx"), discoveredMax > 0 {
                    cacheLock.lock()
                    cachedFanMaxRPM[index] = discoveredMax
                    cacheLock.unlock()
                    maxRPM = discoveredMax
                }
            }

            readings.append(
                FanReading(
                    id: index,
                    index: index,
                    rpm: rpm,
                    maxRpm: maxRPM
                )
            )
        }

        return readings
    }

    /// Live USB-C output per port. A port is included only when both keys are valid.
    private func readPortOutputs() -> [Int: SMCPortOutput] {
        var outputs: [Int: SMCPortOutput] = [:]
        for port in Bounds.portNumbers {
            guard let currentA = readSanitizedPortValue("D\(port)JI", upperBound: Bounds.maxPortCurrentA),
                  let voltageV = readSanitizedPortValue("D\(port)JV", upperBound: Bounds.maxVoltageV)
            else {
                continue
            }
            outputs[port] = SMCPortOutput(currentA: currentA, voltageV: voltageV)
        }
        return outputs
    }

    private func readSanitizedPortValue(_ key: String, upperBound: Double) -> Double? {
        guard let value = keyReader.readKey(key)?.floatValue(), value.isFinite else {
            return nil
        }
        guard value >= -0.05, value <= upperBound else { return nil }
        return max(0.0, value)
    }

    private func readSanitizedDieTemperature(_ key: String) -> Double? {
        guard let value = keyReader.readKey(key)?.floatValue(),
              value.isFinite,
              value >= Bounds.minDieTempC,
              value <= Bounds.maxDieTempC
        else {
            return nil
        }
        return value
    }

    private func readSanitizedFanRPM(_ key: String) -> Double? {
        guard let value = keyReader.readKey(key)?.floatValue(),
              value.isFinite,
              value >= -1.0,
              value <= Bounds.maxFanRPM
        else {
            return nil
        }
        return max(0.0, value)
    }

    // MARK: - Sanitizers

    private func decodeNumeric(_ value: SMCValue, isBatteryKey: Bool) -> Double? {
        if isBatteryKey && useLittleEndianBatteryKeys {
            return value.littleEndianNumericValue()
        }
        return value.floatValue()
    }

    private func readSanitizedPower(_ key: String, allowNegative: Bool) -> Double? {
        guard let value = keyReader.readKey(key)?.floatValue(), value.isFinite else {
            return nil
        }
        guard abs(value) <= Bounds.maxPowerW else { return nil }
        if !allowNegative {
            if value < -0.5 { return nil }
            return max(0.0, value)
        }
        return value
    }

    private func readSanitizedVoltage(_ key: String, isBatteryKey: Bool) -> Double? {
        guard let smcValue = keyReader.readKey(key),
              let raw = decodeNumeric(smcValue, isBatteryKey: isBatteryKey),
              raw.isFinite
        else {
            return nil
        }
        // Integer SMC voltage keys (e.g. ui16 B0AV) report millivolts (e.g. 13104 mV).
        let volts: Double
        if Self.isIntegerType(smcValue.dataType) && raw > Bounds.maxVoltageV {
            volts = raw / 1000.0
        } else {
            volts = raw
        }
        guard volts >= 0.0, volts <= Bounds.maxVoltageV else { return nil }
        return volts
    }

    private func readSanitizedCurrent(_ key: String, allowNegative: Bool, isBatteryKey: Bool) -> Double? {
        guard let smcValue = keyReader.readKey(key),
              let raw = decodeNumeric(smcValue, isBatteryKey: isBatteryKey),
              raw.isFinite
        else {
            return nil
        }
        // Integer SMC current keys (e.g. si16 B0AC) report milliamps (e.g. -1850 mA).
        let amps: Double
        if Self.isIntegerType(smcValue.dataType) {
            amps = raw / 1000.0
        } else {
            amps = raw
        }
        guard abs(amps) <= Bounds.maxCurrentA else { return nil }
        if !allowNegative {
            if amps < -0.05 { return nil }
            return max(0.0, amps)
        }
        return amps
    }

    private func readSanitizedTemperature(_ key: String) -> Double? {
        guard let value = keyReader.readKey(key)?.floatValue(),
              value.isFinite,
              value >= Bounds.minTempC,
              value <= Bounds.maxTempC
        else {
            return nil
        }
        return value
    }

    private func readSanitizedCycleCount(_ key: String) -> Int? {
        guard let smcValue = keyReader.readKey(key),
              let value = decodeNumeric(smcValue, isBatteryKey: true),
              value.isFinite,
              value >= 0,
              value <= Double(Bounds.maxCycleCount)
        else {
            return nil
        }
        return Int(value.rounded())
    }

    private static func isIntegerType(_ dataType: String) -> Bool {
        switch dataType.trimmingCharacters(in: .whitespaces) {
        case "ui8", "si8", "ui16", "si16", "ui32", "si32", "ui64", "si64":
            return true
        default:
            return false
        }
    }
}
