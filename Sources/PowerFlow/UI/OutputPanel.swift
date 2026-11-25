import SwiftUI

/// Output detail tab: what each USB-C port feeds right now.
struct OutputPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let snapshot: PowerSnapshot
    let language: AppLanguage
    var isVisible: Bool = true

    private var teal: Color { PowerFlowTheme.outboundTeal(for: colorScheme, contrast: colorSchemeContrast) }
    private var ports: [OutboundPortPower] { snapshot.outboundPorts }
    private var headerTotal: String {
        "\(PowerFormatters.amps(snapshot.totalOutboundCurrentA)) · \(PowerFormatters.watts(snapshot.totalOutboundPowerW))"
    }

    var body: some View {
        if ports.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                Text(L10n.string(.noOutboundDevices, language: language))
                    .font(.system(size: 12))
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(teal)
                    Text(L10n.string(.outboundOutput, language: language))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(headerTotal)
                        .font(PowerFlowTheme.Typography.popoverRowValue)
                        .powerFlowNumericTransition(value: headerTotal)
                        .foregroundStyle(teal)
                        .fixedSize(horizontal: true, vertical: false)
                }

                ForEach(ports) { port in
                    OutboundPortRow(port: port, language: language, isVisible: isVisible)
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
    var isVisible: Bool = true

    @State private var isHovered = false

    private var teal: Color { PowerFlowTheme.outboundTeal(for: colorScheme, contrast: colorSchemeContrast) }

    private var portSymbol: String {
        port.isDisplayPortActive ? "display" : "cable.connector"
    }

    private var subtitle: String {
        "\(port.portLabel) · \(PowerFormatters.amps(port.currentA)) · \(PowerFormatters.volts(port.voltageV))"
    }

    var body: some View {
        HStack(spacing: 10) {
            GaugeRing(
                fraction: port.maxPDWatts > 0.5 ? port.powerW / port.maxPDWatts : 0,
                tint: teal,
                lineWidth: 3.5,
                isVisible: isVisible
            ) {
                Image(systemName: portSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(teal)
            }
            .frame(width: 34, height: 34)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(port.portLabel)
            .accessibilityValue(PowerFormatters.watts(port.powerW))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.deviceName(for: port, language: language))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(PowerFlowTheme.Typography.captionFloor)
                    .monospacedDigit()
                    .powerFlowNumericTransition(value: subtitle)
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                MetricValueText(
                    text: PowerFormatters.watts(port.powerW),
                    valueFont: .system(size: 15, weight: .semibold, design: .rounded),
                    unitFont: PowerFlowTheme.Typography.unit,
                    valueColor: teal,
                    unitColor: PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                )
                if port.maxPDWatts > 0.5 {
                    Text("/ \(Int(port.maxPDWatts.rounded())) W")
                        .font(PowerFlowTheme.Typography.captionFloor)
                        .monospacedDigit()
                        .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? teal.opacity(colorScheme == .dark ? 0.085 : 0.06) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(PowerFlowTheme.Motion.hover) {
                    isHovered = hovering
                }
            }
        }
    }
}
