import SwiftUI

enum PowerFlowSurfaceLevel: Equatable, Sendable {
    case heroStage(accent: Color? = nil)
    case telemetryGroup
    case quietStrip
    case interactiveControl(isHovered: Bool = false, isSelected: Bool = false)
}

enum PowerFlowTheme {
    enum Typography {
        static let heroSoC: Font = .system(size: 28, weight: .semibold, design: .rounded).monospacedDigit()
        static let heroSubvalue: Font = .system(size: 11.5, weight: .medium).monospacedDigit()
        static let sectionTitle: Font = .system(size: 12, weight: .semibold)
        static let metricValue: Font = .system(size: 13.5, weight: .semibold, design: .rounded).monospacedDigit()
        static let nodeHubValue: Font = .system(size: 15, weight: .semibold, design: .rounded).monospacedDigit()
        static let nodeValue: Font = .system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit()
        static let rowLabel: Font = .system(size: 11.5, weight: .regular)
        static let rowValue: Font = .system(size: 11.5, weight: .medium).monospacedDigit()
        static let chip: Font = .system(size: 11, weight: .semibold)
        static let captionFloor: Font = .system(size: 11, weight: .regular)
        static let monoCaptionFloor: Font = .system(size: 11, weight: .medium, design: .monospaced)
    }

    // MARK: - Perceptual Semantic Palette (WCAG >= 4.5:1 text, >= 3:1 icons/borders)

