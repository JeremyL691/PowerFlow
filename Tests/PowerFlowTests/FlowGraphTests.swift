import XCTest
@testable import PowerFlow

final class FlowGraphTests: XCTestCase {
    private func graph(
        adapterW: Double = 0,
        batteryW: Double = 0,
        loadW: Double = 12,
        onAC: Bool = false,
        flowMode: PowerFlowMode = .batteryOnly,
        outputs: [Double] = []
    ) -> FlowGraph {
        let ports = outputs.enumerated().map { index, watts in
            OutboundPortPower(
                id: "usb-c-out-\(index + 1)",
                portIndex: index + 1,
                portLabel: "USB-C \(index + 1)",
                deviceName: "Device \(index + 1)",
                currentA: watts / 5,
                voltageV: 5,
                powerW: watts
            )
        }
        let outboundW = outputs.reduce(0, +)
        let snapshot = PowerSnapshot(
            isDataAvailable: true,
            connectionPhase: onAC ? .onAC : .onBattery,
            flowMode: flowMode,
            batteryPercent: 60,
            isExternalConnected: onAC,
            isCharging: batteryW > 0,
            batteryCurrentA: batteryW / 12,
            batteryPowerW: batteryW,
            totalSystemLoadW: loadW,
            netSystemLoadW: loadW - outboundW,
            adapterInputPowerW: adapterW,
            outboundPorts: ports,
            totalOutboundPowerW: outboundW
        )
        return FlowGraph(snapshot: snapshot, language: .english)
    }

    private func direction(_ graph: FlowGraph, _ id: String) -> String? {
        graph.links.first { $0.id == id && $0.isActive }.map { "\($0.from)>\($0.to)" }
    }

    func testBatteryOnlyFlowsIntoTheMac() {
        let graph = graph(batteryW: -12)
        XCTAssertEqual(graph.sources.map(\.id), [FlowGraph.batteryID])
        XCTAssertEqual(direction(graph, FlowGraph.batteryID), "battery>mac")
        XCTAssertEqual(graph.links.first?.kind, .discharge)
        XCTAssertEqual(graph.links.first?.watts ?? 0, 12, accuracy: 0.001)
    }

    func testHybridFlowsFromBothSourcesIntoTheMac() {
        let graph = graph(adapterW: 60, batteryW: -15, loadW: 75, onAC: true, flowMode: .adapterBatteryHybrid)
        XCTAssertEqual(graph.sources.map(\.id), [FlowGraph.adapterID, FlowGraph.batteryID])
        XCTAssertEqual(direction(graph, FlowGraph.adapterID), "adapter>mac")
        XCTAssertEqual(direction(graph, FlowGraph.batteryID), "battery>mac")
    }

    func testChargingBranchesFromTheChargerToMacAndBattery() {
        let graph = graph(adapterW: 60, batteryW: 35, loadW: 25, onAC: true, flowMode: .adapterCharging)
        XCTAssertEqual(direction(graph, FlowGraph.adapterID), "adapter>mac")
        XCTAssertEqual(direction(graph, FlowGraph.batteryID), "adapter>battery")
        XCTAssertEqual(graph.links.map(\.kind), [.adapter, .charge])
        // The two branches add up to what the charger delivers.
        XCTAssertEqual(graph.links.map(\.watts), [25, 35])
        XCTAssertEqual(graph.sources.first?.value, "60.0 W")
    }

    func testChargerThatSuppliesNothingStaysConnectedWithoutFlow() {
        let graph = graph(adapterW: 0.45, batteryW: -15, loadW: 15, onAC: true, flowMode: .batteryWhilePluggedIn)
        XCTAssertNil(direction(graph, FlowGraph.adapterID))
        XCTAssertEqual(direction(graph, FlowGraph.batteryID), "battery>mac")
        XCTAssertEqual(graph.sources.first?.value, L10n.string(.standby, language: .english))
    }

    func testIdleBatteryStaysConnectedWithoutFlow() {
        let graph = graph(adapterW: 14, onAC: true, flowMode: .adapterBypass)
        XCTAssertEqual(direction(graph, FlowGraph.adapterID), "adapter>mac")
        XCTAssertNotNil(graph.links.first { $0.id == FlowGraph.batteryID })
        XCTAssertNil(direction(graph, FlowGraph.batteryID))
    }

