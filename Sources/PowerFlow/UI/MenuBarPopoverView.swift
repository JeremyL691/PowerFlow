import SwiftUI

/// Everything PowerFlow shows, in one popover.
struct MenuBarPopoverView: View {
    static let width: CGFloat = 452

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let monitor: PowerMonitor
    /// Content taller than this scrolls instead of leaving the screen.
    let maxHeight: CGFloat
    let openSettings: () -> Void
    let quitApp: () -> Void

    @State private var hasAppeared = false
    @State private var contentHeight: CGFloat = 0
    @AppStorage("popoverDetailTab") private var detailTab: PopoverDetailTab = .battery
    @AppStorage("popoverEnergyGroupingMode") private var energyGroupingMode: EnergyGroupingMode = .byApp

    private var snapshot: PowerSnapshot { monitor.snapshot }
    private var settings: PowerSettings { monitor.settingsStore.settings }
    private var language: AppLanguage { settings.appLanguage }
    private var needsScrolling: Bool { contentHeight > maxHeight + 0.5 }
    private var activeDetailTab: PopoverDetailTab {
        (detailTab == .energy && !settings.showEnergyDashboard) ? .battery : detailTab
    }

    var body: some View {
        ScrollView(.vertical) {
            measuredSections
        }
        .scrollIndicators(.never)
        .scrollDisabled(!needsScrolling)
        .fixedSize(horizontal: false, vertical: !needsScrolling)
        .frame(width: Self.width, height: needsScrolling ? maxHeight : nil)
        .background(alignment: .topLeading) {
            ambientAura
        }
        .clipped()
        .environment(\.locale, PowerFlowTheme.locale(for: language))
        .onAppear {
            hasAppeared = true
            monitor.setEnergyTabVisible(activeDetailTab == .energy)
        }
        .onChange(of: activeDetailTab) { _, tab in
            monitor.setEnergyTabVisible(tab == .energy)
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                hasAppeared = true
            }
        }
        .onChange(of: settings.showEnergyDashboard) { _, enabled in
            if !enabled && detailTab == .energy {
                detailTab = .battery
            }
            monitor.setEnergyTabVisible(activeDetailTab == .energy)
        }
    }

    private var measuredSections: some View {
        sections
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                guard newHeight.isFinite, newHeight > 0 else { return }
                if abs(contentHeight - newHeight) > 0.5 {
                    contentHeight = newHeight
                }
            }
    }

    private var ambientAura: some View {
        RadialGradient(
            colors: [
                heroAccent.opacity(colorScheme == .dark ? 0.22 : 0.13),
                heroAccent.opacity(colorScheme == .dark ? 0.06 : 0.035),
                .clear
            ],
            center: .center,
            startRadius: 0,
            endRadius: 260
        )
        .frame(width: 520, height: 520)
        .offset(x: 16 + 52 - 260, y: 16 + 52 - 260)
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : PowerFlowTheme.Motion.tint, value: heroAccent)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 14) {
            hero

            PowerFlowDiagram(
                snapshot: snapshot,
                language: language,
                isAnimating: monitor.isLiveStreaming
            )
            .opacity(hasAppeared ? 1 : 0)
            .animation(
                reduceMotion ? PowerFlowTheme.Motion.reducedFade : PowerFlowTheme.Motion.reveal.delay(PowerFlowTheme.Motion.revealStagger),
                value: hasAppeared
            )

            vitals
                .powerFlowReveal(index: 2, hasAppeared: hasAppeared, reduceMotion: reduceMotion)

            DetailTabBar(
                selection: $detailTab,
                showEnergyTab: settings.showEnergyDashboard,
                isOnAC: snapshot.isEffectivelyOnAC,
                ratedAdapterWatts: snapshot.activeAdapter?.ratedWatts ?? 0,
                outboundPortCount: snapshot.outboundPorts.count,
                language: language
            )
                .powerFlowReveal(index: 3, hasAppeared: hasAppeared, reduceMotion: reduceMotion)

            detailPanel
                .powerFlowReveal(index: 4, hasAppeared: hasAppeared, reduceMotion: reduceMotion)

            footer
                .powerFlowReveal(index: 5, hasAppeared: hasAppeared, reduceMotion: reduceMotion)
        }
        .padding(16)
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            ChargeRingView(
                fraction: snapshot.isDataAvailable ? Double(snapshot.batteryPercent) / 100 : 0,
                limitFraction: snapshot.chargeLimitPercent < 100 ? Double(snapshot.chargeLimitPercent) / 100 : nil,
                tint: NSColor(heroAccent),
                isDark: colorScheme == .dark,
                increasedContrast: colorSchemeContrast == .increased,
                direction: ringDirection,
                isAnimating: monitor.isLiveStreaming,
                reduceMotion: reduceMotion
            )
            .frame(width: 104, height: 104)
            .overlay { ringCenter }
            .opacity(hasAppeared ? 1 : 0)
            .animation(
                reduceMotion ? PowerFlowTheme.Motion.reducedFade : PowerFlowTheme.Motion.reveal,
                value: hasAppeared
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.string(.batteryCharge, language: language))
            .accessibilityValue(snapshot.isDataAvailable ? PowerFormatters.percent(snapshot.batteryPercent) : "—")

            VStack(alignment: .leading, spacing: 5) {
                statusRow
                powerLine
                detailLine
                metaLine
            }
            .powerFlowReveal(index: 0, hasAppeared: hasAppeared, reduceMotion: reduceMotion)
        }
    }

    private var ringCenter: some View {
        Group {
            if snapshot.isDataAvailable {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(hasAppeared || reduceMotion ? "\(snapshot.batteryPercent)" : "0")
                        .font(PowerFlowTheme.Typography.heroPercent)
                        .powerFlowNumericTransition(value: hasAppeared || reduceMotion ? snapshot.batteryPercent : 0)
                        .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                    Text("%")
                        .font(PowerFlowTheme.Typography.heroPercentUnit)
                        .foregroundStyle(PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast))
                }
            } else {
                Text("—")
                    .font(PowerFlowTheme.Typography.heroPercent)
                    .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
            }
        }
    }

    private var ringDirection: ChargeRingView.Direction {
        if snapshot.isBatteryCharging { return .charging }
        if snapshot.isBatteryDischarging { return .discharging }
        return .idle
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                statusIcon
                Text(L10n.label(for: snapshot.flowMode, language: language))
                    .font(PowerFlowTheme.Typography.status)
                    .lineLimit(1)
            }
            .foregroundStyle(statusTint)

            if snapshot.isLowPowerModeEnabled {
                HStack(spacing: 3) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L10n.tr("Low Power", zh: "低电量", language: language))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast))
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        let icon = Image(systemName: statusSymbol)
            .font(.system(size: 12, weight: .semibold))
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        if reduceMotion {
            icon
        } else {
            icon.symbolEffect(.bounce, value: snapshot.flowMode)
        }
    }

    private var powerLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            MetricValueText(
                text: powerValueText,
                valueFont: PowerFlowTheme.Typography.heroPower,
                unitFont: PowerFlowTheme.Typography.heroUnit,
                valueColor: PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast),
                unitColor: PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast)
            )
            Text(powerCaption)
                .font(PowerFlowTheme.Typography.captionFloor)
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
        }
    }

    private var powerValueText: String {
        guard snapshot.isDataAvailable else { return "—" }
        if abs(snapshot.batteryPowerW) >= 0.05 {
            return PowerFormatters.watts(snapshot.batteryPowerW, decimals: 1, signed: true)
        }
        return PowerFormatters.watts(snapshot.totalSystemLoadW, decimals: 1)
    }

    private var powerCaption: String {
        abs(snapshot.batteryPowerW) >= 0.05
            ? L10n.string(.battery, language: language)
            : L10n.string(.systemLoad, language: language)
    }

    private var detailLine: some View {
        Text(heroDetailText)
            .font(PowerFlowTheme.Typography.heroDetail)
            .monospacedDigit()
            .powerFlowNumericTransition(value: heroDetailText)
            .foregroundStyle(PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private var metaLine: some View {
        let parts = metaParts
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(PowerFlowTheme.Typography.captionFloor)
                .monospacedDigit()
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if snapshot.chargeLimitPercent < 100 && !snapshot.isEffectivelyOnAC {
            parts.append(L10n.tr("Limit \(snapshot.chargeLimitPercent)%", zh: "上限 \(snapshot.chargeLimitPercent)%", language: language))
        }
        return parts
    }

    private var statusSymbol: String {
        switch snapshot.flowMode {
        case .adapterCharging: return "bolt.fill"
        case .adapterBypass: return "powerplug.fill"
        case .adapterBatteryHybrid: return "bolt.badge.a.fill"
        case .batteryWhilePluggedIn: return "battery.75percent"
        case .batteryOnly: return PowerFlowTheme.batterySymbol(percent: snapshot.batteryPercent, isCharging: false)
        case .connectingAC: return "bolt.horizontal.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var statusTint: Color {
        switch snapshot.flowMode {
        case .adapterCharging:
            return PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        case .adapterBypass, .connectingAC:
            return PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast)
        case .adapterBatteryHybrid, .batteryWhilePluggedIn:
            return PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        case .batteryOnly:
            return snapshot.isLowBatteryWarning || snapshot.atCriticalLevel
                ? PowerFlowTheme.warningRed(for: colorScheme, contrast: colorSchemeContrast)
                : PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast)
        case .unknown:
            return PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
        }
    }

    private var heroAccent: Color {
        guard snapshot.isDataAvailable else {
            return PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
        }
        if !snapshot.isEffectivelyOnAC && (snapshot.isLowBatteryWarning || snapshot.atCriticalLevel) {
            return PowerFlowTheme.warningRed(for: colorScheme, contrast: colorSchemeContrast)
        }
        return PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast)
    }

    private var heroDetailText: String {
        guard snapshot.isDataAvailable else {
            return L10n.string(.flowUnknown, language: language)
        }
        if snapshot.isFullyCharged && snapshot.isEffectivelyOnAC && snapshot.flowMode != .batteryWhilePluggedIn {
            return L10n.string(.fullyCharged, language: language)
        }

        if let minutes = snapshot.timeRemainingMinutes, minutes > 0 {
            let formatted = PowerFormatters.duration(minutes: minutes, language: language)
            let suffix: String
            if !snapshot.isTimeEstimateToFull {
                suffix = L10n.string(.timeRemaining, language: language)
            } else if snapshot.chargeLimitPercent < 100 {
                suffix = L10n.tr(
                    "to \(snapshot.chargeLimitPercent)%",
                    zh: "充至 \(snapshot.chargeLimitPercent)%",
                    language: language
                )
            } else {
                suffix = L10n.string(.timeToFull, language: language)
            }
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

    // MARK: - Vitals

    private var vitals: some View {
        HStack(spacing: 8) {
            VitalTile(
                icon: "gauge.with.dots.needle.67percent",
                tint: PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast),
                title: L10n.tr("SoC Power", zh: "芯片功耗", language: language),
                value: snapshot.isDataAvailable
                    ? snapshot.systemBreakdown?.packagePowerW.map { PowerFormatters.watts($0, decimals: 1) } ?? "—"
                    : "—",
                detail: socPowerDetail
            )

            VitalTile(
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

            VitalTile(
                icon: "fan",
                tint: PowerFlowTheme.outboundTeal(for: colorScheme, contrast: colorSchemeContrast),
                title: L10n.string(.fans, language: language),
                value: fanValue,
                detail: thermalLabel
            )

            VitalTile(
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private var socPowerDetail: String {
        guard snapshot.isDataAvailable else { return "—" }
        if let display = snapshot.systemBreakdown?.displayPowerW, display >= 0.05 {
            return L10n.tr(
                "Display \(PowerFormatters.watts(display, decimals: 1))",
                zh: "屏幕 \(PowerFormatters.watts(display, decimals: 1))",
                language: language
            )
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
        case .nominal: return PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        case .fair: return PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        case .serious: return PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        case .critical: return PowerFlowTheme.warningRed(for: colorScheme, contrast: colorSchemeContrast)
        }
    }

    private var healthTint: Color {
        switch snapshot.health.condition {
        case .serviceRecommended:
            return PowerFlowTheme.warningRed(for: colorScheme, contrast: colorSchemeContrast)
        case .normal:
            let effectiveHealth = snapshot.health.realHealthPercent
                ?? snapshot.health.macOSCapacityPercent.map(Double.init)
            return (effectiveHealth ?? 100) < 80
                ? PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
                : PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        case .unknown:
            return PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
        }
    }

    // MARK: - Detail Panel

    private var detailPanel: some View {
        Group {
            switch activeDetailTab {
            case .battery:
                BatteryPanel(snapshot: snapshot, settings: settings)
            case .energy:
                EnergyDashboardSection(
                    monitor: monitor,
                    powerSnapshot: snapshot,
                    groupingMode: $energyGroupingMode,
                    limit: settings.energyDashboardLimit,
                    language: language
                )
            case .charger:
                ChargerPanel(snapshot: snapshot, settings: settings, isVisible: true)
            case .output:
                OutputPanel(snapshot: snapshot, language: language, isVisible: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .id(activeDetailTab)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
        .animation(reduceMotion ? PowerFlowTheme.Motion.reducedFade : PowerFlowTheme.Motion.tab, value: activeDetailTab)
        .padding(12)
        .powerFlowSurface(.tile(), cornerRadius: 14)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                LivePulseView(
                    tint: NSColor(
                        monitor.isLiveStreaming
                            ? PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
                            : PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                    ),
                    isPulsing: monitor.isLiveStreaming && !reduceMotion
                )
                .frame(width: 6, height: 6)

                Text(L10n.string(monitor.isLiveStreaming ? .live : .paused, language: language))
                .font(PowerFlowTheme.Typography.captionFloor)
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                PopoverIconButton(
                    symbol: "gearshape.fill",
                    helpText: L10n.string(.settings, language: language),
                    action: openSettings
                )
                PopoverIconButton(
                    symbol: "power",
                    helpText: L10n.string(.quitPowerFlow, language: language),
                    isDestructiveHover: true,
                    action: quitApp
                )
            }
            .powerFlowGlassGroup(spacing: 6)
        }
        .padding(.top, 1)
    }
}

private struct VitalTile: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let icon: String
    let tint: Color
    let title: String
    let value: String
    let detail: String

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(PowerFlowTheme.Typography.captionFloor)
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
            }

            MetricValueText(
                text: value,
                valueFont: PowerFlowTheme.Typography.tileValue,
                unitFont: PowerFlowTheme.Typography.unit,
                valueColor: PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast),
                unitColor: PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
            )

            Text(detail)
                .font(PowerFlowTheme.Typography.captionFloor)
                .monospacedDigit()
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .powerFlowSurface(.tile(isHovered: isHovered), cornerRadius: 12)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(PowerFlowTheme.Motion.hover) {
                    isHovered = hovering
                }
            }
        }
    }
}
