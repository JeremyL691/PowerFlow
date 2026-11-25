import XCTest
@testable import PowerFlow

final class OutboundLivePowerTests: XCTestCase {

    // MARK: - Port Override Rules

    func testLiveReadingOverridesStaleEntry() {
        let stale = makePowerOutEntry(portIndex: 2, currentMA: 1_040, voltageMV: 5_000, maxPDMW: 15_000)
        let ports = resolveOutbound(
            powerOut: [stale],
            live: [2: SMCPortOutput(currentA: 0.5, voltageV: 9.0)],
            topology: [makeUSBCTopology(port: 2, name: "Demo Phone")]
        )

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].currentA, 0.5, accuracy: 0.001)
        XCTAssertEqual(ports[0].voltageV, 9.0, accuracy: 0.001)
        XCTAssertEqual(ports[0].powerW, 4.5, accuracy: 0.001)
        XCTAssertEqual(ports[0].maxPDWatts, 15.0, accuracy: 0.001)
        XCTAssertEqual(ports[0].deviceName, "Demo Phone")
    }

    func testLiveOffReadingDropsStaleEntry() {
        let stale = makePowerOutEntry(portIndex: 2, currentMA: 1_040, voltageMV: 5_000, vconnMW: 200)
        let ports = resolveOutbound(
            powerOut: [stale],
            live: [2: SMCPortOutput(currentA: 0.0, voltageV: 0.0)],
            topology: [makeUSBCTopology(port: 2, name: "Demo Phone")]
        )

        XCTAssertTrue(ports.isEmpty)
    }

    func testLivePortWithoutEntryIsAdded() {
        let ports = resolveOutbound(
            powerOut: [],
            live: [2: SMCPortOutput(currentA: 1.2, voltageV: 5.0)],
            topology: [makeUSBCTopology(port: 2, name: "Demo Phone")]
        )

        XCTAssertEqual(ports.count, 1)
        let port = ports[0]
        XCTAssertEqual(port.id, "usb-c-out-2")
        XCTAssertEqual(port.portIndex, 2)
        XCTAssertEqual(port.portLabel, "USB-C 2")
        XCTAssertEqual(port.deviceName, "Demo Phone")
        XCTAssertEqual(port.powerW, 6.0, accuracy: 0.001)
        XCTAssertEqual(port.configuredVoltageV, 0)
        XCTAssertEqual(port.configuredCurrentA, 0)
        XCTAssertEqual(port.maxPDWatts, 0)
        XCTAssertEqual(port.vconnCurrentA, 0)
        XCTAssertEqual(port.vconnPowerW, 0)
        XCTAssertNil(port.filteredPowerW)
    }

    func testLivePortWithoutMatchingUSBCTopologyIsNotAdded() {
        let ports = resolveOutbound(
            powerOut: [],
            live: [3: SMCPortOutput(currentA: 1.0, voltageV: 5.0)],
            topology: [makeUSBCTopology(port: 2, name: "Demo Phone")]
        )

        XCTAssertTrue(ports.isEmpty)
    }

    func testNoLiveReadingsKeepsIOKitValues() {
        let entry = makePowerOutEntry(portIndex: 2, wattsMW: 5_200, currentMA: 1_040, voltageMV: 5_000)
        let ports = resolveOutbound(
            powerOut: [entry],
            live: [:],
            topology: [makeUSBCTopology(port: 2, name: "Demo Phone")]
        )

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].powerW, 5.2, accuracy: 0.001)
        XCTAssertEqual(ports[0].currentA, 1.04, accuracy: 0.001)
        XCTAssertEqual(ports[0].voltageV, 5.0, accuracy: 0.001)
    }

    func testLiveReadingsFlowIntoSnapshotTotal() {
        let resolver = makeIsolatedResolver()
        let reading = makeReading(
            isExternalConnected: true,
            powerOutDetails: [makePowerOutEntry(portIndex: 2, wattsMW: 5_200, currentMA: 1_040, voltageMV: 5_000)]
        )

        let snap = resolver.resolve(
            reading: reading,
            smc: SMCPowerSample(portOutputs: [2: SMCPortOutput(currentA: 2.0, voltageV: 5.0)]),
            portTopology: [makeUSBCTopology(port: 2, name: "Demo Phone")],
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false
        )

        XCTAssertEqual(snap.outboundPorts.count, 1)
        XCTAssertEqual(snap.outboundPorts[0].powerW, 10.0, accuracy: 0.001)
        XCTAssertEqual(snap.totalOutboundPowerW, 10.0, accuracy: 0.001)
    }

    func testDuplicatePortIndexEntriesAreDeduplicated() {
        let lower = makePowerOutEntry(portIndex: 2, wattsMW: 1_000, currentMA: 200, voltageMV: 5_000)
        let higher = makePowerOutEntry(portIndex: 2, wattsMW: 5_200, currentMA: 1_040, voltageMV: 5_000)
        let ports = resolveOutbound(
            powerOut: [lower, higher],
            live: [:],
            topology: [makeUSBCTopology(port: 2, name: "Demo Phone")]
        )

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].portIndex, 2)
        XCTAssertEqual(ports[0].powerW, 5.2, accuracy: 0.001)
    }

    func testLiveVBUSActiveDipPassesThroughResolveOutboundPorts() {
        // 0.01A @ 5.0V = 0.05W: below 0.02A but VBUS is active (>= 3.0V), so resolver lets OutboundPortGate decide.
        let ports = resolveOutbound(
            powerOut: [],
            live: [2: SMCPortOutput(currentA: 0.01, voltageV: 5.0)],
            topology: [makeUSBCTopology(port: 2, name: "Demo Phone")]
        )

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].portIndex, 2)
        XCTAssertEqual(ports[0].powerW, 0.05, accuracy: 0.001)
    }

    func testLivePortBriefDipThroughResolverHysteresisDoesNotBlink() {
        let resolver = makeIsolatedResolver()
        let topology = [makeUSBCTopology(port: 2, name: "Demo Phone")]
        let reading = makeReading(isExternalConnected: true, powerOutDetails: [])
        let t0 = Date(timeIntervalSince1970: 5_000)

        let open = resolver.resolve(
            reading: reading,
            smc: SMCPowerSample(deliveryRateW: 25, portOutputs: [2: SMCPortOutput(currentA: 0.5, voltageV: 5.0)]),
            portTopology: topology,
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false,
            timestamp: t0
        )
        XCTAssertEqual(open.outboundPorts.count, 1)

        // Brief 0.06W dip (0.012A @ 5.0V) for 2 seconds must stay open via OutboundPortGate hysteresis.
        let dip1 = resolver.resolve(
            reading: reading,
            smc: SMCPowerSample(deliveryRateW: 25, portOutputs: [2: SMCPortOutput(currentA: 0.012, voltageV: 5.0)]),
            portTopology: topology,
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false,
            timestamp: t0.addingTimeInterval(1)
        )
        let dip2 = resolver.resolve(
            reading: reading,
            smc: SMCPowerSample(deliveryRateW: 25, portOutputs: [2: SMCPortOutput(currentA: 0.012, voltageV: 5.0)]),
            portTopology: topology,
            connectionPhase: .onAC,
            isLowPowerModeEnabled: false,
            timestamp: t0.addingTimeInterval(2)
        )
        XCTAssertEqual(dip1.outboundPorts.count, 1)
        XCTAssertEqual(dip2.outboundPorts.count, 1)
    }

    // MARK: - Helpers

    private func resolveOutbound(
        powerOut: [RawPowerOutEntry],
        live: [Int: SMCPortOutput],
        topology: [IOPortTopologyEntry]
    ) -> [OutboundPortPower] {
        PowerFlowResolver.resolveOutboundPorts(
            powerOutDetails: powerOut,
            fedDetails: [],
            portTopology: topology,
            liveOutputs: live
        )
    }

    private func makePowerOutEntry(
        portIndex: Int,
        wattsMW: Int? = nil,
        currentMA: Int,
        voltageMV: Int,
        maxPDMW: Int = 15_000,
        vconnMW: Int = 0
    ) -> RawPowerOutEntry {
        RawPowerOutEntry(
            portIndex: portIndex,
            wattsMW: wattsMW ?? currentMA * voltageMV / 1_000,
            filteredPowerMW: wattsMW ?? currentMA * voltageMV / 1_000,
            currentMA: currentMA,
            voltageMV: voltageMV,
            configuredVoltageMV: 5_000,
            configuredCurrentMA: 3_000,
            pdPowerMW: maxPDMW,
            vconnCurrentMA: vconnMW > 0 ? 40 : 0,
            vconnPowerMW: vconnMW
        )
    }

    private func makeUSBCTopology(port: Int, name: String) -> IOPortTopologyEntry {
        IOPortTopologyEntry(
            portKind: .usbC,
            portNumber: port,
            portLabel: "USB-C \(port)",
            connectionActive: true,
            isWinningPowerSource: false,
            winningMaxPowerMW: nil,
            winningMaxCurrentMA: nil,
            standbyMaxPowerMW: nil,
            sopVendorID: nil,
            sopProductID: nil,
            usbProductName: name,
            usbManufacturer: nil,
            isDisplayPortActive: false
        )
    }
}

