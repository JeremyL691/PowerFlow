import Foundation
import Observation
import ServiceManagement

enum MenuBarDisplayMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    case iconOnly
    case iconAndPercentage
    case iconAndWatts
    case iconPercentageAndWatts

    var id: String { rawValue }

    var requiresPeriodicPolling: Bool {
        showsWatts
    }

    var showsPercentage: Bool {
        self == .iconAndPercentage || self == .iconPercentageAndWatts
    }

    var showsWatts: Bool {
        self == .iconAndWatts || self == .iconPercentageAndWatts
    }
}

enum LiveRefreshInterval: Double, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    case standard = 1.0
    case relaxed = 2.0

    var id: Double { rawValue }
}

enum TemperatureUnit: String, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }
}

enum AppLanguage: String, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }
}

struct PowerSettings: Codable, Equatable, Hashable, Sendable {
    var menuBarDisplayMode: MenuBarDisplayMode
    var batteryIconStyle: BatteryIconStyle
    var liveRefreshInterval: LiveRefreshInterval
    var temperatureUnit: TemperatureUnit
    var maskSerialNumbers: Bool
    var appLanguage: AppLanguage

    static let `default` = PowerSettings(
        menuBarDisplayMode: .iconOnly,
        batteryIconStyle: .outlined,
        liveRefreshInterval: .standard,
        temperatureUnit: .celsius,
        maskSerialNumbers: false,
        appLanguage: .system
    )

    init(
        menuBarDisplayMode: MenuBarDisplayMode = .iconOnly,
        batteryIconStyle: BatteryIconStyle = .outlined,
        liveRefreshInterval: LiveRefreshInterval = .standard,
        temperatureUnit: TemperatureUnit = .celsius,
        maskSerialNumbers: Bool = false,
        appLanguage: AppLanguage = .system
    ) {
        self.menuBarDisplayMode = menuBarDisplayMode
        self.batteryIconStyle = batteryIconStyle
        self.liveRefreshInterval = liveRefreshInterval
        self.temperatureUnit = temperatureUnit
        self.maskSerialNumbers = maskSerialNumbers
        self.appLanguage = appLanguage
    }

    private enum CodingKeys: String, CodingKey {
        case menuBarDisplayMode
        case batteryIconStyle
        case liveRefreshInterval
        case temperatureUnit
        case maskSerialNumbers
        case appLanguage
    }

    /// Decodes field by field so one unknown or retired value never discards the other settings.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PowerSettings.default
        func value<T: Decodable>(_ key: CodingKeys, default fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        self.menuBarDisplayMode = value(.menuBarDisplayMode, default: defaults.menuBarDisplayMode)
        self.batteryIconStyle = value(.batteryIconStyle, default: defaults.batteryIconStyle)
        self.liveRefreshInterval = value(.liveRefreshInterval, default: defaults.liveRefreshInterval)
        self.temperatureUnit = value(.temperatureUnit, default: defaults.temperatureUnit)
        self.maskSerialNumbers = value(.maskSerialNumbers, default: defaults.maskSerialNumbers)
        self.appLanguage = value(.appLanguage, default: defaults.appLanguage)
    }
}

@MainActor
@Observable
final class PowerSettingsStore {
    static let defaultStorageKey = "com.powerflow.settings.v1"

    @ObservationIgnored private let userDefaults: UserDefaults?
    @ObservationIgnored private let storageKey: String
    @ObservationIgnored private let manageLaunchAtLogin: Bool
    @ObservationIgnored private var isSyncingLaunchAtLogin = false

    @ObservationIgnored var onChange: ((PowerSettings) -> Void)?

    var settings: PowerSettings {
        didSet {
            guard settings != oldValue else { return }
            persist(settings)
            onChange?(settings)
        }
    }

    var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin, launchAtLogin != oldValue else { return }
            applyLaunchAtLogin(enabled: launchAtLogin)
        }
    }

    private(set) var launchAtLoginRequiresApproval: Bool = false
    private(set) var launchAtLoginError: String?

    /// Pass `nil` defaults to keep settings in memory only.
    init(
        userDefaults: UserDefaults? = .standard,
        storageKey: String = PowerSettingsStore.defaultStorageKey,
        manageLaunchAtLogin: Bool = true
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.manageLaunchAtLogin = manageLaunchAtLogin
        self.settings = Self.load(from: userDefaults, key: storageKey)
        self.launchAtLogin = false
        self.launchAtLoginRequiresApproval = false
        self.launchAtLoginError = nil
        if manageLaunchAtLogin {
            refreshLaunchAtLoginStatus()
        }
    }

    func refreshLaunchAtLoginStatus() {
        guard manageLaunchAtLogin else { return }
        syncLaunchAtLoginStatus(SMAppService.mainApp.status)
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func syncLaunchAtLoginStatus(_ status: SMAppService.Status) {
        isSyncingLaunchAtLogin = true
        defer { isSyncingLaunchAtLogin = false }
        switch status {
        case .enabled:
            launchAtLogin = true
            launchAtLoginRequiresApproval = false
            launchAtLoginError = nil
        case .requiresApproval:
            launchAtLogin = true
            launchAtLoginRequiresApproval = true
            launchAtLoginError = nil
        case .notRegistered, .notFound:
            launchAtLogin = false
            launchAtLoginRequiresApproval = false
        @unknown default:
            launchAtLogin = false
            launchAtLoginRequiresApproval = false
        }
    }

    func resetToDefaults() {
        settings = .default
    }

    private func applyLaunchAtLogin(enabled: Bool) {
        guard manageLaunchAtLogin else { return }
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            let status = SMAppService.mainApp.status
            if status == .requiresApproval {
                syncLaunchAtLoginStatus(status)
            } else {
                launchAtLoginError = error.localizedDescription
                syncLaunchAtLoginStatus(status)
            }
        }
    }

    private func persist(_ value: PowerSettings) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        userDefaults?.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults?, key: String) -> PowerSettings {
        guard let data = defaults?.data(forKey: key),
              let decoded = try? JSONDecoder().decode(PowerSettings.self, from: data) else {
            return .default
        }
        return decoded
    }
}
