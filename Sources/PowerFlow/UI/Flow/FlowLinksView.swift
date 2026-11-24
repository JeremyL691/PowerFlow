import AppKit
import QuartzCore
import SwiftUI

/// Speed and thickness of a link, so more power visibly means more flow.
enum FlowDynamics {
    static func pointsPerSecond(for watts: Double) -> Double {
        30 + log10(1 + max(0, watts)) * 42
    }

    static func lineWidth(for watts: Double) -> CGFloat {
        min(7.6, max(2.6, 2.1 + CGFloat(max(0, watts).squareRoot()) * 0.56))
    }
}

struct FlowLinksView: NSViewRepresentable {
    struct LinkStyle: Equatable {
        let id: String
        let route: FlowLayout.Route
        let tint: NSColor
        let watts: Double
        let isActive: Bool
    }

    let links: [LinkStyle]
    let isAnimating: Bool
    let reduceMotion: Bool
    let isDark: Bool
    let differentiateWithoutColor: Bool

    func makeNSView(context: Context) -> FlowLinksNSView {
        FlowLinksNSView()
    }

    func updateNSView(_ view: FlowLinksNSView, context: Context) {
        view.apply(
            links,
            isAnimating: isAnimating,
            reduceMotion: reduceMotion,
            isDark: isDark,
            differentiateWithoutColor: differentiateWithoutColor
        )
    }
}

/// Draws the links and runs the moving droplets in the WindowServer render server, so the app does zero work per frame.
@MainActor
final class FlowLinksNSView: NSView {
    private var layers: [String: FlowLinkLayer] = [:]
    private var links: [FlowLinksView.LinkStyle] = []
    private var isAnimating = false
    private var reduceMotion = false
    private var isDark = false
    private var differentiateWithoutColor = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
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
            rebuild()
        }
    }

    func apply(
        _ newLinks: [FlowLinksView.LinkStyle],
        isAnimating newAnimating: Bool,
        reduceMotion newReduceMotion: Bool,
        isDark newIsDark: Bool,
        differentiateWithoutColor newDifferentiate: Bool
    ) {
        guard
            newLinks != links
                || newAnimating != isAnimating
                || newReduceMotion != reduceMotion
                || newIsDark != isDark
                || newDifferentiate != differentiateWithoutColor
        else { return }
        links = newLinks
        isAnimating = newAnimating
        reduceMotion = newReduceMotion
        isDark = newIsDark
        differentiateWithoutColor = newDifferentiate
        rebuild()
    }

    override func layout() {
        super.layout()
        rebuild()
    }

    private func stripAllAnimations() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for linkLayer in layers.values {
            linkLayer.stopAllAnimations()
        }
        CATransaction.commit()
    }

    private func rebuild() {
        guard bounds.height > 0 else { return }
        let allowMotion = isAnimating && !reduceMotion && window != nil

        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let currentIDs = Set(links.map(\.id))
            for (id, stale) in layers where !currentIDs.contains(id) {
                stale.stopAllAnimations()
                stale.removeFromSuperlayer()
                layers[id] = nil
            }
            for link in links {
                let linkLayer = layers[link.id] ?? {
                    let created = FlowLinkLayer()
                    layer?.addSublayer(created)
                    layers[link.id] = created
                    return created
                }()
                linkLayer.frame = bounds
                linkLayer.update(
                    link,
                    path: path(for: link.route),
                    allowMotion: allowMotion,
                    isDark: isDark,
                    differentiateWithoutColor: differentiateWithoutColor
                )
            }
            CATransaction.commit()
        }
    }

    /// Routes use a top-left origin; layers of this view use a bottom-left one.
    private func path(for route: FlowLayout.Route) -> CGPath {
        func flipped(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: bounds.height - point.y)
        }
        let path = CGMutablePath()
        path.move(to: flipped(route.start))
        path.addCurve(
            to: flipped(route.end),
            control1: flipped(route.control1),
            control2: flipped(route.control2)
        )
        return path
    }
}