// MARK: - SMC Port Output Parsing

final class SMCPortOutputTests: XCTestCase {

    func testFullSampleReturnsOnlyValidPorts() {
        let reader = PortSMCKeyReader(values: [
            "D1JI": makeFloatValue(key: "D1JI", value: 0.5),
            "D1JV": makeFloatValue(key: "D1JV", value: 5.0),
            "D2JI": makeFloatValue(key: "D2JI", value: 1.0),
            "D2JV": makeFloatValue(key: "D2JV", value: 70.0),   // voltage out of range
            "D3JI": makeFloatValue(key: "D3JI", value: -0.02),  // tiny negative clamps to zero
            "D3JV": makeFloatValue(key: "D3JV", value: 5.0),
            "D4JI": makeFloatValue(key: "D4JI", value: 12.0),   // current out of range
            "D4JV": makeFloatValue(key: "D4JV", value: 5.0)
        ])

        let sample = SMCReader(keyReader: reader).readSample(full: true)

        XCTAssertEqual(Set(sample.portOutputs.keys), [1, 3])
        XCTAssertEqual(sample.portOutputs[1]?.currentA ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(sample.portOutputs[1]?.voltageV ?? -1, 5.0, accuracy: 0.001)
        XCTAssertEqual(sample.portOutputs[3]?.currentA ?? -1, 0.0, accuracy: 0.0001)
    }

    func testPortWithMissingVoltageKeyIsExcluded() {
        let reader = PortSMCKeyReader(values: [
            "D2JI": makeFloatValue(key: "D2JI", value: 1.0)
        ])

        let sample = SMCReader(keyReader: reader).readSample(full: true)

        XCTAssertNil(sample.portOutputs[2])
    }

    func testLightSampleDoesNotReadPortOutputs() {
        let reader = PortSMCKeyReader(values: [
            "PDTR": makeFloatValue(key: "PDTR", value: 30.0),
            "D1JI": makeFloatValue(key: "D1JI", value: 0.5),
            "D1JV": makeFloatValue(key: "D1JV", value: 5.0)
        ])

        let sample = SMCReader(keyReader: reader).readSample(full: false)

        XCTAssertEqual(sample.deliveryRateW ?? 0, 30.0, accuracy: 0.001)
        XCTAssertTrue(sample.portOutputs.isEmpty)
    }

    // MARK: - Helpers

    private func makeFloatValue(key: String, value: Float) -> SMCValue {
        let bits = value.bitPattern
        let bytes: [UInt8] = [
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF)
        ]
        return SMCValue(key: key, dataSize: 4, dataType: "flt ", bytes: bytes)
    }
}

private final class PortSMCKeyReader: SMCKeyReading, @unchecked Sendable {
    private let values: [String: SMCValue]

    init(values: [String: SMCValue]) {
        self.values = values
    }

    func readKey(_ key: String) -> SMCValue? {
        values[key]
    }
}
