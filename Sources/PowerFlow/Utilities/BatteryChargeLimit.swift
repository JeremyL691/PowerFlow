import AppKit
import Foundation

struct BatteryChargeLimitInfo: Sendable, Equatable, Hashable {
    let limitPercent: Int
    let source: BatteryChargeLimitSource
    /// The battery is deliberately run down to the limit while a charger is connected.
    var drainsToLimit = false

    static let unlimited = BatteryChargeLimitInfo(limitPercent: 100, source: .none)
}

private final class ExternalLimiterCache: @unchecked Sendable {
    static let shared = ExternalLimiterCache()
    static let candidateBundleIDs = [
        "com.apphousekitchen.aldente-pro",
        "com.davidwernhart.Helper",
        "com.apphousekitchen.aldente-free"
    ]
    private static let candidateSet = Set(candidateBundleIDs)

    private let lock = NSLock()
    private var isMonitoring = false
    private var runningBundleIDs: Set<String> = []
    private var cachedSuites: [String: UserDefaults] = [:]
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    @MainActor
    func startMonitoringIfNeeded() {
        lock.lock()
        let alreadyMonitoring = isMonitoring
        if !alreadyMonitoring {
            isMonitoring = true
        }
        lock.unlock()

        guard !alreadyMonitoring else { return }

        seedRunningAppsOnMainActor()

        let center = NSWorkspace.shared.notificationCenter
        let launchToken = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier,
                  Self.candidateSet.contains(bundleID)
            else {
                return
            }
            self?.markRunning(bundleID)
        }

        let terminateToken = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier,
                  Self.candidateSet.contains(bundleID)
            else {
                return
            }
            MainActor.assumeIsolated {
                self?.seedRunningAppsOnMainActor()
            }
        }

        lock.lock()
        launchObserver = launchToken
        terminateObserver = terminateToken
        lock.unlock()
    }

    @MainActor
    private func seedRunningAppsOnMainActor() {
        let running = Set(
            NSWorkspace.shared.runningApplications.compactMap { app -> String? in
                guard let id = app.bundleIdentifier, Self.candidateSet.contains(id) else {
                    return nil
                }
                return id
            }
        )
        lock.lock()
        runningBundleIDs = running
        lock.unlock()
    }

    private func markRunning(_ bundleID: String) {
        lock.lock()
        runningBundleIDs.insert(bundleID)
        lock.unlock()
    }

    func isRunning(_ bundleID: String) -> Bool {
        lock.lock()
        let monitoring = isMonitoring
        let cached = runningBundleIDs.contains(bundleID)
        lock.unlock()
        if monitoring {
            return cached
        }
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
            }
        }
        return cached
    }

    func suite(for bundleID: String) -> UserDefaults? {
        lock.lock()
        if let existing = cachedSuites[bundleID] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        guard let created = UserDefaults(suiteName: bundleID) else {
            return nil
        }

        lock.lock()
        if let existing = cachedSuites[bundleID] {
            lock.unlock()
            return existing
        }
        cachedSuites[bundleID] = created
        lock.unlock()
        return created
    }
}

enum BatteryChargeLimitResolver {
    /// AppleSmartBattery `NotChargingReason` bits observed on Apple Silicon macOS.
    private static let optimizedChargingMask: Int = 0x0480
    private static let optimizedChargingHoldPercent = 80

    /// Wires `NSWorkspace` launch/terminate observers on `@MainActor` and seeds the running AlDente set
    /// so background telemetry polls never call AppKit `NSRunningApplication` off the main actor.
    @MainActor
    static func startMonitoringExternalLimiters() {
        ExternalLimiterCache.shared.startMonitoringIfNeeded()
    }

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
            ExternalLimiterCache.shared.isRunning(bundleID)
        },
        defaults: (String) -> UserDefaults? = { bundleID in
            ExternalLimiterCache.shared.suite(for: bundleID)
        }
    ) -> Int? {
        for bundleID in ExternalLimiterCache.candidateBundleIDs where isRunning(bundleID) {
            guard let suite = defaults(bundleID) else { continue }
            let rawValue = suite.object(forKey: "chargeVal")
            let parsedLimit: Int?
            if let intVal = rawValue as? Int {
                parsedLimit = intVal
            } else if let doubleVal = rawValue as? Double,
                      doubleVal.isFinite,
                      (20.0...99.0).contains(doubleVal.rounded())
            {
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
