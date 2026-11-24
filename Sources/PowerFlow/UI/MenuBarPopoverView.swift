import SwiftUI

/// Everything PowerFlow shows, in one popover.
struct MenuBarPopoverView: View {
    static let width: CGFloat = 452

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let monitor: PowerMonitor
    /// Content taller than this scrolls instead of leaving the screen.
    let maxHeight: CGFloat
    let openSettings: () -> Void
    let quitApp: () -> Void

    @State private var hasAppeared = false
    @State private var isLiveDotDimmed = false

    private var snapshot: PowerSnapshot { monitor.snapshot }
    private var settings: PowerSettings { monitor.settingsStore.settings }
    private var language: AppLanguage { settings.appLanguage }

    var body: some View {
        ZStack(alignment: .top) {
            ambientCanvasWash

            ViewThatFits(in: .vertical) {
                sections
                ScrollView(.vertical) {
                    sections
                }
                .scrollIndicators(.never)
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: maxHeight)
        .onAppear {
            if reduceMotion {
                hasAppeared = true
            } else if !hasAppeared {
                hasAppeared = true
            }
            syncLivePulse()
        }
        .onChange(of: monitor.isLiveStreaming) { _, _ in
            syncLivePulse()
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                hasAppeared = true
            }
            syncLivePulse()
        }
    }

    private var ambientCanvasWash: some View {
        LinearGradient(
            colors: [
                statusTint.opacity(colorScheme == .dark ? 0.065 : 0.045),
                .clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 148)
        .allowsHitTesting(false)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 10) {
            heroHeader
                .modifier(StaggeredRevealModifier(index: 0, hasAppeared: hasAppeared, reduceMotion: reduceMotion))

            PowerFlowDiagram(
                snapshot: snapshot,
                language: language,
                isAnimating: monitor.isLiveStreaming
            )
            .modifier(StaggeredRevealModifier(index: 1, hasAppeared: hasAppeared, reduceMotion: reduceMotion))

            telemetryRibbon
                .modifier(StaggeredRevealModifier(index: 2, hasAppeared: hasAppeared, reduceMotion: reduceMotion))

            BatterySections(snapshot: snapshot, settings: settings)
                .modifier(StaggeredRevealModifier(index: 3, hasAppeared: hasAppeared, reduceMotion: reduceMotion))

            AdapterSection(snapshot: snapshot, settings: settings)
                .modifier(StaggeredRevealModifier(index: 4, hasAppeared: hasAppeared, reduceMotion: reduceMotion))

            OutboundSection(snapshot: snapshot, language: language)
                .modifier(StaggeredRevealModifier(index: 5, hasAppeared: hasAppeared, reduceMotion: reduceMotion))

            footer
                .modifier(StaggeredRevealModifier(index: 6, hasAppeared: hasAppeared, reduceMotion: reduceMotion))
        }
        .padding(14)
    }

