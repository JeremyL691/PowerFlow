import Foundation

enum PowerPollingTier: Equatable, Sendable {
    /// Monitor stopped, system asleep, or displays asleep — zero timers.
    case suspended
    /// Popover hidden in `.iconOnly` / `.iconAndPercentage` — zero timers (purely event-driven).
    case dormant
    /// Popover hidden in `.iconAndWatts` / `.iconPercentageAndWatts` — lightweight 3.0s summary timer.
    case summary(interval: TimeInterval)
    /// Popover visible — live telemetry timer at user-configured interval (1.0s / 2.0s).
    case live(interval: TimeInterval)

    var hasRecurringTimer: Bool {
        switch self {
        case .suspended, .dormant:
            return false
        case .summary, .live:
            return true
        }
    }

    var includesFullHardwareScan: Bool {
        switch self {
        case .live:
            return true
        case .suspended, .dormant, .summary:
            return false
        }
    }
}
