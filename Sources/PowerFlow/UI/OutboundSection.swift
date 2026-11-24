import SwiftUI

struct OutboundSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let snapshot: PowerSnapshot
    let language: AppLanguage

    private var cyan: Color { PowerFlowTheme.outboundCyan(for: colorScheme) }

    private var activePorts: [OutboundPortPower] {
        snapshot.outboundPorts.filter { $0.powerW > 0.05 || $0.currentA > 0.01 }
    }

    var body: some View {
        PopoverSection(
            icon: "arrow.up.right.circle.fill",
            tint: activePorts.isEmpty ? PowerFlowTheme.mutedLabel(for: colorScheme) : cyan,
            title: L10n.string(.outboundUSBCPower, language: language)
        ) {
            if !activePorts.isEmpty {
                Text("\(PowerFormatters.amps(snapshot.totalOutboundCurrentA)) · \(PowerFormatters.watts(snapshot.totalOutboundPowerW))")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(cyan)
            }
        } content: {
            if activePorts.isEmpty {
                Text(L10n.string(.noOutboundDevices, language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))
            } else {
                VStack(spacing: 6) {
                    ForEach(activePorts) { port in
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
                Text(Self.localizedDeviceName(for: port, language: language))
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

    static func localizedDeviceName(for port: OutboundPortPower, language: AppLanguage) -> String {
        if let name = port.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            if name == "External Display" {
                return L10n.string(.externalDisplay, language: language)
            }
            if name == "USB-C Device" {
                return L10n.string(.usbcDevice, language: language)
            }
            return name
        }
        return port.isDisplayPortActive
            ? L10n.string(.externalDisplay, language: language)
            : L10n.string(.usbcDevice, language: language)
    }
}
