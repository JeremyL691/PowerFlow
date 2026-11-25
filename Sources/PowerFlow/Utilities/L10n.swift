import Foundation

enum L10n {
    enum Key: String, CaseIterable, Sendable {
        // App & Chrome
        case appName
        case settings
        case quitPowerFlow
        case live
        case paused

        // Flow Modes & Phases
        case flowAdapterBypass
        case flowAdapterCharging
        case flowAdapterBatteryHybrid
        case flowBatteryWhilePluggedIn
        case flowBatteryOnly
        case flowConnectingAC
        case flowUnknown
        case powerAdapter
        case battery
        case standby
        case bypass
        case hybridPower
        case charging
        case discharging
        case onBattery
        case chargeLimit
        case timeToFull
        case timeRemaining
        case fullyCharged

        // Card Titles
        case batterySpecs
        case batteryHealth
        case powerAdapterSpecs
        case outboundUSBCPower

        // Battery Specs Rows
        case current
        case voltage
        case power
        case systemLoad
        case lowPowerMode
        case batteryCharge
        case temperature
        case remainingEnergy
        case hardwareSoC

        // Battery Health & Lifetime Rows
        case designCapacity
        case maximumCapacity
        case macOSCapacity
        case cycleCount
        case manufactureDate
        case serialNumber
        case conditionNormal
        case conditionServiceRecommended
        case conditionUnknown

        // Adapter Specs & USB-PD Rows
        case manufacturer
        case model
        case description
        case wallPower
        case noAdapterConnected
        case portUnknown

        // System Power Breakdown & Thermal
        case cpuTemp
        case thermalState
        case thermalNominal
        case thermalFair
        case thermalSerious
        case thermalCritical
        case fans

        // Outbound & Physical Ports
        case outboundOutput
        case externalDisplay
        case usbcDevice
        case noOutboundDevices
        case cableType

        // Charge Limit Sources
        case limitSourceOptimized

        // Settings
        case settingsGeneral
        case settingsMenuBar
        case settingsDisplayMode
        case settingsZeroPollingHint
        case settingsRefreshRate
        case settingsTemperatureUnit
        case settingsPrivacy
        case settingsMaskSerials
        case settingsLanguage
        case settingsStartup
        case settingsLaunchAtLogin
        case launchAtLoginRequiresApproval
        case openLoginItemsSettings
        case settingsAbout
        case settingsResetDefaults

        // Display Modes & Options
        case modeIconOnly
        case modeIconAndPercentage
        case modeIconAndWatts
        case modeIconPercentageAndWatts
        case settingsIconStyle
        case iconStyleOutlined
        case iconStyleSolid
        case intervalStandard
        case intervalRelaxed
        case unitCelsius
        case unitFahrenheit
        case languageSystem
        case languageEnglish
        case languageSimplifiedChinese

        // Telemetry Sources
        case sourceSMCAndIOKit
        case sourceIOKitTelemetry
        case sourceIOKitLegacy
        case sourceUnavailable

        // Energy Dashboard
        case energyDashboard
        case energyByApp
        case energyByProcess
        case energySegmentSoC
        case energySegmentDisplay
        case energySegmentOutbound
        case energySegmentOther
        case energySampling
        case energyNoActiveConsumers
        case energyImpact
        case energyCPU
        case energyPCoreShare
        case energyWakeups
        case energyDiskIO
        case energyMemory
        case energyPreventingSleep
        case energyProcessesSection
        case openActivityMonitor
        case energyScopeFootnote
        case settingsEnergyDashboard
        case settingsShowEnergyDashboard
        case settingsEnergyDashboardLimit
    }

    static func resolvedLanguage(for setting: AppLanguage) -> AppLanguage {
        switch setting {
        case .english:
            return .english
        case .simplifiedChinese:
            return .simplifiedChinese
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
        }
    }

    static func tr(_ en: String, zh: String, language: AppLanguage = .system) -> String {
        resolvedLanguage(for: language) == .simplifiedChinese ? zh : en
    }

