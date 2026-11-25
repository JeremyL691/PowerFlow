import SwiftUI

/// Charger detail tab: connected adapter metering, PD profiles and standby adapters.
struct ChargerPanel: View {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let snapshot: PowerSnapshot
    let settings: PowerSettings
    var isVisible: Bool = true

    private var language: AppLanguage { settings.appLanguage }
    private var adapter: AdapterSourceInfo? { snapshot.activeAdapter }
    private var blue: Color { PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast) }

    var body: some View {
        if snapshot.isEffectivelyOnAC {
            connectedContent
        } else {
            VStack(alignment: .leading, spacing: 7) {
                VStack(spacing: 6) {
                    Image(systemName: "powerplug")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                    Text(L10n.string(.noAdapterConnected, language: language))
                        .font(.system(size: 12))
                        .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)

                ForEach(snapshot.standbyAdapters) { standby in
                    standbyRow(standby)
                }
            }
        }
    }

    @ViewBuilder
    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 14) {
                GaugeRing(
                    fraction: ratedWatts.isFinite && ratedWatts > 0.5 ? snapshot.adapterInputPowerW / ratedWatts : 0,
                    tint: blue,
                    lineWidth: 6.5,
                    isVisible: isVisible
                ) {
                    VStack(spacing: 0) {
                        MetricValueText(
                            text: PowerFormatters.watts(snapshot.adapterInputPowerW, decimals: 1),
                            valueFont: .system(size: 16, weight: .semibold, design: .rounded),
                            unitFont: PowerFlowTheme.Typography.unit,
                            valueColor: PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast),
                            unitColor: PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                        )
                        if ratedWatts.isFinite, ratedWatts > 0.5 {
                            Text("/ \(Int(ratedWatts.rounded())) W")
                                .font(PowerFlowTheme.Typography.captionFloor)
                                .monospacedDigit()
                                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 5)
                }
                .frame(width: 76, height: 76)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.string(.power, language: language))
                .accessibilityValue(PowerFormatters.watts(snapshot.adapterInputPowerW, decimals: 1))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(headline.isEmpty ? L10n.string(.powerAdapter, language: language) : headline)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 6)
                        HStack(spacing: 3.5) {
                            Image(systemName: PowerFlowTheme.portSymbol(for: adapter?.portKind ?? .unknown))
                                .font(.system(size: 10, weight: .semibold))
                            Text(adapter.map { localizedAdapterText($0.portLabel) } ?? L10n.string(.portUnknown, language: language))
                                .font(PowerFlowTheme.Typography.captionFloor)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }
                        .foregroundStyle(blue)
                        .fixedSize(horizontal: true, vertical: false)
                    }

                    KeyValueRow(
                        label: L10n.string(.voltage, language: language),
                        value: PowerFormatters.volts(snapshot.adapterInputVoltageV)
                    )
                    KeyValueRow(
                        label: L10n.string(.current, language: language),
                        value: ofRated(
                            PowerFormatters.amps(snapshot.adapterInputCurrentA),
                            rated: ratedCurrent.isFinite && ratedCurrent > 0.05 ? PowerFormatters.amps(ratedCurrent) : nil
                        )
                    )
                    KeyValueRow(
                        label: L10n.string(.wallPower, language: language),
                        value: snapshot.wallPowerEstimateW.map { "~\(PowerFormatters.watts($0, decimals: 1))" } ?? "—"
                    )
                }
            }

            if let serial = adapter?.serialNumber, !serial.isEmpty {
                CopyableSerialRow(
                    label: L10n.string(.serialNumber, language: language),
                    serial: serial,
                    isMasked: settings.maskSerialNumbers,
                    language: language
                )
            }

            if let profiles = adapter?.pdProfiles, !profiles.isEmpty {
                profileChips(profiles)
            }

            ForEach(snapshot.standbyAdapters) { standby in
                standbyRow(standby)
            }
        }
    }

    private var ratedWatts: Double { adapter?.ratedWatts ?? 0 }
    private var ratedCurrent: Double { adapter?.ratedCurrentA ?? 0 }

    private var headline: String {
        let name = (adapter?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? adapter?.description?.trimmingCharacters(in: .whitespacesAndNewlines))
            .map(localizedAdapterText)
        let maker = adapter?.manufacturer?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [name, maker].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func localizedAdapterText(_ raw: String) -> String {
        switch raw {
        case "Power Adapter":
            return L10n.string(.powerAdapter, language: language)
        case "External Display":
            return L10n.string(.externalDisplay, language: language)
        default:
            return raw
        }
    }

    private func ofRated(_ value: String, rated: String?) -> String {
        rated.map { "\(value) / \($0)" } ?? value
    }

    private func profileChips(_ profiles: [USBPDProfile]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(profiles.enumerated()), id: \.offset) { _, profile in
                let isActive = profile.isActive || profile.index == adapter?.activePDProfileIndex
                Text("\(compact(profile.maxVoltageV, "V"))/\(compact(profile.maxCurrentA, "A"))")
                    .font(PowerFlowTheme.Typography.monoCaptionFloor)
                    .fontWeight(isActive ? .semibold : .medium)
                    .monospacedDigit()
                    .foregroundStyle(
                        isActive
                            ? blue
                            : PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                    )
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                isActive
                                    ? blue.opacity(0.2)
                                    : PowerFlowTheme.tileFill(for: colorScheme, contrast: colorSchemeContrast)
                            )
                    )
                    .overlay {
                        if colorSchemeContrast == .increased {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    isActive
                                        ? blue.opacity(0.5)
                                        : PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                                    lineWidth: 0.7
                                )
                        }
                    }
            }
        }
    }

    private func compact(_ value: Double, _ unit: String) -> String {
        guard value.isFinite else { return "—\(unit)" }
        return abs(value - value.rounded()) < 0.05
            ? "\(Int(value.rounded()))\(unit)"
            : String(format: "%.2f%@", locale: Self.posixLocale, value, unit)
    }

    private func standbyRow(_ standby: AdapterSourceInfo) -> some View {
        HStack(spacing: 6) {
            PowerFlowChip(
                icon: "pause.circle",
                text: "\(L10n.string(.standby, language: language)) · \(localizedAdapterText(standby.portLabel))",
                tint: PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
            )
            Text((standby.connectedDeviceName ?? standby.name).map(localizedAdapterText) ?? L10n.string(.powerAdapter, language: language))
                .font(PowerFlowTheme.Typography.captionFloor)
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if standby.ratedWatts.isFinite, standby.ratedWatts > 0.5 {
                Text("\(Int(standby.ratedWatts.rounded())) W")
                    .font(PowerFlowTheme.Typography.captionFloor)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
