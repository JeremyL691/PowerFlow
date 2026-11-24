import SwiftUI

enum PowerFlowTheme {
    // Champagne-gold matching the luminous AC supply bar in Dark mode,
    // deepened slightly in Light mode for crisp legibility.
    static func acGold(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.898, green: 0.843, blue: 0.596) // #E5D798
            : Color(red: 0.720, green: 0.575, blue: 0.140)
    }

    static func acGoldGlow(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.992, green: 0.960, blue: 0.790)
            : Color(red: 0.880, green: 0.745, blue: 0.280)
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

    static func systemIndigo(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.530, green: 0.590, blue: 1.000)
            : Color(red: 0.290, green: 0.350, blue: 0.820)
    }

    static func displayViolet(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.760, green: 0.540, blue: 0.980)
            : Color(red: 0.540, green: 0.270, blue: 0.780)
    }

    static func warningRed(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 1.000, green: 0.340, blue: 0.310)
            : Color(red: 0.830, green: 0.165, blue: 0.145)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.11).opacity(0.68)
            : Color.white.opacity(0.74)
    }

    static func nestedTileFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.055)
            : Color.black.opacity(0.045)
    }

    static func pillFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(white: 0.09).opacity(0.82)
            : Color.black.opacity(0.055)
    }

    static func cardBorderGradient(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.white.opacity(0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.13)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
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

struct PowerFlowCardContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let padding: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = 16,
        padding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                // The window already provides the blurred backdrop; a second material or a shadow per
                // card would make the window server recomposite the whole window on every change.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PowerFlowTheme.cardFill(for: colorScheme))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(PowerFlowTheme.cardBorderGradient(for: colorScheme), lineWidth: 0.75)
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