    static func string(_ key: Key, language: AppLanguage = .system) -> String {
        let isZh = resolvedLanguage(for: language) == .simplifiedChinese
        switch key {
        // App & Chrome
        case .appName: return "PowerFlow"
        case .settings: return isZh ? "设置…" : "Settings…"
        case .quitPowerFlow: return isZh ? "退出 PowerFlow" : "Quit PowerFlow"
        case .live: return isZh ? "实时" : "Live"
        case .paused: return isZh ? "已暂停" : "Paused"

        // Flow Modes & Phases
        case .flowAdapterBypass: return isZh ? "电源适配器直供" : "Power Adapter"
        case .flowAdapterCharging: return isZh ? "正在充电" : "Charging"
        case .flowAdapterBatteryHybrid: return isZh ? "混合供电" : "Hybrid Power"
        case .flowBatteryWhilePluggedIn: return isZh ? "已接电源 · 用电池" : "Plugged In · On Battery"
        case .flowBatteryOnly: return isZh ? "电池供电" : "On Battery"
        case .flowConnectingAC: return isZh ? "正在连接电源…" : "Connecting Power…"
        case .flowUnknown: return isZh ? "状态未知" : "Unavailable"
        case .powerAdapter: return isZh ? "电源适配器" : "Power Adapter"
        case .battery: return isZh ? "电池" : "Battery"
        case .standby: return isZh ? "待命" : "Standby"
        case .bypass: return isZh ? "直供" : "Bypass"
        case .hybridPower: return isZh ? "混合供电" : "Hybrid Power"
        case .charging: return isZh ? "正在充电" : "Charging"
        case .discharging: return isZh ? "正在放电" : "Discharging"
        case .onBattery: return isZh ? "使用电池" : "On Battery"
        case .chargeLimit: return isZh ? "充电上限" : "Charge Limit"
        case .timeToFull: return isZh ? "充满还需" : "Until Full"
        case .timeRemaining: return isZh ? "剩余续航" : "Remaining"
        case .fullyCharged: return isZh ? "已充满" : "Fully Charged"

        // Card Titles
        case .batterySpecs: return isZh ? "电池参数" : "Battery Specs"
        case .batteryHealth: return isZh ? "电池健康" : "Battery Health"
        case .powerAdapterSpecs: return isZh ? "电源适配器参数" : "Power Adapter Specs"
        case .outboundUSBCPower: return isZh ? "USB-C 反向供电输出" : "Outbound USB-C Power"

        // Battery Specs Rows
        case .current: return isZh ? "电流" : "Current"
        case .voltage: return isZh ? "电压" : "Voltage"
        case .power: return isZh ? "功率" : "Power"
        case .systemLoad: return isZh ? "系统总功耗" : "System Load"
        case .lowPowerMode: return isZh ? "低电量模式" : "Low Power Mode"
        case .batteryCharge: return isZh ? "当前电量" : "Battery Charge"
        case .temperature: return isZh ? "温度" : "Temperature"
        case .remainingEnergy: return isZh ? "剩余能量" : "Remaining Energy"
        case .hardwareSoC: return isZh ? "硬件原始电量" : "Hardware SoC"

        // Battery Health & Lifetime Rows
        case .designCapacity: return isZh ? "设计容量" : "Design Capacity"
        case .maximumCapacity: return isZh ? "实际最大容量" : "Max Capacity"
        case .macOSCapacity: return isZh ? "macOS 标称容量" : "macOS Capacity"
        case .cycleCount: return isZh ? "循环次数" : "Cycle Count"
        case .manufactureDate: return isZh ? "生产日期" : "Made"
        case .serialNumber: return isZh ? "序列号" : "Serial"
        case .conditionNormal: return isZh ? "正常" : "Normal"
        case .conditionServiceRecommended: return isZh ? "建议维修" : "Service Recommended"
        case .conditionUnknown: return isZh ? "未知" : "Unknown"

        // Adapter Specs & USB-PD Rows
        case .manufacturer: return isZh ? "制造商" : "Manufacturer"
        case .model: return isZh ? "型号" : "Model"
        case .description: return isZh ? "描述" : "Description"
        case .wallPower: return isZh ? "插座估算功耗" : "Wall Power"
        case .noAdapterConnected: return isZh ? "未连接电源适配器" : "No Power Adapter Connected"
        case .portUnknown: return isZh ? "电源端口" : "Power Port"

        // System Power Breakdown & Thermal
        case .cpuTemp: return isZh ? "CPU 温度" : "CPU Temp"
        case .thermalState: return isZh ? "散热状态" : "Thermal State"
        case .thermalNominal: return isZh ? "正常" : "Nominal"
        case .thermalFair: return isZh ? "偏暖" : "Fair"
        case .thermalSerious: return isZh ? "较热" : "Serious"
        case .thermalCritical: return isZh ? "过热" : "Critical"
        case .fans: return isZh ? "风扇" : "Fans"

        // Outbound & Physical Ports
        case .outboundOutput: return isZh ? "对外供电" : "Outbound Power"
        case .externalDisplay: return isZh ? "外接显示器" : "External Display"
        case .usbcDevice: return isZh ? "USB-C 设备" : "USB-C Device"
        case .noOutboundDevices: return isZh ? "当前无外设反向取电" : "No active outbound USB-C power draw"
        case .cableType: return isZh ? "线缆类型" : "Cable Type"

        // Charge Limit Sources
        case .limitSourceOptimized: return isZh ? "优化电池充电" : "Optimized Charging"

        // Settings
        case .settingsGeneral: return isZh ? "通用" : "General"
        case .settingsMenuBar: return isZh ? "菜单栏" : "Menu Bar"
        case .settingsDisplayMode: return isZh ? "菜单栏显示样式" : "Display Mode"
        case .settingsZeroPollingHint: return isZh ? "仅图标和图标+百分比模式在面板关闭时零后台轮询（0% CPU）" : "Icon Only and Icon + Percentage use zero background polling when closed"
        case .settingsRefreshRate: return isZh ? "实时刷新频率" : "Live Refresh Rate"
        case .settingsTemperatureUnit: return isZh ? "温度单位" : "Temperature Unit"
        case .settingsPrivacy: return isZh ? "隐私" : "Privacy"
        case .settingsMaskSerials: return isZh ? "隐藏序列号" : "Mask Serial Numbers"
        case .settingsLanguage: return isZh ? "界面语言" : "Interface Language"
        case .settingsStartup: return isZh ? "启动" : "Startup"
        case .settingsLaunchAtLogin: return isZh ? "登录时启动" : "Launch at Login"
        case .launchAtLoginRequiresApproval: return isZh ? "需在“系统设置 → 登录项”中批准" : "Approval required in System Settings → Login Items"
        case .openLoginItemsSettings: return isZh ? "打开登录项设置…" : "Open Login Items…"
        case .settingsAbout: return isZh ? "关于" : "About"
        case .settingsResetDefaults: return isZh ? "恢复默认设置" : "Reset to Defaults"

        // Display Modes & Options
        case .modeIconOnly: return isZh ? "仅图标" : "Icon Only"
        case .modeIconAndPercentage: return isZh ? "图标 + 百分比" : "Icon + Percentage"
        case .modeIconAndWatts: return isZh ? "图标 + 功率" : "Icon + Watts"
        case .modeIconPercentageAndWatts: return isZh ? "图标 + 百分比 + 功率" : "Icon + % + Watts"
        case .settingsIconStyle: return isZh ? "电池图标样式" : "Battery Icon Style"
        case .iconStyleOutlined: return isZh ? "描边" : "Outlined"
        case .iconStyleSolid: return isZh ? "实心（macOS 27）" : "Solid (macOS 27)"
        case .intervalStandard: return isZh ? "1.0 秒（标准）" : "1.0s (Standard)"
        case .intervalRelaxed: return isZh ? "2.0 秒（省电）" : "2.0s (Relaxed)"
        case .unitCelsius: return isZh ? "摄氏度 (°C)" : "Celsius (°C)"
        case .unitFahrenheit: return isZh ? "华氏度 (°F)" : "Fahrenheit (°F)"
        case .languageSystem: return isZh ? "跟随系统" : "System"
        case .languageEnglish: return "English"
        case .languageSimplifiedChinese: return "简体中文"

        // Telemetry Sources
        case .sourceSMCAndIOKit: return "SMC + IOKit"
        case .sourceIOKitTelemetry: return "IOKit Telemetry"
        case .sourceIOKitLegacy: return "IOKit"
        case .sourceUnavailable: return isZh ? "不可用" : "Unavailable"

        // Energy Dashboard
        case .energyDashboard: return isZh ? "能耗看板" : "Energy Dashboard"
        case .energyByApp: return isZh ? "应用" : "Apps"
        case .energyByProcess: return isZh ? "进程" : "Processes"
        case .energySegmentSoC: return isZh ? "芯片" : "SoC"
        case .energySegmentDisplay: return isZh ? "屏幕" : "Display"
        case .energySegmentOutbound: return "USB-C"
        case .energySegmentOther: return isZh ? "其他" : "Other"
        case .energySampling: return isZh ? "正在采样进程能耗…" : "Sampling process energy…"
        case .energyNoActiveConsumers: return isZh ? "当前无显著耗电进程" : "No significant active energy consumers"
        case .energyImpact: return isZh ? "能耗影响" : "Energy Impact"
        case .energyCPU: return "CPU"
        case .energyPCoreShare: return isZh ? "性能核占比" : "P-Core Share"
        case .energyWakeups: return isZh ? "空闲唤醒" : "Idle Wakeups"
        case .energyDiskIO: return isZh ? "磁盘读写" : "Disk I/O"
        case .energyMemory: return isZh ? "内存占用" : "Memory"
        case .energyPreventingSleep: return isZh ? "阻止休眠" : "Preventing Sleep"
        case .energyProcessesSection: return isZh ? "包含进程" : "Processes"
        case .openActivityMonitor: return isZh ? "打开活动监视器" : "Open Activity Monitor"
        case .energyScopeFootnote: return isZh ? "应用功耗为 CPU 与芯片归因功耗；屏幕与外设功耗见上方硬件分布。" : "App power reflects CPU & SoC attributed energy; display and peripherals appear above."
        case .settingsEnergyDashboard: return isZh ? "能耗标签页" : "Energy Tab"
        case .settingsShowEnergyDashboard: return isZh ? "显示「能耗」标签页" : "Show Energy Tab"
        case .settingsEnergyDashboardLimit: return isZh ? "显示排行数量" : "Top Consumers Shown"
        }
    }

