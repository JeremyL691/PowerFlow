import AppKit
import SwiftUI

/// Titled L2 telemetry container shared across popover sections.
/// When `isQuiet` is true, collapses into a sleek single-line matte strip for idle/unplugged states.
struct PopoverSection<Trailing: View, Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let icon: String
    let tint: Color
    let title: String
    let isQuiet: Bool
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    init(
        icon: String,
        tint: Color,
        title: String,
        isQuiet: Bool = false,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.isQuiet = isQuiet
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        if isQuiet {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 14, alignment: .center)
                Text(title)
                    .font(PowerFlowTheme.Typography.sectionTitle)
                    .foregroundStyle(PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                content
                    .lineLimit(1)
                    .truncationMode(.tail)
                trailing
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .powerFlowSurface(.quietStrip, cornerRadius: 13)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 14, alignment: .center)
                    Text(title)
                        .font(PowerFlowTheme.Typography.sectionTitle)
                        .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    trailing
                }
                content
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .powerFlowSurface(.telemetryGroup, cornerRadius: 13)
        }
    }
}

extension PopoverSection where Trailing == EmptyView {
    init(
        icon: String,
        tint: Color,
        title: String,
        isQuiet: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            icon: icon,
            tint: tint,
            title: title,
            isQuiet: isQuiet,
            trailing: { EmptyView() },
            content: content
        )
    }
}

struct KeyValueRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let label: String
    let value: String
    let valueColor: Color?
    let prefixSymbol: String?

    init(
        label: String,
        value: String,
        valueColor: Color? = nil,
        prefixSymbol: String? = nil
    ) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
        self.prefixSymbol = prefixSymbol
    }

    var body: some View {
        let resolvedValueColor = valueColor ?? PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast)

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(PowerFlowTheme.Typography.rowLabel)
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            HStack(spacing: 3.5) {
                if let prefixSymbol {
                    Image(systemName: prefixSymbol)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(resolvedValueColor)
                }
                Text(value)
                    .font(PowerFlowTheme.Typography.rowValue)
                    .foregroundStyle(resolvedValueColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .powerFlowNumericTransition()
            }
        }
    }
}

struct ProgressLine: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let fraction: Double
    let tint: Color
    let limitFraction: Double?
    let height: CGFloat

    init(
        fraction: Double,
        tint: Color,
        limitFraction: Double? = nil,
        height: CGFloat = 4
    ) {
        self.fraction = fraction
        self.tint = tint
        self.limitFraction = limitFraction
        self.height = height
    }

    var body: some View {
        let clamped = min(1.0, max(0.0, fraction))
        let showLimitTick = limitFraction.map { $0 > 0.02 && $0 < 0.999 } ?? false

        GeometryReader { geo in
            let fillWidth = max(clamped > 0.005 ? max(height, 4) : 0, geo.size.width * clamped)

            ZStack(alignment: .leading) {
                // Recessed gauge trough
                Capsule(style: .continuous)
                    .fill(trackFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast)
                                    .opacity(colorSchemeContrast == .increased ? 0.9 : 0.65),
                                lineWidth: 0.5
                            )
                    )

                // Luminous progress bar with subtle top sheen
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.84), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(colorScheme == .dark ? 0.28 : 0.34), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .frame(width: min(geo.size.width, fillWidth))
                    .animation(reduceMotion ? nil : .spring(duration: 0.38, bounce: 0.12), value: clamped)

                // Crisp Charge-Limit Tick marker when < 100%
                if showLimitTick, let limit = limitFraction {
                    let clampedLimit = min(0.995, max(0.02, limit))
                    let tickX = geo.size.width * clampedLimit
                    let tickHeight = height + 4

                    Capsule(style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.94) : Color(white: 0.14).opacity(0.88))
                        .frame(width: 2, height: tickHeight)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    colorScheme == .dark ? Color.black.opacity(0.55) : Color.white.opacity(0.88),
                                    lineWidth: 0.5
                                )
                        )
                        .position(x: tickX, y: height / 2)
                }
            }
        }
        .frame(height: height)
        .padding(.vertical, showLimitTick ? 2 : 0)
    }

    private var trackFill: Color {
        switch (colorScheme, colorSchemeContrast) {
        case (.dark, .increased):
            return Color.white.opacity(0.18)
        case (.dark, _):
            return Color.white.opacity(0.095)
        case (_, .increased):
            return Color.black.opacity(0.16)
        default:
            return Color.black.opacity(0.08)
        }
    }
}

