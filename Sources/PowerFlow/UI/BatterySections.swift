import SwiftUI

/// Battery specs and battery health, side by side.
struct BatterySections: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let snapshot: PowerSnapshot
    let settings: PowerSettings

    private var language: AppLanguage { settings.appLanguage }
    private var health: BatteryHealthInfo { snapshot.health }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            specs
            healthCard
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Specs

    private var specs: some View {
        PopoverSection(
            icon: "bolt.fill",
            tint: PowerFlowTheme.acGold(for: colorScheme, contrast: colorSchemeContrast),
            title: L10n.string(.batterySpecs, language: language)
        ) {
            EmptyView()
        } content: {
            VStack(spacing: 6) {
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
        }
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

    private var healthCard: some View {
        PopoverSection(
            icon: "heart.fill",
            tint: conditionTint,
            title: L10n.string(.batteryHealth, language: language)
        ) {
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
        } content: {
            VStack(spacing: 6) {
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
                    value: PowerFormatters.cycleCount(health.cycleCount, designLimit: health.designCycleCount)
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