    /// Luminous champagne gold in Dark mode; rich burnished gold in Light mode.
    static func acGold(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color(red: 0.969, green: 0.898, blue: 0.659) // #F7E5A8
        case (.dark, _):
            return Color(red: 0.941, green: 0.851, blue: 0.549) // #F0D98C
        case (_, .increased):
            return Color(red: 0.451, green: 0.290, blue: 0.000) // #734A00
        default:
            return Color(red: 0.569, green: 0.373, blue: 0.000) // #915F00
        }
    }

    static func chargeGreen(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color(red: 0.353, green: 0.941, blue: 0.588) // #5AF096
        case (.dark, _):
            return Color(red: 0.220, green: 0.878, blue: 0.482) // #38E07B
        case (_, .increased):
            return Color(red: 0.027, green: 0.369, blue: 0.176) // #075E2D
        default:
            return Color(red: 0.043, green: 0.478, blue: 0.231) // #0B7A3B
        }
    }

    static func dischargeAmber(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color(red: 1.000, green: 0.737, blue: 0.420) // #FFBC6B
        case (.dark, _):
            return Color(red: 1.000, green: 0.643, blue: 0.231) // #FFA43B
        case (_, .increased):
            return Color(red: 0.541, green: 0.235, blue: 0.000) // #8A3C00
        default:
            return Color(red: 0.667, green: 0.294, blue: 0.000) // #AA4B00
        }
    }

    static func outboundCyan(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color(red: 0.471, green: 0.878, blue: 1.000) // #78E0FF
        case (.dark, _):
            return Color(red: 0.290, green: 0.831, blue: 1.000) // #4AD4FF
        case (_, .increased):
            return Color(red: 0.000, green: 0.322, blue: 0.478) // #00527A
        default:
            return Color(red: 0.000, green: 0.420, blue: 0.620) // #006B9E
        }
    }

    static func warningRed(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color(red: 1.000, green: 0.522, blue: 0.502) // #FF8580
        case (.dark, _):
            return Color(red: 1.000, green: 0.400, blue: 0.380) // #FF6661
        case (_, .increased):
            return Color(red: 0.620, green: 0.075, blue: 0.063) // #9E1310
        default:
            return Color(red: 0.769, green: 0.118, blue: 0.102) // #C41E1A
        }
    }

    // MARK: - Surface & Elevation Tokens

    /// L2 quiet recessed matte fill for telemetry groups and sub-tiles.
    static func nestedTileFill(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color.white.opacity(0.065)
        case (.dark, _):
            return Color.white.opacity(0.038)
        case (_, .increased):
            return Color.black.opacity(0.055)
        default:
            return Color.black.opacity(0.030)
        }
    }

    /// L1 Hero Stage base tint: Space Black (#14161B) in Dark mode, Frosted Silver (#F6F7FA) in Light mode.
    static func heroStageFill(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color(red: 0.078, green: 0.086, blue: 0.106).opacity(0.84)
        case (.dark, _):
            return Color(red: 0.078, green: 0.086, blue: 0.106).opacity(0.72)
        case (_, .increased):
            return Color(red: 0.965, green: 0.969, blue: 0.980).opacity(0.92)
        default:
            return Color(red: 0.965, green: 0.969, blue: 0.980).opacity(0.82)
        }
    }

    /// Opaque sculptural node surface so energy links terminate cleanly at node boundaries.
    static func nodeFill(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color(red: 0.098, green: 0.106, blue: 0.125) // #191B20
        case (.dark, _):
            return Color(red: 0.118, green: 0.125, blue: 0.145) // #1E2025
        case (_, .increased):
            return Color(red: 0.992, green: 0.994, blue: 0.998)
        default:
            return Color(red: 0.984, green: 0.986, blue: 0.992) // #FBFBFD
        }
    }

    static func hairlineDivider(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color.white.opacity(0.34)
        case (.dark, _):
            return Color.white.opacity(0.085)
        case (_, .increased):
            return Color.black.opacity(0.32)
        default:
            return Color.black.opacity(0.075)
        }
    }

    /// Directional top-lit specular hairline rim for elevated surfaces and sculptural nodes.
    static func specularRimGradient(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> LinearGradient {
        let stops: [Gradient.Stop]
        switch (scheme, contrast) {
        case (.dark, .increased):
            stops = [
                .init(color: Color.white.opacity(0.46), location: 0.0),
                .init(color: Color.white.opacity(0.26), location: 1.0)
            ]
        case (.dark, _):
            stops = [
                .init(color: Color.white.opacity(0.22), location: 0.0),
                .init(color: Color.white.opacity(0.09), location: 0.38),
                .init(color: Color.white.opacity(0.04), location: 1.0)
            ]
        case (_, .increased):
            stops = [
                .init(color: Color.black.opacity(0.34), location: 0.0),
                .init(color: Color.black.opacity(0.22), location: 1.0)
            ]
        default:
            stops = [
                .init(color: Color.white.opacity(0.82), location: 0.0),
                .init(color: Color.white.opacity(0.42), location: 0.45),
                .init(color: Color.white.opacity(0.22), location: 1.0)
            ]
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Neutral Ink Tokens (Never pure #000 / #FFF)

    static func mutedLabel(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color.white.opacity(0.82)
        case (.dark, _):
            return Color.white.opacity(0.64)
        case (_, .increased):
            return Color(red: 0.075, green: 0.082, blue: 0.098).opacity(0.82)
        default:
            return Color(red: 0.075, green: 0.082, blue: 0.098).opacity(0.64)
        }
    }

    static func primaryValue(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color(white: 0.985)
        case (.dark, _):
            return Color(white: 0.96)
        case (_, .increased):
            return Color(red: 0.055, green: 0.062, blue: 0.078).opacity(0.96)
        default:
            return Color(red: 0.075, green: 0.082, blue: 0.098).opacity(0.90)
        }
    }

    static func secondaryValue(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color.white.opacity(0.90)
        case (.dark, _):
            return Color.white.opacity(0.78)
        case (_, .increased):
            return Color(red: 0.075, green: 0.082, blue: 0.098).opacity(0.88)
        default:
            return Color(red: 0.075, green: 0.082, blue: 0.098).opacity(0.76)
        }
    }

    // MARK: - Hardware Symbols

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

// MARK: - PowerFlowChip

struct PowerFlowChip: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let icon: String?
    let text: String
    let tint: Color
    let isProminent: Bool

    init(icon: String? = nil, text: String, tint: Color, isProminent: Bool = false) {
        self.icon = icon
        self.text = text
        self.tint = tint
        self.isProminent = isProminent
    }

    var body: some View {
        let isDark = colorScheme == .dark
        let isHighContrast = colorSchemeContrast == .increased
        let fillAlpha: Double = if isProminent {
            isDark ? (isHighContrast ? 0.28 : 0.20) : (isHighContrast ? 0.22 : 0.14)
        } else {
            isDark ? (isHighContrast ? 0.22 : 0.14) : (isHighContrast ? 0.16 : 0.10)
        }
        let strokeAlpha: Double = if isProminent {
            isDark ? (isHighContrast ? 0.62 : 0.42) : (isHighContrast ? 0.56 : 0.34)
        } else {
            isDark ? (isHighContrast ? 0.48 : 0.28) : (isHighContrast ? 0.42 : 0.22)
        }

        HStack(spacing: 4.5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(isProminent ? PowerFlowTheme.Typography.chip : .system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, isProminent ? 8.5 : 7.5)
        .padding(.vertical, isProminent ? 3.5 : 3)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(fillAlpha))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(strokeAlpha), lineWidth: isProminent || isHighContrast ? 0.75 : 0.55)
        )
    }
}