    static func label(for flowMode: PowerFlowMode, language: AppLanguage = .system) -> String {
        switch flowMode {
        case .adapterBypass: return string(.flowAdapterBypass, language: language)
        case .adapterCharging: return string(.flowAdapterCharging, language: language)
        case .adapterBatteryHybrid: return string(.flowAdapterBatteryHybrid, language: language)
        case .batteryWhilePluggedIn: return string(.flowBatteryWhilePluggedIn, language: language)
        case .batteryOnly: return string(.flowBatteryOnly, language: language)
        case .connectingAC: return string(.flowConnectingAC, language: language)
        case .unknown: return string(.flowUnknown, language: language)
        }
    }

    static func label(for condition: BatteryCondition, language: AppLanguage = .system) -> String {
        switch condition {
        case .normal: return string(.conditionNormal, language: language)
        case .serviceRecommended: return string(.conditionServiceRecommended, language: language)
        case .unknown: return string(.conditionUnknown, language: language)
        }
    }

    static func label(for displayMode: MenuBarDisplayMode, language: AppLanguage = .system) -> String {
        switch displayMode {
        case .iconOnly: return string(.modeIconOnly, language: language)
        case .iconAndPercentage: return string(.modeIconAndPercentage, language: language)
        case .iconAndWatts: return string(.modeIconAndWatts, language: language)
        case .iconPercentageAndWatts: return string(.modeIconPercentageAndWatts, language: language)
        }
    }

