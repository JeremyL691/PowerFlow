import Darwin
import Foundation

enum SMCBatteryPowerPolarity: String, Sendable, Equatable, Codable {
    /// Positive PPBR = charging, negative PPBR = discharging.
    case normal
    /// Negative PPBR = charging, positive PPBR = discharging.
    case inverted
}

/// Thread-safe auto-calibrator for SMC `PPBR` sign convention, optionally persisted per Mac model.
final class SMCPolarityCalibrator: @unchecked Sendable {
    private let lock = NSLock()
    private let userDefaults: UserDefaults?
    private let storageKey: String
    private var cachedPolarity: SMCBatteryPowerPolarity?

    init(
        userDefaults: UserDefaults? = .standard,
        modelIdentifier: String? = nil
    ) {
        self.userDefaults = userDefaults
        let model = modelIdentifier ?? Self.currentHardwareModel()
        self.storageKey = "com.powerflow.smc.ppbrPolarity.\(model)"
        if let raw = userDefaults?.string(forKey: self.storageKey),
           let stored = SMCBatteryPowerPolarity(rawValue: raw)
        {
            self.cachedPolarity = stored
        } else {
            self.cachedPolarity = nil
        }
    }

    var currentPolarity: SMCBatteryPowerPolarity? {
        lock.lock()
        defer { lock.unlock() }
        return cachedPolarity
    }

    /// Calibrates and normalizes `PPBR` into the unified sign convention:
    /// `> 0` charging, `< 0` discharging.
    func normalizeBatteryPower(
        rawPPBR: Double,
        isExternalConnected: Bool,
        isCharging: Bool
    ) -> Double {
        guard rawPPBR.isFinite else { return 0 }

        lock.lock()
        defer { lock.unlock() }

        let magnitude = abs(rawPPBR)
        if magnitude >= 2.0 {
            var observed: SMCBatteryPowerPolarity?
            if !isExternalConnected {
                // Unplugged battery can only discharge.
                observed = rawPPBR < 0 ? .normal : .inverted
            } else if isCharging {
                // Actively charging battery can only absorb power.
                observed = rawPPBR > 0 ? .normal : .inverted
            }

            if let observed, observed != cachedPolarity {
                cachedPolarity = observed
                userDefaults?.set(observed.rawValue, forKey: storageKey)
            }
        }

        let effectivePolarity = cachedPolarity ?? .normal
        let normalized = effectivePolarity == .inverted ? -rawPPBR : rawPPBR
        return abs(normalized) < 0.05 ? 0 : normalized
    }

    static func currentHardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else {
            return "unknown"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
            return "unknown"
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
