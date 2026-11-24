import SwiftUI

struct OutboundSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: PowerSnapshot
    let language: AppLanguage

    private var cyan: Color { PowerFlowTheme.outboundCyan(for: colorScheme) }

    private var ports: [OutboundPortPower] { snapshot.outboundPorts }

    var body: some View {
        PopoverSection(
            icon: "arrow.up.right.circle.fill",
            tint: ports.isEmpty ? PowerFlowTheme.mutedLabel(for: colorScheme) : cyan,
            title: L10n.string(.outboundUSBCPower, language: language)
        ) {
            if !ports.isEmpty {
                Text("\(PowerFormatters.amps(snapshot.totalOutboundCurrentA)) · \(PowerFormatters.watts(snapshot.totalOutboundPowerW))")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(cyan)
            }
        } content: {
            if ports.isEmpty {
                Text(L10n.string(.noOutboundDevices, language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))
            } else {
                VStack(spacing: 6) {
                    ForEach(ports) { port in
                        portRow(port)
                    }
                }
            }
        }
    }

    private func portRow(_ port: OutboundPortPower) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                PowerFlowChip(text: port.portLabel, tint: cyan)
                Text(L10n.deviceName(for: port, language: language))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text("\(PowerFormatters.amps(port.currentA)) · \(PowerFormatters.volts(port.voltageV))")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))
                Text(PowerFormatters.watts(port.powerW))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(cyan)
                    .frame(minWidth: 48, alignment: .trailing)
            }
            if port.maxPDWatts > 0.5 {
                ProgressLine(fraction: port.powerW / port.maxPDWatts, tint: cyan)
            }
        }
    }
}
