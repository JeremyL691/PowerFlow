import AppKit

/// Glyphs used by the menu bar battery, loaded from the running system's own Control Center
/// so they always match the installed macOS release. Nothing is bundled with PowerFlow.
struct SystemBatteryArtwork {
    enum Piece: String, CaseIterable {
        case cap = "battery-cap"
        case missing = "battery-missing"
        case bolt = "battery-bolt"
        case boltMask = "battery-bolt-mask"
        case boltLarge = "battery-bolt-large"
        case boltMaskLarge = "battery-bolt-mask-large"
        case plug = "battery-plug"
        case plugMask = "battery-plug-mask"
        case plugLarge = "battery-plug-large"
        case plugMaskLarge = "battery-plug-mask-large"
    }

    private let load: (Piece) -> NSImage?

    init(load: @escaping (Piece) -> NSImage?) {
        self.load = load
    }

    func image(_ piece: Piece) -> NSImage? {
        load(piece)
    }

    nonisolated(unsafe) static let system: SystemBatteryArtwork = {
        let bundle = Bundle(path: "/System/Library/CoreServices/ControlCenter.app")
        var images: [Piece: NSImage] = [:]
        for piece in Piece.allCases {
            images[piece] = bundle?.image(forResource: piece.rawValue)
        }
        let loaded = images
        return SystemBatteryArtwork { loaded[$0] }
    }()

    /// Used when the system artwork is missing; every glyph falls back to SF Symbols.
    nonisolated(unsafe) static let unavailable = SystemBatteryArtwork { _ in nil }
}
