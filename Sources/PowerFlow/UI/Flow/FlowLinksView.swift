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
    let hub: CGRect?
    let hubTint: NSColor?
    let hubWatts: Double

    func makeNSView(context: Context) -> FlowLinksNSView {
        FlowLinksNSView()
    }

    func updateNSView(_ view: FlowLinksNSView, context: Context) {
        view.apply(
            links,
            isAnimating: isAnimating,
            reduceMotion: reduceMotion,
            isDark: isDark,
            differentiateWithoutColor: differentiateWithoutColor,
            hub: hub,
            hubTint: hubTint,
            hubWatts: hubWatts
        )
    }
}

/// Draws the links and runs the moving comets in the WindowServer render server, so the app does zero work per frame.
@MainActor
final class FlowLinksNSView: NSView {
    private static let pingBaseDuration: CFTimeInterval = 2.4
    private static let highFrameRate = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)

    private var layers: [String: FlowLinkLayer] = [:]
    private var fadingLayers: [FlowLinkLayer] = []
    private var links: [FlowLinksView.LinkStyle] = []
    private var isAnimating = false
    private var reduceMotion = false
    private var isDark = false
    private var differentiateWithoutColor = false
    private var hub: CGRect?
    private var hubTint: NSColor?
    private var hubWatts: Double = 0

    private var pingReplicator: CAReplicatorLayer?
    private var pingShape: CAShapeLayer?
    private var pingActive = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    /// Top-left origin matching SwiftUI, so routes and hub rects need no flip.
    override var isFlipped: Bool { true }

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
        differentiateWithoutColor newDifferentiate: Bool,
        hub newHub: CGRect?,
        hubTint newHubTint: NSColor?,
        hubWatts newHubWatts: Double
    ) {
        guard
            newLinks != links
                || newAnimating != isAnimating
                || newReduceMotion != reduceMotion
                || newIsDark != isDark
                || newDifferentiate != differentiateWithoutColor
                || newHub != hub
                || newHubTint != hubTint
                || newHubWatts != hubWatts
        else { return }
        links = newLinks
        isAnimating = newAnimating
        reduceMotion = newReduceMotion
        isDark = newIsDark
        differentiateWithoutColor = newDifferentiate
        hub = newHub
        hubTint = newHubTint
        hubWatts = newHubWatts
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
        for fading in fadingLayers {
            fading.stopAllAnimations()
            fading.removeAllAnimations()
            fading.removeFromSuperlayer()
        }
        fadingLayers.removeAll()
        CATransaction.commit()
        pingReplicator?.removeFromSuperlayer()
        pingReplicator = nil
        pingShape = nil
        pingActive = false
    }

    private func rebuild() {
        guard bounds.height > 0 else { return }
        let allowMotion = isAnimating && !reduceMotion && window != nil
        let allowEntrance = window != nil && !reduceMotion

        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let currentIDs = Set(links.map(\.id))
            for (id, stale) in layers where !currentIDs.contains(id) {
                layers[id] = nil
                if allowEntrance {
                    // Fade the removed conduit out, then drop it once the fade lands.
                    stale.beginFadeOut()
                    fadingLayers.append(stale)
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    let fadeOut = CABasicAnimation(keyPath: "opacity")
                    fadeOut.fromValue = stale.presentation()?.opacity ?? stale.opacity
                    fadeOut.toValue = 0
                    fadeOut.duration = 0.2
                    stale.opacity = 0
                    stale.add(fadeOut, forKey: "fadeOut")
                    CATransaction.setCompletionBlock { [weak self, weak stale] in
                        MainActor.assumeIsolated {
                            guard let stale else { return }
                            stale.removeFromSuperlayer()
                            self?.fadingLayers.removeAll { $0 === stale }
                        }
                    }
                    CATransaction.commit()
                } else {
                    stale.stopAllAnimations()
                    stale.removeFromSuperlayer()
                }
            }
            for (index, link) in links.enumerated() {
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
                    differentiateWithoutColor: differentiateWithoutColor,
                    allowEntrance: allowEntrance,
                    entranceDelay: 0.12 + Double(index) * 0.07
                )
            }
            CATransaction.commit()
        }

        syncPing(allowMotion: allowMotion)
    }

    // MARK: - Hub Ping

    /// A soft ring that ripples out of the Mac hub. Built once with a fixed base
    /// period; the pace, tint and position update in place so it never restarts.
    private func syncPing(allowMotion: Bool) {
        let active = allowMotion && hub != nil && hubTint != nil && hubWatts >= 0.05
        guard active, let hub, let hubTint else {
            pingReplicator?.removeFromSuperlayer()
            pingReplicator = nil
            pingShape = nil
            pingActive = false
            return
        }

        let duration = 2.8 - min(1.2, log10(1 + max(0, hubWatts)) * 0.6)
        let resolvedTint = hubTint.usingColorSpace(.sRGB) ?? hubTint

        if pingActive, let shape = pingShape, shape.bounds.size == hub.size {
            if let replicator = pingReplicator, replicator.frame != bounds {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                replicator.frame = bounds
                CATransaction.commit()
            }
            let targetSpeed = Float(Self.pingBaseDuration / duration)
            if let replicator = pingReplicator, abs(replicator.speed - targetSpeed) / targetSpeed > 0.08 {
                retime(replicator, to: targetSpeed)
            }
            if shape.strokeColor != resolvedTint.cgColor {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.5)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
                shape.strokeColor = resolvedTint.cgColor
                CATransaction.commit()
            }
            let target = CGPoint(x: hub.midX, y: hub.midY)
            if !CGPointEqualToPoint(shape.position, target) {
                let spring = CASpringAnimation(keyPath: "position")
                spring.mass = 1
                spring.stiffness = 224
                spring.damping = 25.7
                spring.duration = spring.settlingDuration
                spring.fromValue = shape.presentation()?.position ?? shape.position
                spring.toValue = target
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                shape.position = target
                CATransaction.commit()
                shape.add(spring, forKey: "move")
            }
            return
        }

        pingReplicator?.removeFromSuperlayer()

        let shape = CAShapeLayer()
        shape.bounds = CGRect(origin: .zero, size: hub.size)
        shape.position = CGPoint(x: hub.midX, y: hub.midY)
        shape.path = CGPath(ellipseIn: shape.bounds, transform: nil)
        shape.fillColor = nil
        shape.strokeColor = resolvedTint.cgColor
        shape.lineWidth = 1.5

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.4

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.45
        fade.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = Self.pingBaseDuration
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.preferredFrameRateRange = Self.highFrameRate
        shape.add(group, forKey: "ping")

        let replicator = CAReplicatorLayer()
        replicator.frame = bounds
        replicator.instanceCount = 2
        replicator.instanceDelay = Self.pingBaseDuration / 2
        replicator.speed = Float(Self.pingBaseDuration / duration)
        replicator.addSublayer(shape)
        layer?.addSublayer(replicator)

        pingReplicator = replicator
        pingShape = shape
        pingActive = true
    }

    /// Changes the clock rate without resetting the ripple phase.
    private func retime(_ layer: CALayer, to speed: Float) {
        let now = CACurrentMediaTime()
        let local = layer.convertTime(now, from: nil)
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.speed = speed
        layer.timeOffset = local - layer.convertTime(now, from: nil)
    }

    private func path(for route: FlowLayout.Route) -> CGPath {
        let path = CGMutablePath()
        path.move(to: route.start)
        path.addCurve(
            to: route.end,
            control1: route.control1,
            control2: route.control2
        )
        return path
    }
}

