import Foundation

/// Decides which ports count as supplying power.
///
/// A self-powered device still draws a few milliamps (about 0.04–0.08 W) for cable handshaking, right
/// where a single threshold would make it blink. A port therefore opens at one level, closes at a
/// lower one, and stays open through brief dips.
final class OutboundPortGate: @unchecked Sendable {
    static let openWatts = 0.15
    static let closeWatts = 0.11
    static let holdSeconds: TimeInterval = 3

    private struct OpenPortState {
        var lastDraw: Date
        var lastPort: OutboundPortPower
    }

    private let lock = NSLock()
    /// When each open port last drew at least `closeWatts`, plus its last reading.
    private var openPorts: [Int: OpenPortState] = [:]

    func filter(
        _ ports: [OutboundPortPower],
        at now: Date,
        hasLivePortOutputs: Bool = true
    ) -> [OutboundPortPower] {
        lock.lock()
        defer { lock.unlock() }

        var updated: [Int: OpenPortState] = [:]
        var seenIndices = Set<Int>()
        var kept: [OutboundPortPower] = []

        for port in ports {
            seenIndices.insert(port.portIndex)
            let previous = openPorts[port.portIndex]
            if port.powerW >= (previous == nil ? Self.openWatts : Self.closeWatts) {
                updated[port.portIndex] = OpenPortState(lastDraw: now, lastPort: port)
                kept.append(port)
                continue
            }
            guard let previous, (0..<Self.holdSeconds).contains(now.timeIntervalSince(previous.lastDraw)) else {
                continue
            }
            updated[port.portIndex] = OpenPortState(lastDraw: previous.lastDraw, lastPort: port)
            kept.append(port)
        }

        if !hasLivePortOutputs {
            for (portIndex, previous) in openPorts where !seenIndices.contains(portIndex) {
                guard (0..<Self.holdSeconds).contains(now.timeIntervalSince(previous.lastDraw)) else {
                    continue
                }
                updated[portIndex] = previous
                kept.append(previous.lastPort)
            }
            kept.sort { $0.portIndex < $1.portIndex }
        }

        openPorts = updated
        return kept
    }
}