/// Serial number that copies itself on click with tactile hover pill and animated checkmark confirmation.
struct CopyableSerialRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String
    let serial: String
    let isMasked: Bool
    let language: AppLanguage

    @State private var isCopied = false
    @State private var isHovered = false

    init(label: String, serial: String, isMasked: Bool, language: AppLanguage) {
        self.label = label
        self.serial = serial
        self.isMasked = isMasked
        self.language = language
    }

    var body: some View {
        let green = PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        let isDark = colorScheme == .dark

        HStack(alignment: .center, spacing: 6) {
            Text(label)
                .font(PowerFlowTheme.Typography.rowLabel)
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Button(action: copy) {
                HStack(spacing: 4) {
                    Text(
                        isCopied
                            ? L10n.tr("Copied", zh: "已复制", language: language)
                            : PowerFormatters.maskSerial(serial, masked: isMasked)
                    )
                    .font(PowerFlowTheme.Typography.monoCaptionFloor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 9.5, weight: .semibold))
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                }
                .foregroundStyle(
                    isCopied
                        ? green
                        : (isHovered
                            ? PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast)
                            : PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast))
                )
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isCopied
                                ? green.opacity(isDark ? 0.18 : 0.13)
                                : (isHovered
                                    ? (isDark ? Color.white.opacity(0.095) : Color.black.opacity(0.065))
                                    : PowerFlowTheme.nestedTileFill(for: colorScheme, contrast: colorSchemeContrast))
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isCopied
                                ? green.opacity(isDark ? 0.45 : 0.36)
                                : (isHovered
                                    ? PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast).opacity(1.8)
                                    : PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast)),
                            lineWidth: isCopied ? 0.7 : 0.5
                        )
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if reduceMotion {
                    isHovered = hovering
                } else {
                    withAnimation(.easeOut(duration: 0.14)) {
                        isHovered = hovering
                    }
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.20), value: isCopied)
            .help(L10n.tr("Click to copy serial number", zh: "点击复制序列号", language: language))
        }
        .task(id: isCopied) {
            guard isCopied else { return }
            try? await Task.sleep(for: .seconds(1.6))
            isCopied = false
        }
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(serial, forType: .string)
        isCopied = true
    }
}

/// Tactile toolbar icon button with hover feedback, optional destructive hover wash, and spring press scale.
struct PopoverIconButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let symbol: String
    let helpText: String
    let isDestructiveHover: Bool
    let action: () -> Void

    @State private var isHovered = false

    init(
        symbol: String,
        helpText: String,
        isDestructiveHover: Bool = false,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.helpText = helpText
        self.isDestructiveHover = isDestructiveHover
        self.action = action
    }

    var body: some View {
        let destructiveTint = PowerFlowTheme.warningRed(for: colorScheme, contrast: colorSchemeContrast)
        let isDestructiveActive = isDestructiveHover && isHovered
        let iconColor: Color = if isDestructiveActive {
            destructiveTint
        } else if isHovered {
            PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast)
        } else {
            PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast)
        }

        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 28)
                .powerFlowSurface(.interactiveControl(isHovered: isHovered, isSelected: false), cornerRadius: 8.5)
                .overlay {
                    if isDestructiveActive {
                        let shape = RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                        shape
                            .fill(destructiveTint.opacity(colorScheme == .dark ? 0.16 : 0.11))
                            .overlay(
                                shape.strokeBorder(
                                    destructiveTint.opacity(colorScheme == .dark ? 0.44 : 0.34),
                                    lineWidth: 0.75
                                )
                            )
                            .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(PopoverIconButtonStyle(reduceMotion: reduceMotion))
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
        }
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}

private struct PopoverIconButtonStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
    }
}