    // MARK: - Hero Instrument Header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(L10n.string(.appName, language: language))
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))

                        if snapshot.isLowPowerModeEnabled {
                            PowerFlowChip(
                                icon: "leaf.fill",
                                text: L10n.tr("Low Power", zh: "低电量", language: language),
                                tint: PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
                            )
                        }
                    }

                    HStack(spacing: 5) {
                        PowerFlowChip(
                            icon: statusSymbol,
                            text: L10n.label(for: snapshot.flowMode, language: language),
                            tint: statusTint,
                            isProminent: true
                        )

                        if snapshot.chargeLimitPercent < 100 {
                            PowerFlowChip(
                                icon: differentiateWithoutColor ? "dial.low.fill" : nil,
                                text: "\(L10n.string(.chargeLimit, language: language)) \(snapshot.chargeLimitPercent)%",
                                tint: PowerFlowTheme.acGold(for: colorScheme, contrast: colorSchemeContrast)
                            )
                        }
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let rawSoC = snapshot.rawStateOfCharge,
                           snapshot.isDataAvailable,
                           rawSoC != snapshot.batteryPercent
                        {
                            Text("HW \(PowerFormatters.percent(rawSoC))")
                                .font(PowerFlowTheme.Typography.monoCaptionFloor)
                                .monospacedDigit()
                                .powerFlowNumericTransition()
                                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(PowerFlowTheme.nestedTileFill(for: colorScheme, contrast: colorSchemeContrast))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(
                                            PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                                            lineWidth: 0.5
                                        )
                                )
                                .fixedSize(horizontal: true, vertical: false)
                                .help(L10n.string(.hardwareSoC, language: language))
                        }

                        Text(snapshot.isDataAvailable ? PowerFormatters.percent(snapshot.batteryPercent) : "—%")
                            .font(PowerFlowTheme.Typography.heroSoC)
                            .monospacedDigit()
                            .powerFlowNumericTransition()
                            .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Text(heroSubtitle)
                        .font(PowerFlowTheme.Typography.heroSubvalue)
                        .monospacedDigit()
                        .powerFlowNumericTransition()
                        .foregroundStyle(PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            ProgressLine(
                fraction: snapshot.isDataAvailable ? Double(snapshot.batteryPercent) / 100.0 : 0,
                tint: heroProgressTint,
                limitFraction: snapshot.chargeLimitPercent < 100 ? Double(snapshot.chargeLimitPercent) / 100.0 : nil,
                height: 6
            )
            .accessibilityLabel(L10n.string(.batteryCharge, language: language))
            .accessibilityValue(snapshot.isDataAvailable ? PowerFormatters.percent(snapshot.batteryPercent) : "—%")
        }
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
            return PowerFlowTheme.acGold(for: colorScheme, contrast: colorSchemeContrast)
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

    private var heroProgressTint: Color {
        guard snapshot.isDataAvailable else {
            return PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
        }
        if snapshot.isLowBatteryWarning || snapshot.atCriticalLevel {
            return PowerFlowTheme.warningRed(for: colorScheme, contrast: colorSchemeContrast)
        }
        if snapshot.isLowPowerModeEnabled {
            return PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        }
        switch snapshot.flowMode {
        case .adapterCharging:
            return PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        case .adapterBypass, .connectingAC:
            return PowerFlowTheme.acGold(for: colorScheme, contrast: colorSchemeContrast)
        case .adapterBatteryHybrid, .batteryWhilePluggedIn:
            return PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        case .batteryOnly:
            return snapshot.batteryPercent <= 20
                ? PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
                : PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        case .unknown:
            return PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
        }
    }

    private var heroSubtitle: String {
        guard snapshot.isDataAvailable else {
            return L10n.string(.flowUnknown, language: language)
        }
        if snapshot.isFullyCharged && snapshot.isEffectivelyOnAC && snapshot.flowMode != .batteryWhilePluggedIn {
            return L10n.string(.fullyCharged, language: language)
        }

        let netWatts: String? = abs(snapshot.batteryPowerW) >= 0.05
            ? PowerFormatters.watts(snapshot.batteryPowerW, decimals: 1, signed: true)
            : nil

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

            let timeText = "\(formatted) · \(suffix)"
            if let netWatts, !(snapshot.flowMode == .batteryWhilePluggedIn && snapshot.chargeLimitPercent < 100) {
                return "\(netWatts) · \(timeText)"
            }
            return timeText
        }

        if let holdReason = snapshot.chargingHoldReason, !holdReason.isEmpty {
            let holdText = L10n.chargingHold(
                holdReason,
                chargeLimitPercent: snapshot.chargeLimitPercent,
                language: language
            )
            if let netWatts {
                return "\(netWatts) · \(holdText)"
            }
            return holdText
        }

        if snapshot.flowMode == .adapterBypass {
            return L10n.string(.bypass, language: language)
        }

        if let netWatts {
            return netWatts
        }

        return L10n.label(for: snapshot.telemetrySource, language: language)
    }

    // MARK: - Unified Telemetry Ribbon

    private var telemetryRibbon: some View {
        HStack(spacing: 0) {
            ribbonSegment(
                icon: "gauge.with.dots.needle.67percent",
                tint: PowerFlowTheme.acGold(for: colorScheme, contrast: colorSchemeContrast),
                title: L10n.string(.systemLoad, language: language),
                value: snapshot.isDataAvailable ? PowerFormatters.watts(snapshot.totalSystemLoadW, decimals: 1) : "—",
                detail: loadDetail
            )

            ribbonDivider

            ribbonSegment(
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

            ribbonDivider

            ribbonSegment(
                icon: "fan",
                tint: PowerFlowTheme.outboundCyan(for: colorScheme, contrast: colorSchemeContrast),
                title: L10n.string(.fans, language: language),
                value: fanValue,
                detail: thermalLabel
            )

            ribbonDivider

            ribbonSegment(
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
        .powerFlowSurface(.quietStrip, cornerRadius: 13)
    }

    private var ribbonDivider: some View {
        Rectangle()
            .fill(PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast))
            .frame(width: 0.5)
            .padding(.vertical, 9)
    }

    private func ribbonSegment(
        icon: String,
        tint: Color,
        title: String,
        value: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(PowerFlowTheme.Typography.captionFloor)
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(value)
                .font(PowerFlowTheme.Typography.metricValue)
                .monospacedDigit()
                .powerFlowNumericTransition()
                .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Text(detail)
                .font(PowerFlowTheme.Typography.captionFloor)
                .monospacedDigit()
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case .nominal: return PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        case .fair: return PowerFlowTheme.acGold(for: colorScheme, contrast: colorSchemeContrast)
        case .serious: return PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        case .critical: return PowerFlowTheme.warningRed(for: colorScheme, contrast: colorSchemeContrast)
        }
    }

    private var healthTint: Color {
        switch snapshot.health.condition {
        case .serviceRecommended:
            return PowerFlowTheme.warningRed(for: colorScheme, contrast: colorSchemeContrast)
        case .normal:
            return (snapshot.health.realHealthPercent ?? 100) < 80
                ? PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
                : PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        case .unknown:
            return PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
        }
    }

    // MARK: - Footer Toolbar

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(
                        monitor.isLiveStreaming
                            ? PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
                            : PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                    )
                    .frame(width: 6, height: 6)
                    .opacity(monitor.isLiveStreaming && !reduceMotion && isLiveDotDimmed ? 0.38 : 1.0)

                Text(
                    "\(L10n.string(monitor.isLiveStreaming ? .live : .paused, language: language)) · \(L10n.label(for: snapshot.telemetrySource, language: language)) · \(String(format: "%.0fs", settings.liveRefreshInterval.rawValue))"
                )
                .font(PowerFlowTheme.Typography.captionFloor)
                .monospacedDigit()
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

    private func syncLivePulse() {
        if monitor.isLiveStreaming && !reduceMotion {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isLiveDotDimmed = true
            }
        } else {
            withAnimation(nil) {
                isLiveDotDimmed = false
            }
        }
    }
}

private struct StaggeredRevealModifier: ViewModifier {
    let index: Int
    let hasAppeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || hasAppeared ? 1 : 0)
            .offset(y: reduceMotion || hasAppeared ? 0 : 4)
            .animation(
                reduceMotion ? nil : .spring(duration: 0.30, bounce: 0.12).delay(Double(index) * 0.022),
                value: hasAppeared
            )
    }
}