/// One precision conduit: recessed groove, wattage-scaled soft halo, vibrant calibrated track,
/// and tangentially rotated tapered energy droplets running entirely in WindowServer CoreAnimation.
private final class FlowLinkLayer: CALayer {
    private static let referenceSpeed = 60.0
    private static let pulseSpacing: CGFloat = 34
    private static let pulseLength: CGFloat = 24
    private static let frameRate = CAFrameRateRange(minimum: 24, maximum: 60, preferred: 60)
    private static let speedTolerance: Float = 0.05
    private static let transitionDuration: CFTimeInterval = 0.26
    @MainActor private static let transitionTiming = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)

    private let grooveLayer = CAShapeLayer()
    private let haloLayer = CAShapeLayer()
    private let trackLayer = CAShapeLayer()
    private let pulses = CAReplicatorLayer()
    private let pulse = CAGradientLayer()
    private let pulseMask = CAShapeLayer()

    private var hasConfigured = false
    private var animatedRoute: FlowLayout.Route?
    private var animatedHeight: CGFloat = 0
    private var animatedWidth: CGFloat = 0

    override init() {
        super.init()

        grooveLayer.fillColor = nil
        grooveLayer.lineCap = .round
        addSublayer(grooveLayer)

        haloLayer.fillColor = nil
        haloLayer.lineCap = .round
        addSublayer(haloLayer)

        trackLayer.fillColor = nil
        trackLayer.lineCap = .round
        addSublayer(trackLayer)

        pulse.startPoint = CGPoint(x: 0, y: 0.5)
        pulse.endPoint = CGPoint(x: 1, y: 0.5)
        pulse.opacity = 0
        pulses.addSublayer(pulse)

        pulseMask.fillColor = nil
        pulseMask.strokeColor = NSColor.black.cgColor
        pulseMask.lineCap = .butt
        pulses.mask = pulseMask
        addSublayer(pulses)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @MainActor
    func stopAllAnimations() {
        pulse.removeAllAnimations()
        trackLayer.removeAllAnimations()
        haloLayer.removeAllAnimations()
        grooveLayer.removeAllAnimations()
        pulses.isHidden = true
        animatedRoute = nil
    }

    @MainActor
    func update(
        _ link: FlowLinksView.LinkStyle,
        path: CGPath,
        allowMotion: Bool,
        isDark: Bool,
        differentiateWithoutColor: Bool
    ) {
        let baseTint = link.tint.usingColorSpace(.sRGB) ?? link.tint
        let resolvedTint = Self.calibratedConduitColor(from: baseTint, isActive: link.isActive, isDark: isDark)
        let width: CGFloat = link.isActive ? FlowDynamics.lineWidth(for: link.watts) : 2.0
        let shouldAnimateFlow = link.isActive && allowMotion
        let shouldAnimateTransitions = hasConfigured && allowMotion

        let grooveWidth = width + 2.4
        let grooveColor = isDark
            ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.34).cgColor
            : NSColor(srgbRed: 0.06, green: 0.08, blue: 0.14, alpha: 0.065).cgColor
        let grooveOpacity: Float = link.isActive ? 1.0 : 0.45

        let haloWidth = width * 2.1
        let wattsFactor = min(1.0, max(0.0, log10(1 + max(0, link.watts)) / 2.0))
        let haloOpacity: Float = if !link.isActive {
            0.0
        } else if isDark {
            Float(0.07 + 0.08 * wattsFactor)
        } else {
            Float(0.06 + 0.07 * wattsFactor)
        }

        let trackColor = resolvedTint.cgColor
        let trackOpacity: Float = if link.isActive {
            shouldAnimateFlow ? (isDark ? 0.34 : 0.38) : 0.78
        } else if differentiateWithoutColor {
            isDark ? 0.56 : 0.60
        } else {
            isDark ? 0.38 : 0.42
        }
        let dashPattern: [NSNumber]? = link.isActive ? nil : (differentiateWithoutColor ? [4, 4] : [2, 5])

        let previousTrackWidth = trackLayer.presentation()?.lineWidth ?? trackLayer.lineWidth
        let previousTrackColor = trackLayer.presentation()?.strokeColor ?? trackLayer.strokeColor
        let previousTrackOpacity = trackLayer.presentation()?.opacity ?? trackLayer.opacity
        let previousHaloWidth = haloLayer.presentation()?.lineWidth ?? haloLayer.lineWidth
        let previousHaloColor = haloLayer.presentation()?.strokeColor ?? haloLayer.strokeColor
        let previousHaloOpacity = haloLayer.presentation()?.opacity ?? haloLayer.opacity
        let previousGrooveWidth = grooveLayer.presentation()?.lineWidth ?? grooveLayer.lineWidth

        grooveLayer.frame = bounds
        grooveLayer.path = path
        grooveLayer.lineWidth = grooveWidth
        grooveLayer.strokeColor = grooveColor
        grooveLayer.opacity = grooveOpacity

        haloLayer.frame = bounds
        haloLayer.path = path
        haloLayer.lineWidth = haloWidth
        haloLayer.strokeColor = trackColor
        haloLayer.opacity = haloOpacity

        trackLayer.frame = bounds
        trackLayer.path = path
        trackLayer.lineWidth = width
        trackLayer.lineDashPattern = dashPattern
        trackLayer.strokeColor = trackColor
        trackLayer.opacity = trackOpacity

        if shouldAnimateTransitions {
            if abs(previousTrackWidth - width) > 0.05 {
                animateTransition(keyPath: "lineWidth", on: trackLayer, from: previousTrackWidth, to: width)
                animateTransition(keyPath: "lineWidth", on: haloLayer, from: previousHaloWidth, to: haloWidth)
                animateTransition(keyPath: "lineWidth", on: grooveLayer, from: previousGrooveWidth, to: grooveWidth)
            }
            if let previousTrackColor, previousTrackColor != trackColor {
                animateTransition(keyPath: "strokeColor", on: trackLayer, from: previousTrackColor, to: trackColor)
            }
            if let previousHaloColor, previousHaloColor != trackColor {
                animateTransition(keyPath: "strokeColor", on: haloLayer, from: previousHaloColor, to: trackColor)
            }
            if abs(previousTrackOpacity - trackOpacity) > 0.01 {
                animateTransition(keyPath: "opacity", on: trackLayer, from: previousTrackOpacity, to: trackOpacity)
            }
            if abs(previousHaloOpacity - haloOpacity) > 0.01 {
                animateTransition(keyPath: "opacity", on: haloLayer, from: previousHaloOpacity, to: haloOpacity)
            }
        } else {
            removeTransitionAnimations(on: trackLayer)
            removeTransitionAnimations(on: haloLayer)
            removeTransitionAnimations(on: grooveLayer)
        }
        hasConfigured = true

        pulses.frame = bounds
        pulseMask.frame = bounds
        pulseMask.path = path
        pulseMask.lineWidth = width

        let specularTip = resolvedTint.blended(withFraction: isDark ? 0.55 : 0.40, of: .white) ?? resolvedTint
        pulse.colors = [
            resolvedTint.withAlphaComponent(0.0).cgColor,
            resolvedTint.withAlphaComponent(0.45).cgColor,
            resolvedTint.withAlphaComponent(0.95).cgColor,
            specularTip.cgColor
        ]
        pulse.locations = [0.0, 0.38, 0.78, 1.0]

        guard shouldAnimateFlow else {
            pulse.removeAllAnimations()
            pulses.isHidden = true
            animatedRoute = nil
            return
        }

        pulses.isHidden = false
        setSpeed(FlowDynamics.pointsPerSecond(for: link.watts) / Self.referenceSpeed)
        let routeChanged = animatedRoute != link.route || abs(animatedHeight - bounds.height) > 0.5
        if routeChanged || abs(animatedWidth - width) > 0.4 || pulse.animation(forKey: "flow") == nil {
            animate(along: path, route: link.route, height: bounds.height, width: width)
        }
    }

    private static func calibratedConduitColor(
        from color: NSColor,
        isActive: Bool,
        isDark: Bool
    ) -> NSColor {
        guard isActive, !isDark else { return color }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // Preserve exact semantic hue while keeping light-mode energy conduits radiant rather than muddy.
        let liftedBrightness = min(0.84, max(brightness, 0.74))
        let refinedSaturation = min(1.0, max(saturation, 0.78))
        return NSColor(
            calibratedHue: hue,
            saturation: refinedSaturation,
            brightness: liftedBrightness,
            alpha: alpha
        ).usingColorSpace(.sRGB) ?? color
    }

    @MainActor
    private func animateTransition(keyPath: String, on target: CALayer, from oldValue: Any, to newValue: Any) {
        let transition = CABasicAnimation(keyPath: keyPath)
        transition.fromValue = oldValue
        transition.toValue = newValue
        transition.duration = Self.transitionDuration
        transition.timingFunction = Self.transitionTiming
        target.add(transition, forKey: "transition-\(keyPath)")
    }

    private func removeTransitionAnimations(on target: CALayer) {
        target.removeAnimation(forKey: "transition-lineWidth")
        target.removeAnimation(forKey: "transition-strokeColor")
        target.removeAnimation(forKey: "transition-opacity")
    }

    private func animate(along path: CGPath, route: FlowLayout.Route, height: CGFloat, width: CGFloat) {
        animatedRoute = route
        animatedHeight = height
        animatedWidth = width

        let length = max(1, path.approximateLength)
        let count = max(2, Int((length / Self.pulseSpacing).rounded()))
        let duration = Double(length) / Self.referenceSpeed

        // Short links keep a visible gap between droplets.
        let pulseLength = min(Self.pulseLength, length / CGFloat(count) * 0.74)
        let dropletHeight = max(2.2, width * 0.94)
        pulse.bounds = CGRect(x: 0, y: 0, width: pulseLength, height: dropletHeight)
        pulse.cornerRadius = dropletHeight / 2
        pulse.opacity = 0

        pulses.instanceCount = count
        pulses.instanceDelay = -(duration / Double(count))

        let travel = CAKeyframeAnimation(keyPath: "position")
        travel.path = path
        travel.calculationMode = .paced
        travel.rotationMode = .rotateAuto

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0.0, 0.14, 0.86, 1.0]

        let group = CAAnimationGroup()
        group.animations = [travel, fade]
        group.duration = duration
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        group.fillMode = .both
        group.preferredFrameRateRange = Self.frameRate

        pulse.removeAnimation(forKey: "flow")
        pulse.add(group, forKey: "flow")
    }

    /// Changes the clock rate without moving the droplets.
    private func setSpeed(_ speed: Double) {
        let target = Float(speed)
        guard abs(pulses.speed - target) > Self.speedTolerance else { return }
        let now = CACurrentMediaTime()
        let local = pulses.convertTime(now, from: nil)
        pulses.timeOffset = 0
        pulses.beginTime = 0
        pulses.speed = target
        pulses.timeOffset = local - pulses.convertTime(now, from: nil)
    }
}

private extension CGPath {
    var approximateLength: CGFloat {
        var length: CGFloat = 0
        var current = CGPoint.zero
        applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                current = points[0]
            case .addLineToPoint:
                length += hypot(points[0].x - current.x, points[0].y - current.y)
                current = points[0]
            case .addCurveToPoint:
                let start = current
                var previous = start
                for step in 1...16 {
                    let t = CGFloat(step) / 16
                    let u = 1 - t
                    let x = u * u * u * start.x + 3 * u * u * t * points[0].x
                        + 3 * u * t * t * points[1].x + t * t * t * points[2].x
                    let y = u * u * u * start.y + 3 * u * u * t * points[0].y
                        + 3 * u * t * t * points[1].y + t * t * t * points[2].y
                    length += hypot(x - previous.x, y - previous.y)
                    previous = CGPoint(x: x, y: y)
                }
                current = points[2]
            default:
                break
            }
        }
        return length
    }
}
