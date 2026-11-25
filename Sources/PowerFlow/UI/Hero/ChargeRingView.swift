import AppKit
import QuartzCore
import SwiftUI

/// Circular charge gauge drawn entirely in Core Animation so value sweeps and the
/// travelling comet cost zero per-frame work in the app.
struct ChargeRingView: NSViewRepresentable {
    enum Direction: Equatable {
        case charging
        case discharging
        case idle
    }

    var fraction: Double
    var limitFraction: Double?
    var tint: NSColor
    var isDark: Bool
    var increasedContrast: Bool
    var direction: Direction
    var isAnimating: Bool
    var reduceMotion: Bool

    func makeNSView(context: Context) -> ChargeRingNSView {
        ChargeRingNSView()
    }

    func updateNSView(_ view: ChargeRingNSView, context: Context) {
        view.apply(
            fraction: fraction,
            limitFraction: limitFraction,
            tint: tint,
            isDark: isDark,
            increasedContrast: increasedContrast,
            direction: direction,
            isAnimating: isAnimating,
            reduceMotion: reduceMotion
        )
    }
}

@MainActor
final class ChargeRingNSView: NSView {
    private static let lineWidth: CGFloat = 9
    private static let cometLength = 0.1

    private let trackLayer = CAShapeLayer()
    private let glowLayer = CAShapeLayer()
    private let progressGradient = CAGradientLayer()
    private let progressMask = CAShapeLayer()
    private let limitTickLayer = CAShapeLayer()
    private let cometLayer = CAShapeLayer()

    private var hasApplied = false
    private var fraction: Double = 0
    private var limitFraction: Double?
    private var tint: NSColor?
    private var isDark = false
    private var increasedContrast = false
    private var direction = ChargeRingView.Direction.idle
    private var isAnimating = false
    private var reduceMotion = false
    private var entrancePending = false
    private var cometFraction: Double = 0
    private var cometSignature = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        trackLayer.fillColor = nil
        trackLayer.lineCap = .round
        layer?.addSublayer(trackLayer)

        glowLayer.fillColor = nil
        glowLayer.lineCap = .round
        glowLayer.shadowOpacity = 0
        layer?.addSublayer(glowLayer)

        progressGradient.type = .conic
        progressGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        progressGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        progressMask.fillColor = nil
        progressMask.strokeColor = NSColor.black.cgColor
        progressMask.lineCap = .round
        progressGradient.mask = progressMask
        layer?.addSublayer(progressGradient)

        limitTickLayer.fillColor = nil
        limitTickLayer.lineCap = .round
        limitTickLayer.lineWidth = 2
        layer?.addSublayer(limitTickLayer)

