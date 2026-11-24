import SwiftUI

struct AdapterSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let snapshot: PowerSnapshot
    let settings: PowerSettings

    private var language: AppLanguage { settings.appLanguage }
    private var adapter: AdapterSourceInfo? { snapshot.activeAdapter }
    private var gold: Color { PowerFlowTheme.acGold(for: colorScheme, contrast: colorSchemeContrast) }
    private var isQuiet: Bool { !snapshot.isEffectivelyOnAC && snapshot.standbyAdapters.isEmpty }

    var body: some View {
        PopoverSection(
            icon: "powerplug.fill",
            tint: snapshot.isEffectivelyOnAC
                ? gold
                : PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast),
            title: L10n.string(.powerAdapterSpecs, language: language),
            isQuiet: isQuiet
        ) {
            if snapshot.isEffectivelyOnAC {
                PowerFlowChip(
                    icon: PowerFlowTheme.portSymbol(for: adapter?.portKind ?? .unknown),
                    text: adapter?.portLabel ?? L10n.string(.portUnknown, language: language),
                    tint: gold
                )
            } else {
                Text(L10n.string(.noAdapterConnected, language: language))
                    .font(PowerFlowTheme.Typography.captionFloor)
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } content: {
            if snapshot.isEffectivelyOnAC {
                connectedContent
            } else if !snapshot.standbyAdapters.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.standbyAdapters) { standby in
                        standbyRow(standby)
                    }
                }
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !headline.isEmpty {
                Text(headline)
                    .font(PowerFlowTheme.Typography.rowLabel)
                    .fontWeight(.medium)
                    .foregroundStyle(PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if ratedWatts > 0.5 {
                ProgressLine(
                    fraction: snapshot.adapterInputPowerW / ratedWatts,
                    tint: gold,
                    height: 5
                )
                .padding(.vertical, 1)
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    KeyValueRow(
                        label: L10n.string(.power, language: language),
                        value: ofRated(
                            PowerFormatters.watts(snapshot.adapterInputPowerW, decimals: 1),
                            rated: ratedWatts > 0.5 ? "\(Int(ratedWatts.rounded())) W" : nil
                        ),
                        valueColor: gold
                    )
                    KeyValueRow(
                        label: L10n.string(.voltage, language: language),
                        value: PowerFormatters.volts(snapshot.adapterInputVoltageV)
                    )
                }
                GridRow {
                    KeyValueRow(
                        label: L10n.string(.current, language: language),
                        value: ofRated(
                            PowerFormatters.amps(snapshot.adapterInputCurrentA),
                            rated: ratedCurrent > 0.05 ? PowerFormatters.amps(ratedCurrent) : nil
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
        let name = adapter?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? adapter?.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let maker = adapter?.manufacturer?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [name, maker].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func ofRated(_ value: String, rated: String?) -> String {
        rated.map { "\(value) / \($0)" } ?? value
    }

    private func profileChips(_ profiles: [USBPDProfile]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(profiles) { profile in
                let isActive = profile.isActive || profile.index == adapter?.activePDProfileIndex
                Text("\(compact(profile.maxVoltageV, "V"))/\(compact(profile.maxCurrentA, "A"))")
                    .font(PowerFlowTheme.Typography.monoCaptionFloor)
                    .fontWeight(isActive ? .semibold : .medium)
                    .monospacedDigit()
                    .foregroundStyle(
                        isActive
                            ? gold
                            : PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                    )
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                isActive
                                    ? gold.opacity(colorScheme == .dark ? 0.22 : 0.16)
                                    : PowerFlowTheme.nestedTileFill(for: colorScheme, contrast: colorSchemeContrast)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                isActive
                                    ? gold.opacity(colorScheme == .dark ? 0.56 : 0.48)
                                    : PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                                lineWidth: isActive ? 1 : 0.5
                            )
                    )
            }
        }
    }

    private func compact(_ value: Double, _ unit: String) -> String {
        abs(value - value.rounded()) < 0.05
            ? "\(Int(value.rounded()))\(unit)"
            : String(format: "%.2f%@", value, unit)
    }

    private func standbyRow(_ standby: AdapterSourceInfo) -> some View {
        HStack(spacing: 6) {
            PowerFlowChip(
                icon: "pause.circle",
                text: "\(L10n.string(.standby, language: language)) · \(standby.portLabel)",
                tint: PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
            )
            Text(standby.connectedDeviceName ?? standby.name ?? L10n.string(.powerAdapter, language: language))
                .font(PowerFlowTheme.Typography.captionFloor)
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if standby.ratedWatts > 0.5 {
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
