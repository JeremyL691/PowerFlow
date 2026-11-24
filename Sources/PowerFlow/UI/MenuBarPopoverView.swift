import SwiftUI

/// Everything PowerFlow shows, in one popover.
struct MenuBarPopoverView: View {
    static let width: CGFloat = 404

    @Environment(\.colorScheme) private var colorScheme

    let monitor: PowerMonitor
    /// Content taller than this scrolls instead of leaving the screen.
    let maxHeight: CGFloat
    let openSettings: () -> Void
    let quitApp: () -> Void

    private var snapshot: PowerSnapshot { monitor.snapshot }
    private var settings: PowerSettings { monitor.settingsStore.settings }
    private var language: AppLanguage { settings.appLanguage }

    var body: some View {
        ViewThatFits(in: .vertical) {
            sections
            ScrollView(.vertical) {
                sections
            }
            .scrollIndicators(.never)
        }
        .frame(width: Self.width)
        .frame(maxHeight: maxHeight)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            PowerFlowBarView(
                snapshot: snapshot,
                settings: settings,
                isAnimating: monitor.isLiveStreaming
            )

            metricStrip
            BatterySections(snapshot: snapshot, settings: settings)
            AdapterSection(snapshot: snapshot, settings: settings)
            OutboundSection(snapshot: snapshot, language: language)
            footer
        }
        .padding(13)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(L10n.string(.appName, language: language))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme))

                    if snapshot.isLowPowerModeEnabled {
                        PowerFlowChip(
                            icon: "leaf.fill",
                            text: L10n.tr("Low Power", zh: "低电量", language: language),
                            tint: PowerFlowTheme.dischargeAmber(for: colorScheme)
                        )
                    }
                }

                HStack(spacing: 5) {
                    PowerFlowChip(
                        icon: statusSymbol,
                        text: L10n.label(for: snapshot.flowMode, language: language),
                        tint: statusTint
                    )

                    if snapshot.chargeLimitPercent < 100 {
                        PowerFlowChip(
                            text: "\(L10n.string(.chargeLimit, language: language)) \(snapshot.chargeLimitPercent)%",
                            tint: PowerFlowTheme.acGold(for: colorScheme)
                        )
                    }
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let rawSoC = snapshot.rawStateOfCharge,
                       snapshot.isDataAvailable,
                       rawSoC != snapshot.batteryPercent
                    {
                        Text("HW \(PowerFormatters.percent(rawSoC))")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(PowerFlowTheme.nestedTileFill(for: colorScheme))
                            )
                            .help(L10n.string(.hardwareSoC, language: language))
                    }

                    Text(snapshot.isDataAvailable ? PowerFormatters.percent(snapshot.batteryPercent) : "—%")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme))
                }

                Text(timeEstimateCaption)
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))
                    .lineLimit(1)
            }
        }
    }

    private var statusSymbol: String {
        switch snapshot.flowMode {
        case .adapterCharging: return "bolt.fill"
        case .adapterBypass: return "powerplug.fill"
        case .adapterBatteryHybrid: return "bolt.badge.a.fill"
        case .batteryOnly: return "battery.75percent"
        case .connectingAC: return "bolt.horizontal.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var statusTint: Color {
        switch snapshot.flowMode {
        case .adapterCharging:
            return PowerFlowTheme.chargeGreen(for: colorScheme)
        case .adapterBypass, .connectingAC:
            return PowerFlowTheme.acGold(for: colorScheme)
        case .adapterBatteryHybrid:
            return PowerFlowTheme.dischargeAmber(for: colorScheme)
        case .batteryOnly:
            return snapshot.isLowBatteryWarning || snapshot.atCriticalLevel
                ? PowerFlowTheme.warningRed(for: colorScheme)
                : PowerFlowTheme.secondaryValue(for: colorScheme)
        case .unknown:
            return PowerFlowTheme.mutedLabel(for: colorScheme)
        }
    }

    private var timeEstimateCaption: String {
        guard snapshot.isDataAvailable else {
            return L10n.string(.flowUnknown, language: language)
        }
        if snapshot.isFullyCharged && snapshot.isEffectivelyOnAC {
            return L10n.string(.fullyCharged, language: language)
        }
        if let minutes = snapshot.timeRemainingMinutes, minutes > 0 {
            let formatted = PowerFormatters.duration(minutes: minutes, language: language)
            let suffix = snapshot.isTimeEstimateToFull
                ? L10n.string(.timeToFull, language: language)
                : L10n.string(.timeRemaining, language: language)
            return "\(formatted) · \(suffix)"
        }
        if let holdReason = snapshot.chargingHoldReason, !holdReason.isEmpty {
            return L10n.chargingHold(
                holdReason,
                chargeLimitPercent: snapshot.chargeLimitPercent,
                language: language
            )
        }
        if snapshot.flowMode == .adapterBypass {
            return L10n.string(.bypass, language: language)
        }
        return L10n.label(for: snapshot.telemetrySource, language: language)
    }

    // MARK: - Metric Strip

    private var metricStrip: some View {
        HStack(spacing: 7) {
            metricTile(
                icon: "gauge.with.dots.needle.67percent",
                tint: PowerFlowTheme.acGold(for: colorScheme),
                title: L10n.string(.systemLoad, language: language),
                value: snapshot.isDataAvailable ? PowerFormatters.watts(snapshot.totalSystemLoadW, decimals: 1) : "—",
                detail: loadDetail
            )
            metricTile(
                icon: "cpu",
                tint: thermalTint,
                title: L10n.string(.cpuTemp, language: language),
                value: PowerFormatters.temperature(
                    snapshot.systemBreakdown?.cpuTemperatureC,
                    unit: settings.temperatureUnit
                ),
                detail: snapshot.systemBreakdown?.gpuTemperatureC.map {
                    "GPU \(PowerFormatters.temperature($0, unit: settings.temperatureUnit))"
                } ?? thermalLabel
            )
            metricTile(
                icon: "fan",
                tint: PowerFlowTheme.outboundCyan(for: colorScheme),
                title: L10n.string(.fans, language: language),
                value: fanValue,
                detail: thermalLabel
            )
            metricTile(
                icon: "heart.fill",
                tint: healthTint,
                title: L10n.tr("Health", zh: "电池健康", language: language),
                value: snapshot.health.realHealthPercent.map { PowerFormatters.precisePercent($0, decimals: 1) }
                    ?? snapshot.health.macOSCapacityPercent.map(PowerFormatters.percent)
                    ?? "—",
                detail: snapshot.health.cycleCount.map {
                    L10n.tr("\($0) cycles", zh: "\($0) 次循环", language: language)
                } ?? "—"
            )
        }
    }

    private func metricTile(
        icon: String,
        tint: Color,
        title: String,
        value: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(PowerFlowTheme.nestedTileFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(PowerFlowTheme.hairlineDivider(for: colorScheme), lineWidth: 0.65)
        )
    }

    private var loadDetail: String {
        guard snapshot.isDataAvailable else { return "—" }
        if let package = snapshot.systemBreakdown?.packagePowerW, package >= 0.05 {
            return "SoC \(PowerFormatters.watts(package, decimals: 1))"
        }
        return L10n.label(for: snapshot.telemetrySource, language: language)
    }

    private var fanValue: String {
        guard let fans = snapshot.systemBreakdown?.fans, let fastest = fans.map(\.rpm).max() else {
            return "—"
        }
        return fastest < 100
            ? L10n.tr("Silent", zh: "静音", language: language)
            : PowerFormatters.rpm(fastest)
    }

    private var thermalState: ThermalPressureLevel {
        snapshot.systemBreakdown?.thermalState ?? .nominal
    }

    private var thermalLabel: String {
        L10n.label(for: thermalState, language: language)
    }

    private var thermalTint: Color {
        switch thermalState {
        case .nominal: return PowerFlowTheme.chargeGreen(for: colorScheme)
        case .fair: return PowerFlowTheme.acGold(for: colorScheme)
        case .serious: return PowerFlowTheme.dischargeAmber(for: colorScheme)
        case .critical: return PowerFlowTheme.warningRed(for: colorScheme)
        }
    }

    private var healthTint: Color {
        switch snapshot.health.condition {
        case .serviceRecommended:
            return PowerFlowTheme.warningRed(for: colorScheme)
        case .normal:
            return (snapshot.health.realHealthPercent ?? 100) < 80
                ? PowerFlowTheme.dischargeAmber(for: colorScheme)
                : PowerFlowTheme.chargeGreen(for: colorScheme)
        case .unknown:
            return PowerFlowTheme.mutedLabel(for: colorScheme)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(
                    monitor.isLiveStreaming
                        ? PowerFlowTheme.chargeGreen(for: colorScheme)
                        : PowerFlowTheme.mutedLabel(for: colorScheme)
                )
                .frame(width: 6, height: 6)
            Text(
                "\(L10n.string(monitor.isLiveStreaming ? .live : .paused, language: language)) · \(L10n.label(for: snapshot.telemetrySource, language: language)) · \(String(format: "%.0fs", settings.liveRefreshInterval.rawValue))"
            )
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))
            .lineLimit(1)

            Spacer(minLength: 6)

            iconButton(
                symbol: "gearshape.fill",
                helpText: L10n.string(.settings, language: language),
                action: openSettings
            )
            iconButton(
                symbol: "power",
                helpText: L10n.string(.quitPowerFlow, language: language),
                action: quitApp
            )
        }
    }

    private func iconButton(symbol: String, helpText: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(PowerFlowTheme.secondaryValue(for: colorScheme))
                .frame(width: 28, height: 25)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(PowerFlowTheme.nestedTileFill(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(PowerFlowTheme.hairlineDivider(for: colorScheme), lineWidth: 0.65)
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}
