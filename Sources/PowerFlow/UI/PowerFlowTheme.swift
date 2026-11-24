import SwiftUI

enum PowerFlowTheme {
    // Champagne-gold matching the luminous AC supply bar in Dark mode,
    // deepened slightly in Light mode for crisp legibility.
    static func acGold(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.898, green: 0.843, blue: 0.596) // #E5D798
            : Color(red: 0.720, green: 0.575, blue: 0.140)
    }

    static func chargeGreen(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.235, green: 0.845, blue: 0.485)
            : Color(red: 0.085, green: 0.630, blue: 0.300)
    }

    static func dischargeAmber(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.975, green: 0.625, blue: 0.240)
            : Color(red: 0.845, green: 0.440, blue: 0.055)
    }

    static func outboundCyan(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.295, green: 0.825, blue: 0.970)
            : Color(red: 0.025, green: 0.520, blue: 0.760)
    }

    static func warningRed(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 1.000, green: 0.340, blue: 0.310)
            : Color(red: 0.830, green: 0.165, blue: 0.145)
    }

    static func nestedTileFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.055)
            : Color.black.opacity(0.045)
    }

    /// Opaque enough that links appear to end at a node's edge.
    static func nodeFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.13) : Color(white: 0.97)
    }

    static func hairlineDivider(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }

    static func mutedLabel(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.54)
    }

    static func primaryValue(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.88)
    }

    static func secondaryValue(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.66)
    }

    static func batterySymbol(percent: Int, isCharging: Bool) -> String {
        if isCharging {
            return "battery.100percent.bolt"
        }
        switch percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    static func portSymbol(for kind: PowerPortKind) -> String {
        switch kind {
        case .magSafe:
            return "powerplug.fill"
        case .usbC:
            return "cable.connector"
        case .unknown:
            return "powerplug.fill"
        }
    }
}

struct PowerFlowChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String?
    let text: String
    let tint: Color

    init(icon: String? = nil, text: String, tint: Color) {
        self.icon = icon
        self.text = text
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7.5)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(colorScheme == .dark ? 0.30 : 0.24), lineWidth: 0.6)
        )
    }
}
