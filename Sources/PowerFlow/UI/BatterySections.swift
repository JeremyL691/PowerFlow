import SwiftUI

/// Battery specs and battery health, side by side.
struct BatterySections: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: PowerSnapshot
    let settings: PowerSettings

    private var language: AppLanguage { settings.appLanguage }
    private var health: BatteryHealthInfo { snapshot.health }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            specs
            healthCard
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Specs

    private var specs: some View {
        PopoverSection(
            icon: "bolt.fill",
            tint: PowerFlowTheme.acGold(for: colorScheme),
            title: L10n.string(.batterySpecs, language: language)
        ) {
            EmptyView()
        } content: {
            VStack(spacing: 5) {
                KeyValueRow(
                    label: L10n.string(.power, language: language),
                    value: live(PowerFormatters.watts(snapshot.batteryPowerW, signed: true)),
                    valueColor: flowColor
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
            return PowerFlowTheme.chargeGreen(for: colorScheme)
        }
        if snapshot.isBatteryDischarging {
            return PowerFlowTheme.dischargeAmber(for: colorScheme)
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
            Text(L10n.label(for: health.condition, language: language))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(conditionTint)
                .lineLimit(1)
        } content: {
            VStack(spacing: 5) {
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
            return PowerFlowTheme.chargeGreen(for: colorScheme)
        case .serviceRecommended:
            return PowerFlowTheme.warningRed(for: colorScheme)
        case .unknown:
            return PowerFlowTheme.mutedLabel(for: colorScheme)
        }
    }
}
