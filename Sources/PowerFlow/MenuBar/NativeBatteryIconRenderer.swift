import AppKit

enum BatteryIconState: Equatable, Hashable, Sendable {
    case neutral
    case lowPower
    case critical
    case unavailable
}

enum BatteryOverlay: Equatable, Hashable, Sendable {
    case none
    case chargingBolt
    case pluggedInPlug
}

struct BatteryIconRenderSpec: Equatable, Hashable, Sendable {
    let percent: Int
    let state: BatteryIconState
    let overlay: BatteryOverlay
    let showsPercent: Bool
    let isDarkMenuBar: Bool
    let style: BatteryIconStyle

    init(
        percent: Int,
        state: BatteryIconState,
        overlay: BatteryOverlay = .none,
        showsPercent: Bool = false,
        isDarkMenuBar: Bool,
        style: BatteryIconStyle
    ) {
        self.percent = percent
        self.state = state
        self.overlay = overlay
        self.showsPercent = showsPercent
        self.isDarkMenuBar = isDarkMenuBar
        self.style = style
    }

    /// Colored states carry their own colors; everything else is tinted by the menu bar.
    var usesTemplateRendering: Bool {
        switch state {
        case .neutral, .unavailable:
            return true
        case .lowPower, .critical:
            return false
        }
    }

    fileprivate var cacheKey: BatteryIconRenderSpec {
        BatteryIconRenderSpec(
            percent: min(max(percent, 0), 100),
            state: state,
            overlay: state == .unavailable ? .none : overlay,
            showsPercent: showsPercent && style.drawsPercentInsideIcon && state != .unavailable,
            isDarkMenuBar: usesTemplateRendering ? false : isDarkMenuBar,
            style: style
        )
    }
}

/// Reproduces Apple's menu bar battery, including the rules the system uses to pick a color and an
/// overlay.
enum NativeBatteryIconRenderer {
    static let canvasSize = BatteryIconDrawing.canvasSize

    @MainActor private static let cache = BoundedImageCache(maxEntries: 128)

    /// Low Power Mode wins over the low-battery warning. The warning is the system's own
    /// (`IOPSGetBatteryWarningLevel`), which is never raised while on external power.
    static func state(for snapshot: PowerSnapshot) -> BatteryIconState {
        guard snapshot.isDataAvailable else {
            return .unavailable
        }
        if snapshot.isLowPowerModeEnabled {
            return .lowPower
        }
        if !snapshot.isExternalConnected, snapshot.isLowBatteryWarning || snapshot.atCriticalLevel {
            return .critical
        }
        return .neutral
    }

    /// Follows the physical connection directly so the icon changes the moment power does.
    static func overlay(for snapshot: PowerSnapshot) -> BatteryOverlay {
        guard snapshot.isDataAvailable, snapshot.isExternalConnected else {
            return .none
        }
        return snapshot.isCharging ? .chargingBolt : .pluggedInPlug
    }

    static func spec(
        for snapshot: PowerSnapshot,
        showsPercent: Bool = false,
        isDarkMenuBar: Bool,
        style: BatteryIconStyle
    ) -> BatteryIconRenderSpec {
        BatteryIconRenderSpec(
            percent: snapshot.batteryPercent,
            state: state(for: snapshot),
            overlay: overlay(for: snapshot),
            showsPercent: showsPercent,
            isDarkMenuBar: isDarkMenuBar,
            style: style
        )
    }

    @MainActor
    static func render(spec: BatteryIconRenderSpec) -> NSImage {
        let key = spec.cacheKey
        if let cached = cache.image(for: key) {
            return cached
        }
        let image = makeImage(spec: key, artwork: .system)
        cache.store(image, for: key)
        return image
    }

    @MainActor
    static func makeImage(spec: BatteryIconRenderSpec, artwork: SystemBatteryArtwork) -> NSImage {
        let drawing = BatteryIconDrawing(spec: spec, artwork: artwork)
        let image = NSImage(size: canvasSize, flipped: false) { _ in
            MainActor.assumeIsolated {
                guard let ctx = NSGraphicsContext.current?.cgContext else {
                    return false
                }
                drawing.draw(in: ctx)
                return true
            }
        }
        image.isTemplate = spec.usesTemplateRendering
        return image
    }
}

@MainActor
private final class BoundedImageCache {
    private let maxEntries: Int
    private var storage: [BatteryIconRenderSpec: NSImage] = [:]
    private var insertionOrder: [BatteryIconRenderSpec] = []

    init(maxEntries: Int) {
        self.maxEntries = max(1, maxEntries)
    }

    func image(for key: BatteryIconRenderSpec) -> NSImage? {
        storage[key]
    }

    func store(_ image: NSImage, for key: BatteryIconRenderSpec) {
        if storage[key] == nil {
            if insertionOrder.count >= maxEntries, let evicted = insertionOrder.first {
                insertionOrder.removeFirst()
                storage.removeValue(forKey: evicted)
            }
            insertionOrder.append(key)
        }
        storage[key] = image
    }
}
