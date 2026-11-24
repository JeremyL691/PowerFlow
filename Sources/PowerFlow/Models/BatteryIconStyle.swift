import Foundation

/// The two menu bar battery designs Apple has shipped, selectable in Settings.
enum BatteryIconStyle: String, CaseIterable, Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Outlined shell with an inset charge bar; the percentage sits beside the icon.
    case outlined
    /// Solid shell with a dimmed track (macOS 27); the percentage is cut out of the icon.
    case solid

    var id: String { rawValue }

    var drawsPercentInsideIcon: Bool {
        self == .solid
    }
}