    func testDevicesFlowOutOfTheMacWhichKeepsTheRemainder() {
        let graph = graph(adapterW: 20, loadW: 20, onAC: true, flowMode: .adapterBypass, outputs: [4, 2])
        XCTAssertEqual(graph.outputs.map(\.title), ["Device 1", "Device 2"])
        XCTAssertEqual(direction(graph, "usb-c-out-1"), "mac>usb-c-out-1")
        XCTAssertEqual(graph.mac.value, "14.0 W")
    }

    func testManyDevicesShareTheLastNode() {
        let graph = graph(adapterW: 40, loadW: 40, onAC: true, flowMode: .adapterBypass, outputs: [5, 4, 3, 2])
        XCTAssertEqual(graph.outputs.map(\.title), ["Device 1", "Device 2", "2 more"])
        XCTAssertEqual(graph.links.last?.watts ?? 0, 5, accuracy: 0.001)
    }

    func testNegotiatingAdapterAnimatesWithoutReportingPower() {
        let graph = graph(onAC: true, flowMode: .connectingAC)
        XCTAssertEqual(direction(graph, FlowGraph.adapterID), "adapter>mac")
        XCTAssertEqual(graph.sources.first?.value, L10n.string(.flowConnectingAC, language: .english))
    }

    func testMissingDataShowsOnlyTheMac() {
        let graph = FlowGraph(snapshot: .empty, language: .english)
        XCTAssertTrue(graph.sources.isEmpty && graph.outputs.isEmpty && graph.links.isEmpty)
    }

    func testStructureIgnoresChangingWattsButNotDirection() {
        XCTAssertEqual(graph(batteryW: -12).structure, graph(batteryW: -9).structure)
        XCTAssertNotEqual(
            graph(adapterW: 60, batteryW: 35, onAC: true, flowMode: .adapterCharging).structure,
            graph(adapterW: 60, batteryW: -15, onAC: true, flowMode: .adapterBatteryHybrid).structure
        )
    }

    func testSingleHubConnectionIsCentred() {
        let graph = graph(adapterW: 60, batteryW: 35, loadW: 25, onAC: true, flowMode: .adapterCharging)
        let layout = FlowLayout(graph: graph, width: 414)
        XCTAssertEqual(layout.routes[FlowGraph.adapterID]?.end.y, layout.frames[FlowGraph.macID]?.midY)
    }

    // MARK: - Layout

    func testNodesNeverOverlapAndLinksRunBetweenTheirEdges() {
        let graphs = [
            graph(batteryW: -12),
            graph(adapterW: 60, batteryW: -15, onAC: true, flowMode: .adapterBatteryHybrid),
            graph(adapterW: 60, batteryW: 35, loadW: 25, onAC: true, flowMode: .adapterCharging),
            graph(adapterW: 60, batteryW: 20, loadW: 40, onAC: true, flowMode: .adapterCharging, outputs: [5, 4, 3]),
            graph(adapterW: 40, loadW: 40, onAC: true, flowMode: .adapterBypass, outputs: [5, 4, 3])
        ]
        for graph in graphs {
            let width: CGFloat = 414
            let layout = FlowLayout(graph: graph, width: width)
            let bounds = CGRect(x: 0, y: 0, width: width, height: FlowLayout.height(for: graph))
            let frames = Array(layout.frames.values)
            for (index, frame) in frames.enumerated() {
                XCTAssertTrue(bounds.contains(frame))
                for other in frames.dropFirst(index + 1) {
                    XCTAssertFalse(frame.intersects(other))
                }
            }
            for link in graph.links {
                guard let route = layout.routes[link.id] else {
                    XCTFail("no route for \(link.id)")
                    continue
                }
                XCTAssertGreaterThanOrEqual(hypot(route.end.x - route.start.x, route.end.y - route.start.y), 40)
                if link.kind == .charge {
                    XCTAssertEqual(route.start.x, route.end.x)
                    XCTAssertLessThan(route.start.y, route.end.y)
                }
            }
        }
    }

    func testMorePowerFlowsFasterAndThicker() {
        XCTAssertGreaterThan(FlowDynamics.pointsPerSecond(for: 60), FlowDynamics.pointsPerSecond(for: 5))
        XCTAssertGreaterThan(FlowDynamics.lineWidth(for: 60), FlowDynamics.lineWidth(for: 5))
        XCTAssertLessThanOrEqual(FlowDynamics.lineWidth(for: 400), 8)
    }
}
