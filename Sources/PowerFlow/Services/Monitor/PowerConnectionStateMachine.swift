import Foundation

/// Prevents stale `SystemPowerIn` / `AdapterDetails` glitches across AC plug-in handshake
/// and brief USB-C PD renegotiation blips.
struct PowerConnectionStateMachine: Sendable, Equatable {
    static let defaultConnectingTimeout: TimeInterval = 3.0
    static let defaultUnplugDebounce: TimeInterval = 1.5

    enum State: Equatable, Sendable {
        case uninitialized
        case onBattery
        case connectingAC(since: Date)
        case onAC(pendingDisconnectSince: Date?)
    }

    private(set) var state: State = .uninitialized
    let connectingTimeout: TimeInterval
    let unplugDebounce: TimeInterval

    init(
        connectingTimeout: TimeInterval = PowerConnectionStateMachine.defaultConnectingTimeout,
        unplugDebounce: TimeInterval = PowerConnectionStateMachine.defaultUnplugDebounce
    ) {
        self.connectingTimeout = connectingTimeout
        self.unplugDebounce = unplugDebounce
    }

    var currentPhase: PowerConnectionPhase {
        switch state {
        case .uninitialized, .onBattery:
            return .onBattery
        case .connectingAC:
            return .connectingAC
        case .onAC:
            return .onAC
        }
    }

    var isInTransition: Bool {
        switch state {
        case .connectingAC:
            return true
        case .onAC(let pendingDisconnectSince):
            return pendingDisconnectSince != nil
        case .uninitialized, .onBattery:
            return false
        }
    }

    mutating func reset() {
        state = .uninitialized
    }

    @discardableResult
    mutating func advance(
        isExternalConnected: Bool,
        hasValidACTelemetry: Bool,
        now: Date
    ) -> PowerConnectionPhase {
        switch state {
        case .uninitialized:
            state = isExternalConnected ? .onAC(pendingDisconnectSince: nil) : .onBattery

        case .onBattery:
            if isExternalConnected {
                state = .connectingAC(since: now)
            }

        case .connectingAC(let since):
            if !isExternalConnected {
                state = .onBattery
            } else if hasValidACTelemetry || now.timeIntervalSince(since) >= connectingTimeout {
                state = .onAC(pendingDisconnectSince: nil)
            }

        case .onAC(let pendingDisconnectSince):
            if isExternalConnected {
                if pendingDisconnectSince != nil {
                    state = .onAC(pendingDisconnectSince: nil)
                }
            } else if let disconnectStart = pendingDisconnectSince {
                if now.timeIntervalSince(disconnectStart) >= unplugDebounce {
                    state = .onBattery
                }
            } else {
                state = .onAC(pendingDisconnectSince: now)
            }
        }

        return currentPhase
    }
}