// MARK: - View Modifiers (Surface Hierarchy, Liquid Glass Encapsulation & Motion)

extension View {
    @MainActor
    func powerFlowSurface(_ level: PowerFlowSurfaceLevel, cornerRadius: CGFloat = 13) -> some View {
        modifier(PowerFlowSurfaceModifier(level: level, cornerRadius: cornerRadius))
    }

    @MainActor
    @ViewBuilder
    func powerFlowGlassGroup(spacing: CGFloat = 8) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                self
            }
        } else {
            self
        }
    }

    @MainActor
    func powerFlowNumericTransition() -> some View {
        modifier(PowerFlowNumericTransitionModifier())
    }
}

private struct PowerFlowNumericTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.contentTransition(.identity)
        } else {
            content.contentTransition(.numericText())
        }
    }
}

private struct PowerFlowSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let level: PowerFlowSurfaceLevel
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        switch level {
        case .heroStage(let accent):
            heroStageBody(content: content, accent: accent, shape: shape)

        case .telemetryGroup:
            content
                .background(
                    shape.fill(PowerFlowTheme.nestedTileFill(for: colorScheme, contrast: colorSchemeContrast))
                )
                .overlay(
                    shape.strokeBorder(
                        PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                        lineWidth: colorSchemeContrast == .increased ? 0.85 : 0.5
                    )
                )
                .clipShape(shape)

        case .quietStrip:
            content
                .background(
                    shape.fill(quietStripFill)
                )
                .overlay(
                    shape.strokeBorder(
                        PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                        lineWidth: colorSchemeContrast == .increased ? 0.85 : 0.5
                    )
                )
                .clipShape(shape)

        case .interactiveControl(let isHovered, let isSelected):
            interactiveControlBody(
                content: content,
                isHovered: isHovered,
                isSelected: isSelected,
                shape: shape
            )
        }
    }

    private var quietStripFill: Color {
        switch (colorScheme, colorSchemeContrast) {
        case (.dark, .increased):
            return Color.white.opacity(0.055)
        case (.dark, _):
            return Color.white.opacity(0.032)
        case (_, .increased):
            return Color.black.opacity(0.048)
        default:
            return Color.black.opacity(0.026)
        }
    }

    @ViewBuilder
    private func heroStageBody(
        content: Content,
        accent: Color?,
        shape: RoundedRectangle
    ) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    shape.fill(
                        PowerFlowTheme.heroStageFill(for: colorScheme, contrast: colorSchemeContrast)
                            .opacity(colorScheme == .dark ? 0.62 : 0.68)
                    )
                    if let accent {
                        heroAura(accent: accent)
                    }
                }
                .glassEffect(
                    accent.map { Glass.regular.tint($0.opacity(0.06)) } ?? .regular,
                    in: shape
                )
                .overlay {
                    heroRimOverlay(shape: shape)
                }
                .clipShape(shape)
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(PowerFlowTheme.heroStageFill(for: colorScheme, contrast: colorSchemeContrast))
                    if let accent {
                        heroAura(accent: accent)
                    }
                }
                .overlay {
                    heroRimOverlay(shape: shape)
                }
                .clipShape(shape)
        }
    }

    private func heroAura(accent: Color) -> some View {
        RadialGradient(
            colors: [
                accent.opacity(colorScheme == .dark ? 0.11 : 0.07),
                accent.opacity(colorScheme == .dark ? 0.03 : 0.018),
                .clear
            ],
            center: UnitPoint(x: 0.5, y: 0.0),
            startRadius: 8,
            endRadius: 210
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func heroRimOverlay(shape: RoundedRectangle) -> some View {
        if colorScheme == .dark || colorSchemeContrast == .increased {
            shape.strokeBorder(
                PowerFlowTheme.specularRimGradient(for: colorScheme, contrast: colorSchemeContrast),
                lineWidth: colorSchemeContrast == .increased ? 1.0 : 0.75
            )
        } else {
            ZStack {
                shape.strokeBorder(
                    PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                    lineWidth: 0.6
                )
                shape
                    .inset(by: 0.5)
                    .strokeBorder(
                        PowerFlowTheme.specularRimGradient(for: colorScheme, contrast: colorSchemeContrast),
                        lineWidth: 0.75
                    )
            }
        }
    }

    @ViewBuilder
    private func interactiveControlBody(
        content: Content,
        isHovered: Bool,
        isSelected: Bool,
        shape: RoundedRectangle
    ) -> some View {
        let isDark = colorScheme == .dark
        let isHighContrast = colorSchemeContrast == .increased

        let borderColor: Color = if isSelected {
            Color.accentColor.opacity(isDark ? 0.78 : 0.68)
        } else if isHovered {
            isDark ? Color.white.opacity(isHighContrast ? 0.45 : 0.20) : Color.black.opacity(isHighContrast ? 0.38 : 0.16)
        } else {
            PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast)
        }
        let borderWidth: CGFloat = isSelected ? 1.0 : (isHighContrast ? 0.85 : 0.55)

        if #available(macOS 26.0, *) {
            let glass: Glass = if isSelected {
                Glass.regular.tint(Color.accentColor.opacity(isDark ? 0.18 : 0.12)).interactive()
            } else if isHovered {
                Glass.regular.tint((isDark ? Color.white : Color.black).opacity(isDark ? 0.10 : 0.05)).interactive()
            } else {
                Glass.regular.interactive()
            }

            content
                .background(shape.fill(interactiveFallbackFill(isHovered: isHovered, isSelected: isSelected).opacity(0.55)))
                .glassEffect(glass, in: shape)
                .overlay(shape.strokeBorder(borderColor, lineWidth: borderWidth))
                .clipShape(shape)
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(interactiveFallbackFill(isHovered: isHovered, isSelected: isSelected))
                }
                .overlay(shape.strokeBorder(borderColor, lineWidth: borderWidth))
                .clipShape(shape)
        }
    }

    private func interactiveFallbackFill(isHovered: Bool, isSelected: Bool) -> Color {
        let isDark = colorScheme == .dark
        if isSelected {
            return Color.accentColor.opacity(isDark ? 0.18 : 0.12)
        }
        if isHovered {
            return isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.065)
        }
        return PowerFlowTheme.nestedTileFill(for: colorScheme, contrast: colorSchemeContrast)
    }
}
