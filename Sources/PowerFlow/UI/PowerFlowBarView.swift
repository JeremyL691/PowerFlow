import SwiftUI

struct PowerFlowBarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let snapshot: PowerSnapshot
    let settings: PowerSettings
    let isAnimating: Bool

    init(
        snapshot: PowerSnapshot,
        settings: PowerSettings = .default,
        isAnimating: Bool
    ) {
        self.snapshot = snapshot
        self.settings = settings
        self.isAnimating = isAnimating
    }

    private var language: AppLanguage { settings.appLanguage }

    private var primaryWatts: Double {
        guard snapshot.isDataAvailable else { return 0 }
        if snapshot.isEffectivelyOnAC {
            if snapshot.adapterInputPowerW > 0.05 {
                return snapshot.adapterInputPowerW
            }
            return snapshot.flowMode == .connectingAC ? 0 : snapshot.totalSystemLoadW
        }
        return snapshot.totalSystemLoadW > 0.05
            ? snapshot.totalSystemLoadW
            : snapshot.batteryDischargeRateW
    }

    private var primaryAmps: Double {
        guard snapshot.isDataAvailable else { return 0 }
        if snapshot.isEffectivelyOnAC {
            return max(0, snapshot.adapterInputCurrentA)
        }
        return abs(snapshot.batteryCurrentA)
    }

    private var primaryTint: Color {
        guard snapshot.isDataAvailable else { return PowerFlowTheme.mutedLabel(for: colorScheme) }
        if snapshot.isEffectivelyOnAC {
            return PowerFlowTheme.acGold(for: colorScheme)
        }
        return PowerFlowTheme.dischargeAmber(for: colorScheme)
    }

    private var primaryGlowTint: Color {
        if snapshot.isEffectivelyOnAC {
            return PowerFlowTheme.acGoldGlow(for: colorScheme)
        }
        return PowerFlowTheme.dischargeAmber(for: colorScheme)
    }

    private var primaryDirection: SweepingFlowDirection {
        guard snapshot.isDataAvailable else { return .idle }
        if snapshot.flowMode == .connectingAC {
            return .leftToRight
        }
        guard primaryWatts >= 0.05 else { return .idle }
        return .leftToRight
    }

    private var primaryActiveWattsForSpeed: Double {
        if snapshot.flowMode == .connectingAC {
            return 8.0
        }
        return primaryWatts
    }

    private var leftNodeIcon: String {
        if snapshot.isEffectivelyOnAC {
            return PowerFlowTheme.portSymbol(for: snapshot.activeAdapter?.portKind ?? .unknown)
        }
        return PowerFlowTheme.batterySymbol(
            percent: snapshot.batteryPercent,
            isCharging: false
        )
    }

    private var leftNodeTitle: String {
        if snapshot.isEffectivelyOnAC {
            if let portLabel = snapshot.activeAdapter?.portLabel, !portLabel.isEmpty {
                return portLabel
            }
            return L10n.string(.powerAdapter, language: language)
        }
        return L10n.string(.battery, language: language)
    }

    private var primaryCenterLabel: String {
        guard snapshot.isDataAvailable else { return "—" }
        if snapshot.flowMode == .connectingAC && primaryWatts < 0.05 {
            return L10n.string(.flowConnectingAC, language: language)
        }
        return PowerFormatters.watts(primaryWatts)
    }

    private var primarySecondaryLabel: String? {
        guard snapshot.isDataAvailable else { return nil }
        if snapshot.flowMode == .connectingAC && primaryWatts < 0.05 {
            return nil
        }
        guard primaryAmps >= 0.01 else { return nil }
        return PowerFormatters.amps(primaryAmps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            primarySupplyRow
            batteryBranchPill(height: 32)
            if snapshot.hasActiveOutboundPower {
                outboundBranchPill(height: 32)
            }
        }
    }

    // MARK: - Primary Supply Bar (Left Source Pill -> Sweeping Capsule -> MacBook Pill)

    private var primarySupplyRow: some View {
        let barHeight: CGFloat = 46
        let cornerRadius: CGFloat = 16

        return HStack(spacing: 6) {
            sourceNodePill(
                icon: leftNodeIcon,
                iconTint: primaryTint,
                title: leftNodeTitle,
                height: barHeight,
                cornerRadius: cornerRadius,
                minWidth: 76
            )

            SweepingEnergyCapsule(
                watts: primaryActiveWattsForSpeed,
                primaryText: primaryCenterLabel,
                secondaryText: primarySecondaryLabel,
                direction: primaryDirection,
                baseTint: primaryTint,
                glowTint: primaryGlowTint,
                height: barHeight,
                cornerRadius: cornerRadius,
                isAnimating: isAnimating && !reduceMotion
            )

            macNodePill(
                height: barHeight,
                cornerRadius: cornerRadius,
                minWidth: 56
            )
        }
    }

    private func sourceNodePill(
        icon: String,
        iconTint: Color,
        title: String,
        height: CGFloat,
        cornerRadius: CGFloat,
        minWidth: CGFloat
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconTint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

            }
        }
        .padding(.horizontal, 9)
        .frame(minWidth: minWidth, minHeight: height, maxHeight: height)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(PowerFlowTheme.pillFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(PowerFlowTheme.cardBorderGradient(for: colorScheme), lineWidth: 0.75)
        )
    }

    private func macNodePill(
        height: CGFloat,
        cornerRadius: CGFloat,
        minWidth: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme))
        }
        .padding(.horizontal, 10)
        .frame(minWidth: minWidth, minHeight: height, maxHeight: height)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(PowerFlowTheme.pillFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(PowerFlowTheme.cardBorderGradient(for: colorScheme), lineWidth: 0.75)
        )
    }

    // MARK: - Battery & Outbound Branches

    private func batteryBranchPill(height: CGFloat) -> some View {
        let isCharging = snapshot.isBatteryCharging
        let isDischarging = snapshot.isBatteryDischarging
        let direction: SweepingFlowDirection = isCharging
            ? .leftToRight
            : (isDischarging ? .rightToLeft : .idle)
        let watts = abs(snapshot.batteryPowerW)
        let tint: Color = isCharging
            ? PowerFlowTheme.chargeGreen(for: colorScheme)
            : (isDischarging ? PowerFlowTheme.dischargeAmber(for: colorScheme) : PowerFlowTheme.mutedLabel(for: colorScheme))

        let statusText: String
        if !snapshot.isDataAvailable {
            statusText = "—"
        } else if isCharging {
            statusText = "\(L10n.string(.charging, language: language)) \(PowerFormatters.watts(snapshot.batteryPowerW, decimals: 1, signed: true))"
        } else if isDischarging {
            let prefix = snapshot.flowMode == .adapterBatteryHybrid
                ? L10n.string(.hybridPower, language: language)
                : L10n.string(.discharging, language: language)
            statusText = "\(prefix) \(PowerFormatters.watts(snapshot.batteryPowerW, decimals: 1, signed: true))"
        } else {
            statusText = "\(L10n.string(.bypass, language: language)) · 0 W"
        }

        return HStack(spacing: 8) {
            Image(systemName: PowerFlowTheme.batterySymbol(percent: snapshot.batteryPercent, isCharging: isCharging))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text(L10n.string(.battery, language: language))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))

            if snapshot.chargeLimitPercent < 100 {
                PowerFlowChip(
                    icon: "shield.lefthalf.filled",
                    text: "\(snapshot.chargeLimitPercent)%",
                    tint: PowerFlowTheme.acGold(for: colorScheme)
                )
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                if isCharging {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9.5, weight: .bold))
                } else if isDischarging {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 9.5, weight: .bold))
                }
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(isCharging || isDischarging ? tint : PowerFlowTheme.secondaryValue(for: colorScheme))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background {
            EnergySweepBackground(
                watts: watts,
                direction: direction,
                tint: tint,
                cornerRadius: 12,
                isAnimating: isAnimating && !reduceMotion
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    (isCharging || isDischarging)
                        ? tint.opacity(colorScheme == .dark ? 0.32 : 0.26)
                        : PowerFlowTheme.hairlineDivider(for: colorScheme),
                    lineWidth: 0.75
                )
        )
    }

    private func outboundBranchPill(height: CGFloat) -> some View {
        let tint = PowerFlowTheme.outboundCyan(for: colorScheme)
        let activeCount = max(
            1,
            snapshot.outboundPorts.filter { $0.powerW > 0.05 || $0.currentA > 0.01 }.count
        )
        let portsLabel = L10n.tr(
            activeCount == 1 ? "1 port" : "\(activeCount) ports",
            zh: "\(activeCount) 端口",
            language: language
        )
        let summaryText = "\(PowerFormatters.watts(snapshot.totalOutboundPowerW, decimals: 2)) · \(PowerFormatters.amps(snapshot.totalOutboundCurrentA, decimals: 2))"

        return HStack(spacing: 8) {
            Image(systemName: "arrow.up.right.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text(L10n.string(.outboundOutput, language: language))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))
                .lineLimit(1)

            PowerFlowChip(text: portsLabel, tint: tint)

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                Text(summaryText)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                Image(systemName: "arrow.right")
                    .font(.system(size: 9.5, weight: .bold))
            }
            .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .background {
            EnergySweepBackground(
                watts: snapshot.totalOutboundPowerW,
                direction: .leftToRight,
                tint: tint,
                cornerRadius: 12,
                isAnimating: isAnimating && !reduceMotion
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(colorScheme == .dark ? 0.34 : 0.28), lineWidth: 0.75)
        )
    }
}
