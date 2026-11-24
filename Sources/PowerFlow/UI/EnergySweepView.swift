import AppKit
import SwiftUI

enum SweepingFlowDirection: Equatable, Sendable {
    case idle
    case leftToRight
    case rightToLeft
}

/// Maps power to sweep speed and brightness.
enum EnergySweepDynamics {
    static func cyclesPerSecond(for watts: Double) -> Double {
        min(1.05, max(0.36, 0.36 + log10(1.0 + max(0.0, watts)) * 0.34))
    }

    static func intensity(for watts: Double) -> Double {
        min(1.0, max(0.42, 0.42 + log10(1.0 + max(0.0, watts)) * 0.28))
    }
}

// MARK: - SwiftUI Wrappers

/// Main supply bar: moving energy field with the live figures on top.
struct SweepingEnergyCapsule: View {
    @Environment(\.colorScheme) private var colorScheme

    let watts: Double
    let primaryText: String
    let secondaryText: String?
    let direction: SweepingFlowDirection
    let baseTint: Color
    let glowTint: Color
    let height: CGFloat
    let cornerRadius: CGFloat
    let isAnimating: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(PowerFlowTheme.pillFill(for: colorScheme))

            EnergySweepLayerView(
                style: .capsule,
                watts: watts,
                direction: direction,
                baseTint: baseTint,
                glowTint: glowTint,
                cornerRadius: cornerRadius,
                isDark: colorScheme == .dark,
                isAnimating: isAnimating
            )

