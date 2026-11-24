import Foundation

/// A charge ceiling macOS itself is enforcing.
struct SystemChargePolicy: Equatable, Sendable {
    let limitPercent: Int
    /// The battery is run down to the limit even while a charger is connected.
    let drainsToLimit: Bool
    /// Set by the user in System Settings, as opposed to chosen by Optimized Charging.
    let isManual: Bool
}

/// Reads the charging policies powerd publishes for the current boot session.
final class SystemChargePolicyReader: @unchecked Sendable {
    static let shared = SystemChargePolicyReader()

    private static let manualReason = "manualChargeLimit"

    private let url: URL
    private let bootSession: String?
    private let lock = NSLock()
    private var cachedModificationDate: Date?
    private var cachedPolicy: SystemChargePolicy?

    init(
        url: URL = URL(fileURLWithPath: "/Library/Preferences/com.apple.powerd.charging.plist"),
        bootSession: String? = SystemChargePolicyReader.currentBootSession()
    ) {
        self.url = url
        self.bootSession = bootSession
    }

    /// The strictest active policy, re-read only when powerd rewrites the file.
    func currentPolicy() -> SystemChargePolicy? {
        lock.lock()
        defer { lock.unlock() }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let modified = attributes?[.modificationDate] as? Date else {
            cachedModificationDate = nil
            cachedPolicy = nil
            return nil
        }
        if modified != cachedModificationDate {
            cachedModificationDate = modified
            cachedPolicy = (try? Data(contentsOf: url)).flatMap {
                Self.parse($0, bootSession: bootSession)
            }
        }
        return cachedPolicy
    }

    static func parse(_ data: Data, bootSession: String?) -> SystemChargePolicy? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let archive = root["policies"] as? Data
        else {
            return nil
        }
        // Policies written during an earlier boot are no longer in force.
        if let bootSession,
           let written = root["bootSessionUUID"] as? String,
           written.caseInsensitiveCompare(bootSession) != .orderedSame
        {
            return nil
        }
        return decodePolicies(archive)
            .filter { !$0.terminated && (20...99).contains($0.limit) }
            .min { $0.limit < $1.limit }
            .map {
                SystemChargePolicy(
                    limitPercent: $0.limit,
                    drainsToLimit: $0.drain,
                    isManual: $0.reason == manualReason
                )
            }
    }

    private static func decodePolicies(_ archive: Data) -> [ArchivedChargePolicy] {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archive) else { return [] }
        defer { unarchiver.finishDecoding() }
        unarchiver.requiresSecureCoding = true
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        unarchiver.setClass(ArchivedChargePolicy.self, forClassName: ArchivedChargePolicy.archivedName)
        let decoded = unarchiver.decodeObject(
            of: [NSArray.self, ArchivedChargePolicy.self],
            forKey: NSKeyedArchiveRootObjectKey
        )
        return decoded as? [ArchivedChargePolicy] ?? []
    }

    static func currentBootSession() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }
}

/// Stand-in for powerd's archived policy class.
final class ArchivedChargePolicy: NSObject, NSSecureCoding {
    static let archivedName = "ChargeCtrlPolicy"
    static let supportsSecureCoding = true

    let limit: Int
    let drain: Bool
    let terminated: Bool
    let reason: String?

    init(limit: Int, drain: Bool, terminated: Bool, reason: String?) {
        self.limit = limit
        self.drain = drain
        self.terminated = terminated
        self.reason = reason
    }

    init?(coder: NSCoder) {
        limit = coder.decodeInteger(forKey: "soclimit")
        drain = coder.decodeBool(forKey: "drain")
        terminated = coder.decodeBool(forKey: "terminated")
        reason = coder.decodeObject(of: NSString.self, forKey: "reason") as String?
    }

    func encode(with coder: NSCoder) {
        coder.encode(limit, forKey: "soclimit")
        coder.encode(drain, forKey: "drain")
        coder.encode(terminated, forKey: "terminated")
        coder.encode(reason as NSString?, forKey: "reason")
    }
}
