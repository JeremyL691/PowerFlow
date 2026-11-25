import AppKit
import QuartzCore
import SwiftUI

/// Big value with a smaller secondary unit, split out of a formatted PowerFormatters string.
struct MetricValueText: View {
    let text: String
    let valueFont: Font
    let unitFont: Font
    let valueColor: Color
    let unitColor: Color

    private var parts: (value: String, unit: String) {
        if text.hasSuffix("%"), text.count > 1 {
            return (String(text.dropLast()), "%")
        }
        if let lastSpace = text.lastIndex(of: " ") {
            return (
                String(text[text.startIndex..<lastSpace]),
                String(text[text.index(after: lastSpace)...])
            )
        }
        return (text, "")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(parts.value)
                .font(valueFont)
                .monospacedDigit()
                .powerFlowNumericTransition(value: parts.value)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(unitFont)
                    .foregroundStyle(unitColor)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
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
                .font(PowerFlowTheme.Typography.popoverRowLabel)
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
                    .font(PowerFlowTheme.Typography.popoverRowValue)
                    .foregroundStyle(resolvedValueColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .powerFlowNumericTransition(value: value)
            }
        }
    }
}

/// Miniature ring gauge in the hero ring's visual language; callers overlay the
/// center content and own the accessibility label/value.
struct GaugeRing<Center: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let fraction: Double
    let tint: Color
    let lineWidth: CGFloat
    let isVisible: Bool
    let center: Center

    @State private var hasRevealed = false
    @State private var displayedFraction: Double = 0

    init(
        fraction: Double,
        tint: Color,
        lineWidth: CGFloat,
        isVisible: Bool = true,
        @ViewBuilder center: () -> Center
    ) {
        self.fraction = fraction
        self.tint = tint
        self.lineWidth = lineWidth
        self.isVisible = isVisible
        self.center = center()
    }

    private var clampedFraction: Double {
        fraction.isFinite ? min(1.0, max(0.0, fraction)) : 0
    }

    private var shown: Double {
        if reduceMotion {
            return (isVisible || hasRevealed) ? clampedFraction : 0
        }
        return displayedFraction
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    PowerFlowTheme.gaugeTrack(for: colorScheme, contrast: colorSchemeContrast),
                    lineWidth: lineWidth
                )
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.7), tint],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            center
        }
        .onAppear {
            guard isVisible, !hasRevealed else { return }
            reveal()
        }
        .onChange(of: isVisible) { _, visible in
            guard visible else { return }
            if !hasRevealed {
                reveal()
            } else if reduceMotion {
                displayedFraction = clampedFraction
            } else {
                withAnimation(PowerFlowTheme.Motion.value) {
                    displayedFraction = clampedFraction
                }
            }
        }
        .onChange(of: clampedFraction) { _, newValue in
            guard isVisible, hasRevealed else { return }
            if reduceMotion {
                displayedFraction = newValue
            } else {
                withAnimation(PowerFlowTheme.Motion.value) {
                    displayedFraction = newValue
                }
            }
        }
    }

    private func reveal() {
        hasRevealed = true
        if reduceMotion {
            displayedFraction = clampedFraction
        } else {
            withAnimation(PowerFlowTheme.Motion.reveal) {
                displayedFraction = clampedFraction
            }
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
                .font(PowerFlowTheme.Typography.popoverRowLabel)
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
                .overlay {
                    if colorSchemeContrast == .increased {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isCopied
                                    ? green.opacity(0.45)
                                    : PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                                lineWidth: 0.7
                            )
                    }
                }
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if reduceMotion {
                    isHovered = hovering
                } else {
                    withAnimation(PowerFlowTheme.Motion.hover) {
                        isHovered = hovering
                    }
                }
            }
            .animation(reduceMotion ? nil : PowerFlowTheme.Motion.value, value: isCopied)
            .help(L10n.tr("Click to copy serial number", zh: "点击复制序列号", language: language))
            .accessibilityLabel(
                "\(label), \(isCopied ? L10n.tr("Copied", zh: "已复制", language: language) : PowerFormatters.maskSerial(serial, masked: isMasked))"
            )
            .accessibilityHint(L10n.tr("Click to copy serial number", zh: "点击复制序列号", language: language))
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

/// 28x28 circular toolbar icon button; Liquid Glass on macOS 26, material circle below.
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
                .frame(width: 28, height: 28)
                .powerFlowSurface(.control(isHovered: isHovered), cornerRadius: 14)
                .overlay {
                    if isDestructiveActive {
                        Circle()
                            .fill(destructiveTint.opacity(colorScheme == .dark ? 0.16 : 0.11))
                            .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(PopoverIconButtonStyle(reduceMotion: reduceMotion))
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(PowerFlowTheme.Motion.hover) {
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
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1.0)
            .animation(reduceMotion ? nil : PowerFlowTheme.Motion.press, value: configuration.isPressed)
    }
}

/// Six-point status dot whose ripple runs in the render server instead of a SwiftUI timer.
struct LivePulseView: NSViewRepresentable {
    var tint: NSColor
    var isPulsing: Bool

    func makeNSView(context: Context) -> LivePulseNSView {
        LivePulseNSView()
    }

    func updateNSView(_ view: LivePulseNSView, context: Context) {
        view.apply(tint: tint, isPulsing: isPulsing)
    }
}

@MainActor
final class LivePulseNSView: NSView {
    private let dotLayer = CAShapeLayer()
    private let rippleLayer = CAShapeLayer()
    private var tint: NSColor?
    private var isPulsing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        rippleLayer.fillColor = nil
        rippleLayer.lineWidth = 1
        rippleLayer.isHidden = true
        layer?.addSublayer(rippleLayer)
        layer?.addSublayer(dotLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTintColor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            rippleLayer.removeAllAnimations()
        } else {
            applyTintColor()
            syncRipple()
        }
    }

    override func layout() {
        super.layout()
        let rect = CGRect(
            x: bounds.midX - 3,
            y: bounds.midY - 3,
            width: 6,
            height: 6
        )
        let circle = CGPath(ellipseIn: CGRect(origin: .zero, size: rect.size), transform: nil)
        dotLayer.bounds = CGRect(origin: .zero, size: rect.size)
        dotLayer.position = CGPoint(x: rect.midX, y: rect.midY)
        dotLayer.path = circle
        rippleLayer.bounds = dotLayer.bounds
        rippleLayer.position = dotLayer.position
        rippleLayer.path = circle
    }

    func apply(tint newTint: NSColor, isPulsing newPulsing: Bool) {
        let tintChanged = newTint != tint
        let pulsingChanged = newPulsing != isPulsing
        guard tintChanged || pulsingChanged else { return }

        tint = newTint
        isPulsing = newPulsing

        if tintChanged {
            applyTintColor()
        }
        if pulsingChanged {
            syncRipple()
        }
    }

    private func applyTintColor() {
        guard let tint else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let resolved = (tint.usingColorSpace(.sRGB) ?? tint).cgColor
            dotLayer.fillColor = resolved
            rippleLayer.strokeColor = resolved
            CATransaction.commit()
        }
    }

    private func syncRipple() {
        rippleLayer.removeAllAnimations()
        guard isPulsing, window != nil else {
            rippleLayer.isHidden = true
            return
        }
        rippleLayer.isHidden = false

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 2.6

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.5
        fade.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.8
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        rippleLayer.add(group, forKey: "ripple")
    }
}