/// One precision conduit: wattage-scaled soft halo, vibrant calibrated track, and a tangentially
/// rotated glowing comet running entirely in WindowServer CoreAnimation.
private final class FlowLinkLayer: CALayer {
    private static let referenceSpeed = 60.0
    private static let pulseSpacing: CGFloat = 34
    private static let pulseLength: CGFloat = 28
    private static let frameRate = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
    private static let transitionDuration: CFTimeInterval = 0.45
    @MainActor private static let transitionTiming = CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1)
    @MainActor private static let entranceTiming = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)

    private let haloLayer = CAShapeLayer()
    private let trackLayer = CAShapeLayer()
    private let pulses = CAReplicatorLayer()
    private let pulse = CAGradientLayer()
    private let pulseMask = CAShapeLayer()

    private var hasConfigured = false
    private var didDrawOn = false
    private var animatedRoute: FlowLayout.Route?
    private var appliedRoute: FlowLayout.Route?

    override init() {
        super.init()

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
        pulses.isHidden = true
        animatedRoute = nil
        appliedRoute = nil
        didDrawOn = false
    }

    /// Freezes the comets where they are so the whole conduit can fade out intact.
    @MainActor
    func beginFadeOut() {
        pulse.opacity = pulse.presentation()?.opacity ?? pulse.opacity
        pulse.removeAllAnimations()
    }

    @MainActor
    func update(
        _ link: FlowLinksView.LinkStyle,
        path: CGPath,
        allowMotion: Bool,
        isDark: Bool,
        differentiateWithoutColor: Bool,
        allowEntrance: Bool,
        entranceDelay: CFTimeInterval
    ) {
        let baseTint = link.tint.usingColorSpace(.sRGB) ?? link.tint
        let resolvedTint = Self.calibratedConduitColor(from: baseTint, isActive: link.isActive, isDark: isDark)
        let width: CGFloat = link.isActive ? FlowDynamics.lineWidth(for: link.watts) : 2.0
        let shouldAnimateFlow = link.isActive && allowMotion
        let shouldAnimateTransitions = hasConfigured && allowMotion

        let haloWidth = width * 3
        let wattsFactor = min(1.0, max(0.0, log10(1 + max(0, link.watts)) / 2.0))
        let haloOpacity: Float = if !link.isActive {
            0.0
        } else if isDark {
            Float(0.08 + 0.10 * wattsFactor)
        } else {
            Float(0.06 + 0.08 * wattsFactor)
        }

        let trackColor = resolvedTint.cgColor
        let trackOpacity: Float = if link.isActive {
            shouldAnimateFlow ? 0.22 : 0.7
        } else if differentiateWithoutColor {
            isDark ? 0.56 : 0.60
        } else {
            isDark ? 0.38 : 0.42
        }
        let dashPattern: [NSNumber]? = link.isActive ? nil : (differentiateWithoutColor ? [4, 4] : [2, 5])

        // Structure moves spring the conduit path from wherever the previous
        // route currently renders, matching the SwiftUI node spring.
        let routeChanged = appliedRoute != nil && appliedRoute != link.route
        let previousPath = routeChanged ? (trackLayer.presentation()?.path ?? trackLayer.path) : nil
        appliedRoute = link.route

        let previousTrackWidth = trackLayer.presentation()?.lineWidth ?? trackLayer.lineWidth
        let previousTrackColor = trackLayer.presentation()?.strokeColor ?? trackLayer.strokeColor
        let previousTrackOpacity = trackLayer.presentation()?.opacity ?? trackLayer.opacity
        let previousHaloWidth = haloLayer.presentation()?.lineWidth ?? haloLayer.lineWidth
        let previousHaloColor = haloLayer.presentation()?.strokeColor ?? haloLayer.strokeColor
        let previousHaloOpacity = haloLayer.presentation()?.opacity ?? haloLayer.opacity

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
        }
        hasConfigured = true

        if allowEntrance && !didDrawOn {
            didDrawOn = true
            for target in [trackLayer, haloLayer] {
                let drawOn = CABasicAnimation(keyPath: "strokeEnd")
                drawOn.fromValue = 0
                drawOn.toValue = 1
                drawOn.duration = 0.6
                drawOn.timingFunction = Self.entranceTiming
                drawOn.beginTime = CACurrentMediaTime() + entranceDelay
                drawOn.fillMode = .backwards
                target.add(drawOn, forKey: "drawOn")
            }
        }

        pulses.frame = bounds
        pulseMask.frame = bounds
        pulseMask.path = path
        pulseMask.lineWidth = width + 0.5

        if routeChanged, allowEntrance, let previousPath {
            for target in [trackLayer, haloLayer, pulseMask] {
                let spring = CASpringAnimation(keyPath: "path")
                spring.mass = 1
                spring.stiffness = 224
                spring.damping = 25.7
                spring.duration = spring.settlingDuration
                spring.fromValue = previousPath
                spring.toValue = path
                target.add(spring, forKey: "pathSpring")
            }
        }

        let coreColor = resolvedTint.blended(withFraction: isDark ? 0.25 : 0.15, of: .white) ?? resolvedTint
        let headColor = resolvedTint.blended(withFraction: isDark ? 0.72 : 0.58, of: .white) ?? resolvedTint
        pulse.colors = [
            resolvedTint.withAlphaComponent(0.0).cgColor,
            resolvedTint.withAlphaComponent(0.42).cgColor,
            coreColor.cgColor,
            headColor.cgColor,
            headColor.withAlphaComponent(0.95).cgColor
        ]
        pulse.locations = [0.0, 0.35, 0.72, 0.92, 1.0]

        guard shouldAnimateFlow else {
            pulse.removeAllAnimations()
            pulses.isHidden = true
            animatedRoute = nil
            return
        }

        pulses.isHidden = false
        setSpeed(FlowDynamics.pointsPerSecond(for: link.watts) / Self.referenceSpeed)
        // Width-only changes reshape the comet in place; the travel animation is
        // re-added only when the route actually changed (or isn't running).
        updatePulseGeometry(width: width)
        if animatedRoute != link.route || pulse.animation(forKey: "flow") == nil {
            if routeChanged {
                // Comets hop to the new path while dipped out of view.
                let dip = CAKeyframeAnimation(keyPath: "opacity")
                dip.values = [1.0, 0.0, 0.0, 1.0]
                dip.keyTimes = [0.0, 0.15, 0.85, 1.0]
                dip.duration = 0.6
                pulses.add(dip, forKey: "routeDip")
            }
            animate(along: path, route: link.route, width: width)
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

    /// Reshapes the comet for a new conduit width without touching its travel.
    private func updatePulseGeometry(width: CGFloat) {
        let cometHeight = max(2.5, width * 0.96)
        var cometBounds = pulse.bounds
        cometBounds.size.height = cometHeight
        pulse.bounds = cometBounds
        pulse.cornerRadius = cometHeight / 2
    }

    private func animate(along path: CGPath, route: FlowLayout.Route, width: CGFloat) {
        animatedRoute = route

        let length = max(1, path.approximateLength)
        let count = max(2, Int((length / Self.pulseSpacing).rounded()))
        let duration = Double(length) / Self.referenceSpeed

        // Short links keep a visible gap between comets.
        let pulseLength = min(Self.pulseLength, length / CGFloat(count) * 0.74)
        let cometHeight = max(2.5, width * 0.96)
        let cometBounds = CGRect(x: 0, y: 0, width: pulseLength, height: cometHeight)
        pulse.bounds = cometBounds
        pulse.cornerRadius = cometHeight / 2
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

    /// Changes the clock rate without moving the comets.
    private func setSpeed(_ speed: Double) {
        let target = Float(speed)
        guard abs(pulses.speed - target) / target > 0.06 else { return }
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