        cometLayer.fillColor = nil
        cometLayer.lineCap = .round
        cometLayer.opacity = 0
        layer?.addSublayer(cometLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stripAllAnimations()
        } else {
            entrancePending = true
            rebuild()
        }
    }

    override func layout() {
        super.layout()
        rebuild()
    }

    private func stripAllAnimations() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressMask.removeAllAnimations()
        glowLayer.removeAllAnimations()
        cometLayer.removeAllAnimations()
        cometSignature = -1
        CATransaction.commit()
    }

    // MARK: - Configuration

    func apply(
        fraction newFraction: Double,
        limitFraction newLimit: Double?,
        tint newTint: NSColor,
        isDark newIsDark: Bool,
        increasedContrast newContrast: Bool,
        direction newDirection: ChargeRingView.Direction,
        isAnimating newAnimating: Bool,
        reduceMotion newReduceMotion: Bool
    ) {
        let clampedFraction = min(1.0, max(0.0, newFraction))
        guard
            !hasApplied
                || clampedFraction != fraction
                || newLimit != limitFraction
                || newTint != tint
                || newIsDark != isDark
                || newContrast != increasedContrast
                || newDirection != direction
                || newAnimating != isAnimating
                || newReduceMotion != reduceMotion
        else { return }

        let previousFraction = fraction
        let fractionChanged = hasApplied && clampedFraction != fraction
        hasApplied = true
        fraction = clampedFraction
        limitFraction = newLimit
        tint = newTint
        isDark = newIsDark
        increasedContrast = newContrast
        direction = newDirection
        isAnimating = newAnimating
        reduceMotion = newReduceMotion
        rebuild(fractionChangedFrom: fractionChanged ? previousFraction : nil)
    }

    private func rebuild(fractionChangedFrom previous: Double? = nil) {
        guard bounds.width > 0, bounds.height > 0, let tint else { return }

        let resolvedTint = tint.usingColorSpace(.sRGB) ?? tint
        let lw = Self.lineWidth
        let side = min(bounds.width, bounds.height)
        let radius = side / 2 - lw / 2 - 4
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)

            let trackColor = trackStrokeColor()
            trackLayer.frame = bounds
            trackLayer.path = CGPath(ellipseIn: ringRect(center: center, radius: radius), transform: nil)
            trackLayer.lineWidth = lw
            trackLayer.strokeColor = trackColor

            let arcPath = arcPath(center: center, radius: radius)
            glowLayer.frame = bounds
            glowLayer.path = arcPath
            glowLayer.lineWidth = lw * 2.15
            glowLayer.strokeColor = resolvedTint.withAlphaComponent(isDark ? 0.22 : 0.13).cgColor
            glowLayer.strokeEnd = fraction
            glowLayer.shadowOpacity = 0

            progressGradient.frame = bounds
            configureProgressGradient(from: resolvedTint)
            progressMask.frame = bounds
            progressMask.path = arcPath
            progressMask.lineWidth = lw
            progressMask.strokeEnd = fraction

            configureLimitTick(center: center, radius: radius)

            cometLayer.frame = bounds
            cometLayer.path = arcPath
            cometLayer.lineWidth = lw * 0.55
            cometLayer.strokeColor = (resolvedTint.blended(withFraction: 0.65, of: .white) ?? resolvedTint).cgColor

            CATransaction.commit()

            configureStrokeAnimation(previous: previous)
            configureComet()
        }
    }

    private func ringRect(center: CGPoint, radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// Arc starting at 12 o'clock travelling clockwise in this view's y-up layer space.
    private func arcPath(center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi / 2 - .pi * 2,
            clockwise: true
        )
        return path
    }

    private func trackStrokeColor() -> CGColor {
        NSColor(PowerFlowTheme.gaugeTrack(for: isDark ? .dark : .light, contrast: increasedContrast ? .increased : .standard)).cgColor
    }

    /// In non-flipped Core Animation space, a conic gradient from (0.5, 0.5) to (0.5, 1.0)
    /// sweeps counter-clockwise from 12 o'clock (loc 1.0 = clockwise start, loc 1.0 - fraction = leading tip).
    /// Near 100%, smoothly blend across loc 0.0 back into `startColor` to eliminate any 12-o'clock seam.
    private func configureProgressGradient(from tint: NSColor) {
        let startColor = gradientStartColor(from: tint)
        let endColor = gradientEndColor(from: tint)

        if fraction >= 0.96 {
            let seamBlend = min(1.0, max(0.0, (fraction - 0.96) / 0.04))
            let seamColor = endColor.blended(withFraction: seamBlend, of: startColor) ?? startColor
            let peakLocation = 0.04 + 0.04 * seamBlend
            progressGradient.colors = [seamColor.cgColor, endColor.cgColor, startColor.cgColor]
            progressGradient.locations = [0.0, NSNumber(value: peakLocation), 1.0]
        } else {
            let tipLocation = min(0.96, max(0.04, 1.0 - fraction))
            progressGradient.colors = [endColor.cgColor, endColor.cgColor, startColor.cgColor]
            progressGradient.locations = [0.0, NSNumber(value: tipLocation), 1.0]
        }
    }

    private func gradientStartColor(from tint: NSColor) -> NSColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        tint.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let shifted = NSColor(
            calibratedHue: (hue - 0.035 + 1).truncatingRemainder(dividingBy: 1),
            saturation: saturation,
            brightness: brightness * 0.85,
            alpha: alpha
        )
        return shifted.usingColorSpace(.sRGB) ?? shifted
    }

    private func gradientEndColor(from tint: NSColor) -> NSColor {
        let brightened = tint.blended(withFraction: 0.12, of: .white) ?? tint
        return brightened.usingColorSpace(.sRGB) ?? brightened
    }

    private func configureLimitTick(center: CGPoint, radius: CGFloat) {
        guard let limitFraction, limitFraction > 0.02, limitFraction < 0.999 else {
            limitTickLayer.strokeColor = nil
            limitTickLayer.path = nil
            return
        }
        let lw = Self.lineWidth
        let angle = CGFloat.pi / 2 - limitFraction * .pi * 2
        let inner = radius - (lw + 4) / 2
        let outer = radius + (lw + 4) / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
        path.addLine(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
        limitTickLayer.path = path
        limitTickLayer.strokeColor = tickColor()
    }

    private func tickColor() -> CGColor {
        NSColor(PowerFlowTheme.primaryValue(for: isDark ? .dark : .light, contrast: increasedContrast ? .increased : .standard)).cgColor
    }

    // MARK: - Animations

    /// Rebuilds from layout() and non-fraction apply() calls must not disturb a
    /// sweep already in flight — only re-target when the entrance is pending or
    /// the fraction actually changed.
    private func configureStrokeAnimation(previous: Double?) {
        guard entrancePending || previous != nil else { return }

        let isEntrance = entrancePending
        entrancePending = false
        progressMask.removeAnimation(forKey: "sweep")
        glowLayer.removeAnimation(forKey: "sweep")

        guard !reduceMotion else { return }

        let presented = progressMask.presentation()?.strokeEnd
        let from: CGFloat = isEntrance ? 0 : (presented ?? previous.map { CGFloat($0) } ?? fraction)

        guard abs(from - fraction) > 0.001 else { return }

        for target in [progressMask, glowLayer] {
            let spring = CASpringAnimation(keyPath: "strokeEnd")
            spring.mass = 1
            spring.stiffness = 120
            spring.damping = 17
            spring.duration = spring.settlingDuration
            spring.fromValue = from
            spring.toValue = fraction
            target.add(spring, forKey: "sweep")
        }
    }

    private func configureComet() {
        let active = isAnimating && !reduceMotion && direction != .idle && fraction > 0.05
        let signature = active ? (direction == .discharging ? 3 : 1) : 0
        guard
            signature != cometSignature
                || abs(fraction - cometFraction) > 0.005
        else { return }
        cometSignature = signature
        cometFraction = fraction

        cometLayer.removeAllAnimations()
        cometLayer.opacity = 0
        guard active else { return }

        cometLayer.strokeStart = 0
        cometLayer.strokeEnd = fraction

        let f = fraction
        let cometTravel = CAKeyframeAnimation(keyPath: "strokeEnd")
        let cometTail = CAKeyframeAnimation(keyPath: "strokeStart")
        if direction == .charging {
            cometTravel.values = [0, f]
            cometTravel.keyTimes = [0, 1]
            if f > Self.cometLength {
                cometTail.values = [0, 0, f - Self.cometLength]
                cometTail.keyTimes = [0, NSNumber(value: Self.cometLength / f), 1]
            } else {
                cometTail.values = [0, 0]
                cometTail.keyTimes = [0, 1]
            }
        } else {
            cometTravel.values = [f, 0]
            cometTravel.keyTimes = [0, 1]
            if f > Self.cometLength {
                cometTail.values = [f - Self.cometLength, 0, 0]
                cometTail.keyTimes = [0, NSNumber(value: max(0.01, 1 - Self.cometLength / f)), 1]
            } else {
                cometTail.values = [0, 0]
                cometTail.keyTimes = [0, 1]
            }
        }

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.12, 0.85, 1]

        for animation in [cometTravel, cometTail, fade] {
            animation.duration = 1.6
        }

        let group = CAAnimationGroup()
        group.animations = [cometTravel, cometTail, fade]
        group.duration = 2.4
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        group.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        cometLayer.add(group, forKey: "comet")
    }
}
