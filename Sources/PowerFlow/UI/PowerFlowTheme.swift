import SwiftUI

enum PowerFlowSurfaceLevel: Equatable, Sendable {
    case tile(isHovered: Bool = false)
    case control(isHovered: Bool = false)
}

enum PowerFlowTheme {
    enum Typography {
        static let heroPercent: Font = .system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()
        static let heroPercentUnit: Font = .system(size: 15, weight: .semibold)
        static let heroPower: Font = .system(size: 26, weight: .semibold, design: .rounded).monospacedDigit()
        static let heroUnit: Font = .system(size: 13, weight: .semibold)
        static let heroDetail: Font = .system(size: 12.5).monospacedDigit()
        static let status: Font = .system(size: 13, weight: .semibold)
        static let tileValue: Font = .system(size: 18, weight: .semibold, design: .rounded).monospacedDigit()
        static let unit: Font = .system(size: 11, weight: .medium)
        static let popoverRowLabel: Font = .system(size: 12, weight: .regular)
        static let popoverRowValue: Font = .system(size: 12, weight: .medium).monospacedDigit()
        static let rowLabel: Font = .system(size: 11.5, weight: .regular)
        static let chip: Font = .system(size: 11, weight: .semibold)
        static let captionFloor: Font = .system(size: 11, weight: .regular)
        static let monoCaptionFloor: Font = .system(size: 11, weight: .medium, design: .monospaced)
    }

    enum Motion {
        static let reveal: Animation = .spring(response: 0.5, dampingFraction: 0.9)
        static let revealStagger: Double = 0.035
        static let tab: Animation = .spring(response: 0.42, dampingFraction: 0.86)
        static let hover: Animation = .easeOut(duration: 0.14)
        static let press: Animation = .spring(response: 0.25, dampingFraction: 0.7)
        static let value: Animation = .spring(response: 0.45, dampingFraction: 0.9)
        static let tint: Animation = .easeInOut(duration: 0.5)
        static let reducedFade: Animation = .easeOut(duration: 0.2)
    }

    // MARK: - Perceptual Semantic Palette (WCAG >= 4.5:1 text, >= 3:1 icons/borders)

    /// Blue theme accent: hero ring, aura, hub, adapter flow and the selected tab.
    static func themeBlue(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color(red: 0.478, green: 0.722, blue: 1.000) // #7AB8FF
        case (.dark, _):
            return Color(red: 0.290, green: 0.616, blue: 1.000) // #4A9DFF
        case (_, .increased):
            return Color(red: 0.000, green: 0.294, blue: 0.690) // #004BB0
        default:
            return Color(red: 0.000, green: 0.376, blue: 0.875) // #0060DF
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

    static func outboundTeal(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color(red: 0.478, green: 0.922, blue: 0.859) // #7AEBDB
        case (.dark, _):
            return Color(red: 0.243, green: 0.859, blue: 0.776) // #3EDBC6
        case (_, .increased):
            return Color(red: 0.000, green: 0.373, blue: 0.329) // #005F54
        default:
            return Color(red: 0.000, green: 0.475, blue: 0.420) // #00796B
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

    /// Quiet matte fill for tiles and the detail panel.
    static func tileFill(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard, isHovered: Bool = false) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color.white.opacity(isHovered ? 0.12 : 0.09)
        case (.dark, _):
            return Color.white.opacity(isHovered ? 0.085 : 0.055)
        case (_, .increased):
            return Color.black.opacity(isHovered ? 0.09 : 0.06)
        default:
            return Color.black.opacity(isHovered ? 0.06 : 0.035)
        }
    }

    /// Shared gauge track: hero ring and every GaugeRing stroke it with the same tone.
    static func gaugeTrack(for scheme: ColorScheme, contrast: ColorSchemeContrast = .standard) -> Color {
        switch (scheme, contrast) {
        case (.dark, .increased):
            return Color.white.opacity(0.20)
        case (.dark, _):
            return Color.white.opacity(0.10)
        case (_, .increased):
            return Color.black.opacity(0.16)
        default:
            return Color.black.opacity(0.07)
        }
    }

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

    // MARK: - Locale & Hardware Symbols

    static func locale(for language: AppLanguage) -> Locale {
        switch L10n.resolvedLanguage(for: language) {
        case .simplifiedChinese:
            return Locale(identifier: "zh_Hans")
        case .english, .system:
            return Locale(identifier: "en_US")
        }
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

    /// Numeric-text roll plus Motion.value keyed on the displayed value, so live
    /// digits drift instead of snapping. Identity under Reduce Motion.
    @MainActor
    func powerFlowNumericTransition<Value: Equatable>(value: Value) -> some View {
        modifier(PowerFlowValueTransitionModifier(value: value))
    }

    @MainActor
    func powerFlowReveal(index: Int, hasAppeared: Bool, reduceMotion: Bool) -> some View {
        modifier(PowerFlowReveal(index: index, hasAppeared: hasAppeared, reduceMotion: reduceMotion))
    }
}

private struct PowerFlowValueTransitionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Value

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : PowerFlowTheme.Motion.value, value: value)
    }
}

/// Staggered entrance: fade, rise, un-blur and un-squash in one Motion.reveal spring.
struct PowerFlowReveal: ViewModifier {
    let index: Int
    let hasAppeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
                .opacity(hasAppeared ? 1 : 0)
                .animation(PowerFlowTheme.Motion.reducedFade, value: hasAppeared)
        } else {
            content
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 8)
                .scaleEffect(hasAppeared ? 1 : 0.985, anchor: .top)
                .animation(
                    PowerFlowTheme.Motion.reveal.delay(Double(index) * PowerFlowTheme.Motion.revealStagger),
                    value: hasAppeared
                )
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
        case .tile(let isHovered):
            content
                .background(
                    shape.fill(PowerFlowTheme.tileFill(for: colorScheme, contrast: colorSchemeContrast, isHovered: isHovered))
                )
                .overlay {
                    if colorSchemeContrast == .increased {
                        shape.strokeBorder(
                            PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                            lineWidth: 0.85
                        )
                    }
                }
                .clipShape(shape)

        case .control(let isHovered):
            controlBody(content: content, isHovered: isHovered, shape: shape)
        }
    }

    @ViewBuilder
    private func controlBody(
        content: Content,
        isHovered: Bool,
        shape: RoundedRectangle
    ) -> some View {
        if #available(macOS 26.0, *) {
            let glass: Glass = isHovered
                ? Glass.regular.tint((colorScheme == .dark ? Color.white : Color.black).opacity(colorScheme == .dark ? 0.10 : 0.05)).interactive()
                : Glass.regular.interactive()

            content
                .glassEffect(glass, in: shape)
                .overlay {
                    if colorSchemeContrast == .increased {
                        shape.strokeBorder(
                            PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                            lineWidth: 0.85
                        )
                    }
                }
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(controlFallbackFill(isHovered: isHovered))
                }
                .overlay {
                    if colorSchemeContrast == .increased {
                        shape.strokeBorder(
                            PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                            lineWidth: 0.85
                        )
                    }
                }
                .clipShape(shape)
        }
    }

    private func controlFallbackFill(isHovered: Bool) -> Color {
        let isDark = colorScheme == .dark
        if isHovered {
            return isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.065)
        }
        return PowerFlowTheme.tileFill(for: colorScheme, contrast: colorSchemeContrast)
    }
}
