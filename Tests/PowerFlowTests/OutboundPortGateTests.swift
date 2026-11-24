import XCTest
@testable import PowerFlow

final class OutboundPortGateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func port(_ watts: Double, index: Int = 2) -> OutboundPortPower {
        OutboundPortPower(
            id: "usb-c-out-\(index)",
            portIndex: index,
            portLabel: "USB-C \(index)",
            currentA: watts / 5.2,
            voltageV: 5.2,
            powerW: watts
        )
    }

    /// Feeds one reading per second and returns whether the port is shown after each.
    private func run(_ gate: OutboundPortGate, _ watts: [Double], from offset: TimeInterval = 0) -> [Bool] {
        watts.enumerated().map { index, value in
            !gate.filter([port(value)], at: start.addingTimeInterval(offset + Double(index))).isEmpty
        }
    }

    func testHandshakeCurrentOfASelfPoweredDisplayNeverShows() {
        let readings = [0.048, 0.058, 0.077, 0.048, 0.067, 0.077, 0.038, 0.067, 0.077, 0.048]
        XCTAssertFalse(run(OutboundPortGate(), readings).contains(true))
    }

    func testRealDeviceShowsAtOnce() {
        XCTAssertEqual(run(OutboundPortGate(), [1.6, 1.5, 3.5]), [true, true, true])
        // A small receiver counts too.
        XCTAssertEqual(run(OutboundPortGate(), [0.16, 0.14, 0.12]), [true, true, true])
    }

    func testBriefDipsDoNotBlink() {
        XCTAssertEqual(run(OutboundPortGate(), [1.5, 0.05, 0.06, 1.4, 0.05, 0.05, 0.9]), Array(repeating: true, count: 7))
    }

    func testPortClosesAfterStayingIdle() {
        XCTAssertEqual(run(OutboundPortGate(), [1.5, 0.05, 0.05, 0.05, 0.05]), [true, true, true, false, false])
    }

    func testClosedPortNeedsTheOpeningLevelAgain() {
        let gate = OutboundPortGate()
        _ = run(gate, [1.5, 0.05, 0.05, 0.05])
        XCTAssertEqual(run(gate, [0.12, 0.13, 0.2], from: 4), [false, false, true])
    }

    func testUnpluggedPortDisappearsImmediately() {
        let gate = OutboundPortGate()
        XCTAssertEqual(gate.filter([port(1.5)], at: start).count, 1)
        XCTAssertTrue(gate.filter([], at: start.addingTimeInterval(1)).isEmpty)
        XCTAssertTrue(gate.filter([port(0.12)], at: start.addingTimeInterval(2)).isEmpty)
    }

    func testPortsAreIndependent() {
        let gate = OutboundPortGate()
        let kept = gate.filter([port(0.06, index: 2), port(1.6, index: 3)], at: start)
        XCTAssertEqual(kept.map(\.portIndex), [3])
    }

    func testHandshakeCurrentIsExcludedFromTheTotals() {
        let topology = IOPortTopologyEntry(
            portKind: .usbC, portNumber: 2, portLabel: "USB-C 2", connectionActive: true,
            isWinningPowerSource: false, winningMaxPowerMW: nil, winningMaxCurrentMA: nil,
            standbyMaxPowerMW: nil, sopVendorID: nil, sopProductID: nil,
            usbProductName: "Demo Display", usbManufacturer: nil, isDisplayPortActive: true
        )
        let snapshot = makeIsolatedResolver().resolve(
            reading: makeReading(isExternalConnected: true),
            smc: SMCPowerSample(deliveryRateW: 20, portOutputs: [2: SMCPortOutput(currentA: 0.0147, voltageV: 5.247)]),
            portTopology: [topology],
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )
        XCTAssertFalse(snapshot.hasActiveOutboundPower)
        XCTAssertEqual(snapshot.totalOutboundPowerW, 0)
        XCTAssertEqual(snapshot.netSystemLoadW, snapshot.totalSystemLoadW)
        XCTAssertEqual(snapshot.physicalPorts.first?.role, .dataOnly)
    }
}