    static func label(for style: BatteryIconStyle, language: AppLanguage = .system) -> String {
        switch style {
        case .outlined: return string(.iconStyleOutlined, language: language)
        case .solid: return string(.iconStyleSolid, language: language)
        }
    }

    static func deviceName(for port: OutboundPortPower, language: AppLanguage = .system) -> String {
        if let name = port.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            switch name {
            case "External Display": return string(.externalDisplay, language: language)
            case "USB-C Device": return string(.usbcDevice, language: language)
            default: return name
            }
        }
        return string(port.isDisplayPortActive ? .externalDisplay : .usbcDevice, language: language)
    }

    static func chargingHold(_ reason: String, chargeLimitPercent: Int, language: AppLanguage = .system) -> String {
        let lower = reason.lowercased()
        if lower.contains("draining") {
            return tr("Draining to \(chargeLimitPercent)%", zh: "放电至 \(chargeLimitPercent)%", language: language)
        }
        if lower.contains("optimized") {
            return string(.limitSourceOptimized, language: language)
        }
        if lower.contains("full") {
            return string(.fullyCharged, language: language)
        }
        if lower.contains("limit") {
            let suffix = lower.contains("aldente") ? " · AlDente" : ""
            return "\(string(.chargeLimit, language: language)) (\(chargeLimitPercent)%\(suffix))"
        }
        if lower.contains("thermal") || lower.contains("temp") {
            return tr("Thermal Hold", zh: "温控暂停充电", language: language)
        }
        if lower.contains("on hold") {
            return tr("Charging On Hold", zh: "已暂停充电", language: language)
        }
        if lower.contains("slow") {
            return tr("Slow Charging", zh: "慢速充电", language: language)
        }
        return reason
    }

    static func label(for interval: LiveRefreshInterval, language: AppLanguage = .system) -> String {
        switch interval {
        case .standard: return string(.intervalStandard, language: language)
        case .relaxed: return string(.intervalRelaxed, language: language)
        }
    }

    static func label(for unit: TemperatureUnit, language: AppLanguage = .system) -> String {
        switch unit {
        case .celsius: return string(.unitCelsius, language: language)
        case .fahrenheit: return string(.unitFahrenheit, language: language)
        }
    }

    static func label(for appLanguage: AppLanguage, language: AppLanguage = .system) -> String {
        switch appLanguage {
        case .system: return string(.languageSystem, language: language)
        case .english: return string(.languageEnglish, language: language)
        case .simplifiedChinese: return string(.languageSimplifiedChinese, language: language)
        }
    }

    static func label(for telemetrySource: PowerTelemetrySource, language: AppLanguage = .system) -> String {
        switch telemetrySource {
        case .smcAndIOKit: return string(.sourceSMCAndIOKit, language: language)
        case .iokitTelemetry: return string(.sourceIOKitTelemetry, language: language)
        case .iokitLegacy: return string(.sourceIOKitLegacy, language: language)
        case .unavailable: return string(.sourceUnavailable, language: language)
        }
    }

    static func label(for thermalState: ThermalPressureLevel, language: AppLanguage = .system) -> String {
        switch thermalState {
        case .nominal: return string(.thermalNominal, language: language)
        case .fair: return string(.thermalFair, language: language)
        case .serious: return string(.thermalSerious, language: language)
        case .critical: return string(.thermalCritical, language: language)
        }
    }

    static func label(for limit: EnergyDashboardItemLimit, language: AppLanguage = .system) -> String {
        switch limit {
        case .top3: return tr("Top 3", zh: "前 3 项", language: language)
        case .top5: return tr("Top 5", zh: "前 5 项", language: language)
        case .top8: return tr("Top 8", zh: "前 8 项", language: language)
        }
    }

    static func label(for segment: HardwareEnergySegmentKind, language: AppLanguage = .system) -> String {
        switch segment {
        case .soc: return string(.energySegmentSoC, language: language)
        case .display: return string(.energySegmentDisplay, language: language)
        case .outbound: return string(.energySegmentOutbound, language: language)
        case .other: return string(.energySegmentOther, language: language)
        }
    }

    static func label(for mode: EnergyGroupingMode, language: AppLanguage = .system) -> String {
        switch mode {
        case .byApp: return string(.energyByApp, language: language)
        case .byProcess: return string(.energyByProcess, language: language)
        }
    }

    static func sleepAssertionDescription(_ types: [String], language: AppLanguage = .system) -> String {
        var descriptions: [String] = []
        var seen: Set<String> = []

        for rawType in types {
            let trimmed = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let mapped: String
            switch trimmed {
            case "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion":
                mapped = tr("Preventing display sleep", zh: "阻止显示器休眠", language: language)
            case "PreventUserIdleSystemSleep", "NoIdleSleepAssertion":
                mapped = tr("Preventing idle sleep", zh: "阻止空闲休眠", language: language)
            case "PreventSystemSleep":
                mapped = tr("Preventing system sleep", zh: "阻止系统休眠", language: language)
            default:
                mapped = trimmed
            }
            if seen.insert(mapped).inserted {
                descriptions.append(mapped)
            }
        }

        guard !descriptions.isEmpty else {
            return string(.energyPreventingSleep, language: language)
        }
        return descriptions.joined(separator: " · ")
    }
}
