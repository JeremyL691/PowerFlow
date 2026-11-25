import SwiftUI

/// Battery detail tab: live electricals beside long-term health, no card-in-card.
struct BatteryPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let snapshot: PowerSnapshot
    let settings: PowerSettings

    private var language: AppLanguage { settings.appLanguage }
    private var health: BatteryHealthInfo { snapshot.health }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                columnHeader(
                    icon: "bolt.fill",
                    tint: PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast),
                    title: L10n.tr("Now", zh: "实时", language: language)
                )
                nowRows
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(conditionTint)
                    Text(L10n.tr("Health", zh: "健康", language: language))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 3.5) {
                        if differentiateWithoutColor || health.condition == .serviceRecommended {
                            Image(systemName: conditionSymbol)
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        Text(L10n.label(for: health.condition, language: language))
                            .font(PowerFlowTheme.Typography.captionFloor)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(conditionTint)
                    .fixedSize(horizontal: true, vertical: false)
                }
                healthRows
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func columnHeader(icon: String, tint: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
            Spacer(minLength: 4)
        }
    }

    // MARK: - Now

    @ViewBuilder
    private var nowRows: some View {
        KeyValueRow(
            label: L10n.string(.power, language: language),
            value: live(PowerFormatters.watts(snapshot.batteryPowerW, signed: true)),
            valueColor: flowColor,
            prefixSymbol: flowPrefixSymbol
        )
        KeyValueRow(
            label: L10n.string(.current, language: language),
            value: live(PowerFormatters.amps(snapshot.batteryCurrentA, signed: true)),
            valueColor: flowColor
        )
        KeyValueRow(
            label: L10n.string(.voltage, language: language),
            value: live(PowerFormatters.volts(snapshot.batteryVoltageV))
        )
        KeyValueRow(
            label: L10n.string(.batteryCharge, language: language),
            value: PowerFormatters.capacityMAh(health.currentChargeMAh)
        )
        KeyValueRow(
            label: L10n.string(.remainingEnergy, language: language),
            value: PowerFormatters.wattHours(snapshot.batteryRemainingWh)
        )
        KeyValueRow(
            label: L10n.string(.temperature, language: language),
            value: PowerFormatters.temperature(snapshot.batteryTemperatureC, unit: settings.temperatureUnit)
        )
    }

    private func live(_ value: String) -> String {
        snapshot.isDataAvailable ? value : "—"
    }

    private var flowColor: Color? {
        if snapshot.isBatteryCharging {
            return PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        }
        if snapshot.isBatteryDischarging {
            return PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        }
        return nil
    }

    private var flowPrefixSymbol: String? {
        guard differentiateWithoutColor else { return nil }
        if snapshot.isBatteryCharging {
            return "arrow.down.circle.fill"
        }
        if snapshot.isBatteryDischarging {
            return "arrow.up.circle.fill"
        }
        return nil
    }

    // MARK: - Health

    @ViewBuilder
    private var healthRows: some View {
        KeyValueRow(
            label: L10n.string(.maximumCapacity, language: language),
            value: PowerFormatters.capacityMAh(health.rawMaxCapacityMAh)
        )
        KeyValueRow(
            label: L10n.string(.designCapacity, language: language),
            value: PowerFormatters.capacityMAh(health.designCapacityMAh)
        )
        KeyValueRow(
            label: L10n.string(.macOSCapacity, language: language),
            value: health.macOSCapacityPercent.map(PowerFormatters.percent) ?? "—"
        )
        KeyValueRow(
            label: L10n.string(.cycleCount, language: language),
            value: PowerFormatters.cycleCount(health.cycleCount, designLimit: nil)
        )
        KeyValueRow(
            label: L10n.string(.manufactureDate, language: language),
            value: health.manufactureDate ?? "—"
        )
        if let serial = health.batterySerial, !serial.isEmpty {
            CopyableSerialRow(
                label: L10n.string(.serialNumber, language: language),
                serial: serial,
                isMasked: settings.maskSerialNumbers,
                language: language
            )
        }
    }

    private var conditionTint: Color {
        switch health.condition {
        case .normal:
            return PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        case .serviceRecommended:
            return PowerFlowTheme.warningRed(for: colorScheme, contrast: colorSchemeContrast)
        case .unknown:
            return PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
        }
    }

    private var conditionSymbol: String {
        switch health.condition {
        case .normal:
            return "checkmark.circle.fill"
        case .serviceRecommended:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }
}
