import AppKit
import Foundation

struct BatteryChargeLimitInfo: Sendable, Equatable, Hashable {
    let limitPercent: Int
    let source: BatteryChargeLimitSource
    /// The battery is deliberately run down to the limit while a charger is connected.
    var drainsToLimit = false

    static let unlimited = BatteryChargeLimitInfo(limitPercent: 100, source: .none)
}

enum BatteryChargeLimitResolver {
    /// AppleSmartBattery `NotChargingReason` bits observed on Apple Silicon macOS.
    private static let optimizedChargingMask: Int = 0x0480
    private static let optimizedChargingHoldPercent = 80

    /// Pure, deterministic charge-limit resolver.
    ///
    /// Only explicit limits count. `DailyMaxSoc` is deliberately not an input: it is the highest
    /// charge reached today, not a configured ceiling.
    static func resolve(
        notChargingReason: Int?,
        alDenteLimit: Int? = nil,
        systemPolicy: SystemChargePolicy? = nil
    ) -> BatteryChargeLimitInfo {
        if let alDenteLimit, (20...99).contains(alDenteLimit) {
            return BatteryChargeLimitInfo(limitPercent: alDenteLimit, source: .alDente)
        }

        if let systemPolicy {
            return BatteryChargeLimitInfo(
                limitPercent: systemPolicy.limitPercent,
                source: systemPolicy.isManual ? .macOSSetting : .optimizedCharging,
                drainsToLimit: systemPolicy.drainsToLimit
            )
        }

        if ((notChargingReason ?? 0) & optimizedChargingMask) != 0 {
            return BatteryChargeLimitInfo(
                limitPercent: optimizedChargingHoldPercent,
                source: .optimizedCharging
            )
        }

        return .unlimited
    }

    /// Read-only convenience wrapper that adds the limit macOS enforces and, while AlDente is running,
    /// its configured limit. Never spawns subprocesses or writes defaults.
    static func resolveWithSystemDefaults(notChargingReason: Int?) -> BatteryChargeLimitInfo {
        resolve(
            notChargingReason: notChargingReason,
            alDenteLimit: readAlDenteChargeLimit(),
            systemPolicy: SystemChargePolicyReader.shared.currentPolicy()
        )
    }

    /// AlDente only enforces its limit while it runs, so preferences left behind by an
    /// uninstalled or closed copy are ignored.
    static func readAlDenteChargeLimit(
        isRunning: (String) -> Bool = { bundleID in
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        },
        defaults: (String) -> UserDefaults? = { UserDefaults(suiteName: $0) }
    ) -> Int? {
        let candidateBundleIDs = [
            "com.apphousekitchen.aldente-pro",
            "com.davidwernhart.Helper",
            "com.apphousekitchen.aldente-free"
        ]

        for bundleID in candidateBundleIDs where isRunning(bundleID) {
            guard let suite = defaults(bundleID) else { continue }
            let rawValue = suite.object(forKey: "chargeVal")
            let parsedLimit: Int?
            if let intVal = rawValue as? Int {
                parsedLimit = intVal
            } else if let doubleVal = rawValue as? Double {
                parsedLimit = Int(doubleVal.rounded())
            } else {
                parsedLimit = nil
            }
            guard let limit = parsedLimit, (20...99).contains(limit) else { continue }
            if let enabled = suite.object(forKey: "enableChargeLimiter") as? Bool, !enabled {
                continue
            }
            return limit
        }

        return nil
    }
}