            figures
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderGradient, lineWidth: 0.85)
        )
    }

    private var figures: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(primaryText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(colorScheme == .dark ? Color.white : PowerFlowTheme.primaryValue(for: colorScheme))
                .shadow(
                    color: colorScheme == .dark ? Color.black.opacity(0.55) : Color.white.opacity(0.65),
                    radius: 3,
                    y: 1
                )

            if let secondaryText {
                Text(secondaryText)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        colorScheme == .dark
                            ? Color.white.opacity(0.80)
                            : PowerFlowTheme.secondaryValue(for: colorScheme)
                    )
                    .shadow(
                        color: colorScheme == .dark ? Color.black.opacity(0.45) : Color.clear,
                        radius: 2,
                        y: 1
                    )
            }
        }
        .padding(.horizontal, 12)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var borderGradient: LinearGradient {
        guard direction != .idle else {
            return PowerFlowTheme.cardBorderGradient(for: colorScheme)
        }
        return LinearGradient(
            colors: [
                baseTint.opacity(colorScheme == .dark ? 0.48 : 0.38),
                baseTint.opacity(colorScheme == .dark ? 0.16 : 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Battery and outbound branches: a single soft band behind the row content.
struct EnergySweepBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let watts: Double
    let direction: SweepingFlowDirection
    let tint: Color
    let cornerRadius: CGFloat
    let isAnimating: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(PowerFlowTheme.nestedTileFill(for: colorScheme))

            if direction != .idle {
                EnergySweepLayerView(
                    style: .branch,
                    watts: watts,
                    direction: direction,
                    baseTint: tint,
                    glowTint: tint,
                    cornerRadius: cornerRadius,
                    isDark: colorScheme == .dark,
                    isAnimating: isAnimating
                )
            }
        }
    }
}

// MARK: - Core Animation Bridge

private struct EnergySweepLayerView: NSViewRepresentable {
    let style: EnergySweepNSView.Style
    let watts: Double
    let direction: SweepingFlowDirection
    let baseTint: Color
    let glowTint: Color
    let cornerRadius: CGFloat
    let isDark: Bool
    let isAnimating: Bool

    func makeNSView(context: Context) -> EnergySweepNSView {
        EnergySweepNSView(style: style)
    }

    func updateNSView(_ view: EnergySweepNSView, context: Context) {
        view.apply(
            EnergySweepNSView.Configuration(
                base: NSColor(baseTint),
                glow: NSColor(glowTint),
                direction: direction,
                cornerRadius: cornerRadius,
                isDark: isDark,
                isAnimating: isAnimating && direction != .idle && watts >= 0.05
            ),
            speed: EnergySweepDynamics.cyclesPerSecond(for: watts) * (style == .branch ? 0.85 : 1.0),
            intensity: EnergySweepDynamics.intensity(for: watts)
        )
    }
}

/// Runs the sweep entirely in the render server: the app only does work when the configuration
/// changes, never per frame.
final class EnergySweepNSView: NSView {
    enum Style {
        case capsule
        case branch
    }

    struct Configuration: Equatable {
        let base: NSColor
        let glow: NSColor
        let direction: SweepingFlowDirection
        let cornerRadius: CGFloat
        let isDark: Bool
        let isAnimating: Bool
    }

    private static let frameRate = CAFrameRateRange(minimum: 24, maximum: 60, preferred: 30)
    private static let shimmerSpeedRatio = 0.62
    private static let staticPhase: CGFloat = 0.56
    private static let speedTolerance: Float = 0.04

    private let style: Style
    private let field = CALayer()
    private let ambient = CAGradientLayer()
    private let shimmer = CAGradientLayer()
    private let comet = CAGradientLayer()
    private let sheen = CAGradientLayer()

    private var configuration: Configuration?
    private var animatedSize: CGSize = .zero

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous

        for gradient in [ambient, shimmer, comet] {
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            field.addSublayer(gradient)
        }
        sheen.startPoint = CGPoint(x: 0.5, y: 1)
        sheen.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(field)
        if style == .capsule {
            layer?.addSublayer(sheen)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func apply(_ newConfiguration: Configuration, speed: Double, intensity: Double) {
        withoutImplicitAnimations {
            if newConfiguration != configuration {
                let restart = configuration?.isAnimating != newConfiguration.isAnimating
                configuration = newConfiguration
                updateColors(newConfiguration)
                layer?.cornerRadius = newConfiguration.cornerRadius
                field.setAffineTransform(
                    newConfiguration.direction == .rightToLeft ? CGAffineTransform(scaleX: -1, y: 1) : .identity
                )
                if restart {
                    rebuildMotion()
                }
            }
            field.opacity = Float(newConfiguration.isAnimating ? 0.6 + 0.4 * intensity : 0.85)
            setSpeed(speed, on: comet)
            setSpeed(speed * Self.shimmerSpeedRatio, on: shimmer)
        }
    }

    override func layout() {
        super.layout()
        withoutImplicitAnimations {
            field.bounds = CGRect(origin: .zero, size: bounds.size)
            field.position = CGPoint(x: bounds.midX, y: bounds.midY)
            ambient.frame = field.bounds
            let sheenHeight = bounds.height * 0.46
            sheen.frame = CGRect(x: 0, y: bounds.maxY - sheenHeight, width: bounds.width, height: sheenHeight)
            if bounds.size != animatedSize {
                rebuildMotion()
            }
        }
    }

    // MARK: - Motion

    private func rebuildMotion() {
        animatedSize = bounds.size
        comet.removeAllAnimations()
        shimmer.removeAllAnimations()
        guard bounds.width > 0, bounds.height > 0 else { return }

        let width = bounds.width
        let cometWidth = style == .capsule ? max(width * 0.68, 120) : max(width * 0.56, 92)
        let shimmerWidth = max(width * 0.62, 110)
        place(comet, width: cometWidth, centerShift: -0.10, phase: Self.staticPhase)
        place(shimmer, width: shimmerWidth, centerShift: 0, phase: 0.26)

        guard configuration?.isAnimating == true else { return }
        addSweep(to: comet, width: cometWidth, centerShift: -0.10, initialPhase: 0.24)
        if style == .capsule {
            addSweep(to: shimmer, width: shimmerWidth, centerShift: 0, initialPhase: 0.72)
        }
    }

    private func centerX(width bandWidth: CGFloat, centerShift: CGFloat, phase: CGFloat) -> CGFloat {
        -bandWidth * 0.35 + (bounds.width + bandWidth * 0.70) * phase + bandWidth * centerShift
    }

    private func place(_ band: CAGradientLayer, width: CGFloat, centerShift: CGFloat, phase: CGFloat) {
        band.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        band.position = CGPoint(
            x: centerX(width: width, centerShift: centerShift, phase: phase),
            y: bounds.midY
        )
        band.opacity = 1
    }

    private func addSweep(to band: CAGradientLayer, width: CGFloat, centerShift: CGFloat, initialPhase: Double) {
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = centerX(width: width, centerShift: centerShift, phase: 0)
        move.toValue = centerX(width: width, centerShift: centerShift, phase: 1)

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.5, 1, 1, 0.5, 0]
        fade.keyTimes = [0, 0.08, 0.16, 0.84, 0.92, 1]

        let sweep = CAAnimationGroup()
        sweep.animations = [move, fade]
        sweep.duration = 1
        sweep.timeOffset = initialPhase
        sweep.repeatCount = .infinity
        sweep.isRemovedOnCompletion = false
        sweep.preferredFrameRateRange = Self.frameRate
        band.add(sweep, forKey: "sweep")
    }

    /// Changes the layer clock rate without moving the band.
    private func setSpeed(_ speed: Double, on band: CALayer) {
        let target = Float(speed)
        guard abs(band.speed - target) > Self.speedTolerance else { return }
        let now = CACurrentMediaTime()
        let local = band.convertTime(now, from: nil)
        band.timeOffset = 0
        band.beginTime = 0
        band.speed = target
        band.timeOffset = local - band.convertTime(now, from: nil)
    }

    // MARK: - Colors

    private func updateColors(_ configuration: Configuration) {
        let isDark = configuration.isDark
        let base = configuration.base
        let glow = configuration.glow
        func color(_ color: NSColor, _ alpha: CGFloat) -> CGColor {
            color.withAlphaComponent(alpha).cgColor
        }

        guard configuration.direction != .idle else {
            ambient.colors = [color(base, 0.05), color(base, 0.05)]
            ambient.locations = nil
            comet.isHidden = true
            shimmer.isHidden = true
            sheen.isHidden = true
            return
        }
        comet.isHidden = false
        sheen.isHidden = false
        shimmer.isHidden = style == .branch

        switch style {
        case .capsule:
            ambient.colors = [
                color(base, isDark ? 0.08 : 0.07),
                color(base, isDark ? 0.22 : 0.16),
                color(base, isDark ? 0.36 : 0.24),
                color(base, isDark ? 0.24 : 0.16)
            ]
            ambient.locations = [0, 0.45, 0.80, 1]

            let wave: CGFloat = isDark ? 0.26 : 0.18
            shimmer.colors = [color(base, 0), color(base, wave * 0.70), color(glow, wave), color(glow, 0)]
            shimmer.locations = [0, 0.38, 0.58, 1]

            let peak: CGFloat = isDark ? 0.66 : 0.42
            comet.colors = [
                color(base, 0),
                color(base, peak * 0.24),
                color(base, peak * 0.52),
                color(glow, peak * 0.96),
                color(.white, peak * (isDark ? 0.32 : 0.18)),
                color(base, peak * 0.34),
                color(base, 0)
            ]
            comet.locations = [0, 0.22, 0.48, 0.72, 0.80, 0.88, 1]

            sheen.colors = [color(.white, isDark ? 0.15 : 0.32), color(.white, 0)]
        case .branch:
            ambient.colors = [color(base, isDark ? 0.09 : 0.07), color(base, isDark ? 0.09 : 0.07)]
            ambient.locations = nil
            let peak: CGFloat = isDark ? 0.30 : 0.20
            comet.colors = [color(base, 0), color(base, peak * 0.45), color(base, peak), color(base, 0)]
            comet.locations = [0, 0.42, 0.72, 1]
        }
    }

    private func withoutImplicitAnimations(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
