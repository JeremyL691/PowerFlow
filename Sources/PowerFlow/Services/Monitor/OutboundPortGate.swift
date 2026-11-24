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

    private let lock = NSLock()
    /// When each open port last drew at least `closeWatts`.
    private var lastDraw: [Int: Date] = [:]

    func filter(_ ports: [OutboundPortPower], at now: Date) -> [OutboundPortPower] {
        lock.lock()
        defer { lock.unlock() }

        var updated: [Int: Date] = [:]
        let kept = ports.filter { port in
            let previous = lastDraw[port.portIndex]
            if port.powerW >= (previous == nil ? Self.openWatts : Self.closeWatts) {
                updated[port.portIndex] = now
                return true
            }
            guard let previous, (0..<Self.holdSeconds).contains(now.timeIntervalSince(previous)) else {
                return false
            }
            updated[port.portIndex] = previous
            return true
        }
        lastDraw = updated
        return kept
    }
}
