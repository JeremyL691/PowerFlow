import SwiftUI

struct OutboundSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let snapshot: PowerSnapshot
    let language: AppLanguage

    private var cyan: Color { PowerFlowTheme.outboundCyan(for: colorScheme, contrast: colorSchemeContrast) }
    private var ports: [OutboundPortPower] { snapshot.outboundPorts }
    private var isQuiet: Bool { ports.isEmpty }

    var body: some View {
        PopoverSection(
            icon: "arrow.up.right.circle.fill",
            tint: isQuiet ? PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast) : cyan,
            title: L10n.string(.outboundUSBCPower, language: language),
            isQuiet: isQuiet
        ) {
            if isQuiet {
                Text(L10n.string(.noOutboundDevices, language: language))
                    .font(PowerFlowTheme.Typography.captionFloor)
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text("\(PowerFormatters.amps(snapshot.totalOutboundCurrentA)) · \(PowerFormatters.watts(snapshot.totalOutboundPowerW))")
                    .font(PowerFlowTheme.Typography.rowValue)
                    .monospacedDigit()
                    .powerFlowNumericTransition()
                    .foregroundStyle(cyan)
                    .fixedSize(horizontal: true, vertical: false)
            }
        } content: {
            if isQuiet {
                EmptyView()
            } else {
                VStack(spacing: 4) {
                    ForEach(ports) { port in
                        OutboundPortRow(port: port, language: language)
                    }
                }
            }
        }
    }
}

private struct OutboundPortRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let port: OutboundPortPower
    let language: AppLanguage

    @State private var isHovered = false

    private var cyan: Color { PowerFlowTheme.outboundCyan(for: colorScheme, contrast: colorSchemeContrast) }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                PowerFlowChip(text: port.portLabel, tint: cyan)

                Text(L10n.deviceName(for: port, language: language))
                    .font(PowerFlowTheme.Typography.rowLabel)
                    .fontWeight(.medium)
                    .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                Text("\(PowerFormatters.amps(port.currentA)) · \(PowerFormatters.volts(port.voltageV))")
                    .font(PowerFlowTheme.Typography.captionFloor)
                    .monospacedDigit()
                    .powerFlowNumericTransition()
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                    .fixedSize(horizontal: true, vertical: false)

                Text(PowerFormatters.watts(port.powerW))
                    .font(PowerFlowTheme.Typography.rowValue)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .powerFlowNumericTransition()
                    .foregroundStyle(cyan)
                    .frame(minWidth: 52, alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if port.maxPDWatts > 0.5 {
                ProgressLine(
                    fraction: port.powerW / port.maxPDWatts,
                    tint: cyan,
                    height: 3.5
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? cyan.opacity(colorScheme == .dark ? 0.085 : 0.06) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
        }
    }
}
