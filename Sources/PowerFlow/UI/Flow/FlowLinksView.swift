import AppKit
import SwiftUI

/// Speed and thickness of a link, so more power visibly means more flow.
enum FlowDynamics {
    static func pointsPerSecond(for watts: Double) -> Double {
        30 + log10(1 + max(0, watts)) * 42
    }

    static func lineWidth(for watts: Double) -> CGFloat {
        min(8, max(3, 2.2 + CGFloat(max(0, watts).squareRoot()) * 0.62))
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

    func makeNSView(context: Context) -> FlowLinksNSView {
        FlowLinksNSView()
    }

    func updateNSView(_ view: FlowLinksNSView, context: Context) {
        view.apply(links, isAnimating: isAnimating)
    }
}

/// Draws the links and runs the moving pulses in the render server, so the app does no work per frame.
final class FlowLinksNSView: NSView {
    private var layers: [String: FlowLinkLayer] = [:]
    private var links: [FlowLinksView.LinkStyle] = []
    private var isAnimating = false

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

    func apply(_ newLinks: [FlowLinksView.LinkStyle], isAnimating newValue: Bool) {
        guard newLinks != links || newValue != isAnimating else { return }
        links = newLinks
        isAnimating = newValue
        rebuild()
    }

    override func layout() {
        super.layout()
        rebuild()
    }

    private func rebuild() {
        guard bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let currentIDs = Set(links.map(\.id))
        for (id, stale) in layers where !currentIDs.contains(id) {
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
            linkLayer.update(link, path: path(for: link.route), isAnimating: isAnimating)
        }
        CATransaction.commit()
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

/// One connection: a soft track with bright pulses travelling along it.
private final class FlowLinkLayer: CALayer {
    private static let referenceSpeed = 60.0
    private static let pulseSpacing: CGFloat = 34
    private static let pulseLength: CGFloat = 24
    private static let frameRate = CAFrameRateRange(minimum: 24, maximum: 60, preferred: 60)
    private static let speedTolerance: Float = 0.05

    private let track = CAShapeLayer()
    private let pulses = CAReplicatorLayer()
    private let pulse = CAGradientLayer()
    private let pulseMask = CAShapeLayer()

    private var animatedPath: CGPath?
    private var animatedWidth: CGFloat = 0

    override init() {
        super.init()
        track.fillColor = nil
        track.lineCap = .round
        addSublayer(track)

        pulse.startPoint = CGPoint(x: 0, y: 0.5)
        pulse.endPoint = CGPoint(x: 1, y: 0.5)
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

    func update(_ link: FlowLinksView.LinkStyle, path: CGPath, isAnimating: Bool) {
        let width = link.isActive ? FlowDynamics.lineWidth(for: link.watts) : 2
        track.frame = bounds
        track.path = path
        track.lineWidth = width
        track.lineDashPattern = link.isActive ? nil : [1, 5]
        // Without motion the line itself has to show that power is flowing.
        let trackAlpha: CGFloat = link.isActive ? (isAnimating ? 0.26 : 0.7) : 0.4
        track.strokeColor = link.tint.withAlphaComponent(trackAlpha).cgColor

        pulses.frame = bounds
        pulseMask.frame = bounds
        pulseMask.path = path
        pulseMask.lineWidth = width
        pulse.colors = [
            link.tint.withAlphaComponent(0).cgColor,
            link.tint.withAlphaComponent(0.85).cgColor,
            (link.tint.blended(withFraction: 0.45, of: .white) ?? link.tint).cgColor
        ]
        pulse.locations = [0, 0.7, 1]

        guard link.isActive, isAnimating else {
            pulse.removeAllAnimations()
            pulses.isHidden = true
            animatedPath = nil
            return
        }
        pulses.isHidden = false
        setSpeed(FlowDynamics.pointsPerSecond(for: link.watts) / Self.referenceSpeed)
        if animatedPath != path || abs(animatedWidth - width) > 0.4 || pulse.animation(forKey: "flow") == nil {
            animate(along: path, width: width)
        }
    }

    private func animate(along path: CGPath, width: CGFloat) {
        animatedPath = path
        animatedWidth = width
        let length = path.approximateLength
        let count = max(2, Int((length / Self.pulseSpacing).rounded()))
        let duration = Double(length) / Self.referenceSpeed

        // Short links keep a visible gap between pulses.
        let pulseLength = min(Self.pulseLength, length / CGFloat(count) * 0.72)
        pulse.bounds = CGRect(x: 0, y: 0, width: pulseLength, height: width)
        pulse.cornerRadius = width / 2
        pulses.instanceCount = count
        pulses.instanceDelay = duration / Double(count)

        let travel = CAKeyframeAnimation(keyPath: "position")
        travel.path = path
        travel.calculationMode = .paced
        travel.rotationMode = .rotateAuto
        travel.duration = duration
        travel.repeatCount = .infinity
        travel.isRemovedOnCompletion = false
        travel.preferredFrameRateRange = Self.frameRate
        pulse.removeAnimation(forKey: "flow")
        pulse.add(travel, forKey: "flow")
    }

    /// Changes the clock rate without moving the pulses.
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
