import Foundation

extension PowerFlowResolver {
    // MARK: - Outbound Port Power Mapping

    /// Merges IOKit `PowerOutDetails` (refreshed about once a minute) with live SMC port output
    /// (refreshed about once a second). A live reading overrides current, voltage and power.
    static func resolveOutboundPorts(
        powerOutDetails: [RawPowerOutEntry],
        fedDetails: [RawFedPortEntry],
        portTopology: [IOPortTopologyEntry],
        liveOutputs: [Int: SMCPortOutput] = [:]
    ) -> [OutboundPortPower] {
        var results: [OutboundPortPower] = []
        var handledPorts = Set<Int>()
        var deduplicatedEntries: [Int: RawPowerOutEntry] = [:]

        for entry in powerOutDetails {
            if let existing = deduplicatedEntries[entry.portIndex] {
                if entry.wattsMW > existing.wattsMW
                    || (entry.wattsMW == existing.wattsMW && entry.currentMA > existing.currentMA)
                {
                    deduplicatedEntries[entry.portIndex] = entry
                }
            } else {
                deduplicatedEntries[entry.portIndex] = entry
            }
        }

        for (portIndex, entry) in deduplicatedEntries.sorted(by: { $0.key < $1.key }) {
            handledPorts.insert(portIndex)
            let live = liveOutputs[portIndex]
            if let live, isLiveOff(live) { continue }

            if let port = makeOutboundPort(
                portIndex: portIndex,
                entry: entry,
                live: live,
                fedDetails: fedDetails,
                portTopology: portTopology
            ) {
                results.append(port)
            }
        }

        // Devices plugged in less than a minute ago have live output but no IOKit entry yet.
        // Pass any VBUS-active port (voltageV >= 3.0) through to OutboundPortGate so brief
        // 0.04–0.09 W dips are governed by gate hysteresis instead of being dropped early.
        for (portIndex, live) in liveOutputs.sorted(by: { $0.key < $1.key }) where !handledPorts.contains(portIndex) {
            guard live.voltageV >= 3.0 else { continue }
            let hasUSBCPort = portTopology.isEmpty
                || portTopology.contains { $0.portKind == .usbC && $0.portNumber == portIndex }
            guard hasUSBCPort else { continue }

            if let port = makeOutboundPort(
                portIndex: portIndex,
                entry: nil,
                live: live,
                fedDetails: fedDetails,
                portTopology: portTopology
            ) {
                results.append(port)
            }
        }

        return results.sorted { $0.portIndex < $1.portIndex }
    }

    private static func isLiveOff(_ live: SMCPortOutput) -> Bool {
        live.voltageV < 1.0 && live.currentA < 0.005
    }

    private static func makeOutboundPort(
        portIndex: Int,
        entry: RawPowerOutEntry?,
        live: SMCPortOutput?,
        fedDetails: [RawFedPortEntry],
        portTopology: [IOPortTopologyEntry]
    ) -> OutboundPortPower? {
        let voltageV = live?.voltageV ?? entry.map { Double($0.voltageMV) / 1000.0 } ?? 0
        let currentA = live?.currentA ?? entry.map { Double($0.currentMA) / 1000.0 } ?? 0
        let rawWattsW = entry.map { Double($0.wattsMW) / 1000.0 } ?? 0
        let filteredW = entry.map { Double($0.filteredPowerMW) / 1000.0 } ?? 0
        let vconnCurrentA = entry.map { Double($0.vconnCurrentMA) / 1000.0 } ?? 0
        let vconnPowerW = entry.map { Double($0.vconnPowerMW) / 1000.0 } ?? 0

        let powerW: Double = {
            if let live { return live.voltageV * live.currentA }
            if rawWattsW > 0.01 { return rawWattsW }
            if filteredW > 0.01 { return filteredW }
            let computed = voltageV * currentA
            return computed > 0.01 ? computed : 0
        }()

        let isLiveVBUSActive = live.map { $0.voltageV >= 3.0 } ?? false
        // Skip inactive / disconnected entries drawing zero power unless live VBUS is still up.
        guard isLiveVBUSActive || powerW > 0.01 || currentA > 0.005 || vconnPowerW > 0.01 else {
            return nil
        }

        let matchedPort = matchOutboundPort(
            portIndex: portIndex,
            fedDetails: fedDetails,
            portTopology: portTopology
        )

        let portLabel = matchedPort?.portLabel ?? "USB-C \(portIndex)"
        let isDisplayPortActive = matchedPort?.isDisplayPortActive ?? false
        let deviceName: String = {
            if let name = matchedPort?.usbProductName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty
            {
                return name
            }
            if isDisplayPortActive {
                return "External Display"
            }
            return "USB-C Device"
        }()

        let configuredVoltageV = entry.map { Double($0.configuredVoltageMV) / 1000.0 } ?? 0
        let configuredCurrentA = entry.map { Double($0.configuredCurrentMA) / 1000.0 } ?? 0
        let maxPDWatts: Double = {
            if let entry, entry.pdPowerMW > 0 {
                return Double(entry.pdPowerMW) / 1000.0
            }
            return configuredVoltageV * configuredCurrentA
        }()

        let matchedFed = matchFedEntry(
            portIndex: portIndex,
            matchedPort: matchedPort,
            fedDetails: fedDetails
        )
        let filteredPowerW: Double? = (entry?.filteredPowerMW ?? 0) > 0 ? filteredW : nil

        return OutboundPortPower(
            id: "usb-c-out-\(portIndex)",
            portIndex: portIndex,
            portLabel: portLabel,
            deviceName: deviceName,
            manufacturer: matchedPort?.usbManufacturer,
            isDisplayPortActive: isDisplayPortActive,
            currentA: currentA,
            voltageV: voltageV,
            powerW: powerW,
            configuredVoltageV: configuredVoltageV,
            configuredCurrentA: configuredCurrentA,
            maxPDWatts: maxPDWatts,
            vconnCurrentA: vconnCurrentA,
            vconnPowerW: vconnPowerW,
            filteredPowerW: filteredPowerW,
            activeTransports: matchedPort?.activeTransports ?? [],
            cableType: matchedPort?.cableType,
            pdSpecRevision: matchedFed?.pdSpecRevision
        )
    }

    private static func matchFedEntry(
        portIndex: Int,
        matchedPort: IOPortTopologyEntry?,
        fedDetails: [RawFedPortEntry]
    ) -> RawFedPortEntry? {
        if let port = matchedPort, let vid = port.sopVendorID, vid > 0 {
            if let exact = fedDetails.first(where: { fed in
                fed.vendorID == vid && (fed.productID == 0 || port.sopProductID == nil || fed.productID == port.sopProductID)
            }) {
                return exact
            }
        }
        return fedDetails.first(where: { $0.arrayIndex == portIndex })
            ?? fedDetails.first(where: { $0.arrayIndex == portIndex - 1 })
    }

    // MARK: - Physical Port Map

    static func resolvePhysicalPorts(
        portTopology: [IOPortTopologyEntry],
        connectionPhase: PowerConnectionPhase,
        activeAdapter: AdapterSourceInfo?,
        standbyAdapters: [AdapterSourceInfo],
        outboundPorts: [OutboundPortPower],
        adapterInputPowerW: Double,
        adapterInputCurrentA: Double,
        adapterInputVoltageV: Double
    ) -> [PhysicalPortStatus] {
        let sorted = portTopology.sorted { lhs, rhs in
            if lhs.portKind != rhs.portKind {
                return portSortOrder(lhs.portKind) < portSortOrder(rhs.portKind)
            }
            return lhs.portNumber < rhs.portNumber
        }

        return sorted.map { entry in
            let id = "\(entry.portKind.rawValue)-\(entry.portNumber)"
            let matchedOutbound = outboundPorts.first { out in
                (entry.portKind == .usbC && out.portIndex == entry.portNumber)
                    || out.portLabel == entry.portLabel
            }

            if connectionPhase != .onBattery && entry.isWinningPowerSource {
                let maxPD = activeAdapter?.ratedWatts
                    ?? (entry.winningMaxPowerMW.map { Double($0) / 1000.0 } ?? 0)
                return PhysicalPortStatus(
                    id: id,
                    portKind: entry.portKind,
                    portNumber: entry.portNumber,
                    portLabel: entry.portLabel,
                    role: .powerInActive,
                    connectionActive: true,
                    deviceName: activeAdapter?.name ?? entry.usbProductName,
                    manufacturer: activeAdapter?.manufacturer ?? entry.usbManufacturer,
                    cableType: entry.cableType,
                    activeTransports: entry.activeTransports,
                    powerW: adapterInputPowerW,
                    currentA: adapterInputCurrentA,
                    voltageV: adapterInputVoltageV,
                    maxPDWatts: maxPD
                )
            }

            if let out = matchedOutbound {
                return PhysicalPortStatus(
                    id: id,
                    portKind: entry.portKind,
                    portNumber: entry.portNumber,
                    portLabel: entry.portLabel,
                    role: .powerOut,
                    connectionActive: true,
                    deviceName: out.deviceName,
                    manufacturer: out.manufacturer ?? entry.usbManufacturer,
                    cableType: entry.cableType,
                    activeTransports: entry.activeTransports,
                    powerW: out.powerW,
                    currentA: out.currentA,
                    voltageV: out.voltageV,
                    maxPDWatts: out.maxPDWatts,
                    vconnPowerW: out.vconnPowerW,
                    vconnCurrentA: out.vconnCurrentA
                )
            }

            if connectionPhase != .onBattery
                && entry.connectionActive
                && !entry.isWinningPowerSource
                && (entry.standbyMaxPowerMW ?? 0) > 0
            {
                let standby = standbyAdapters.first {
                    $0.portKind == entry.portKind && $0.portNumber == entry.portNumber
                }
                let deviceName = entry.usbProductName
                    ?? (entry.isDisplayPortActive ? "External Display" : standby?.name)
                return PhysicalPortStatus(
                    id: id,
                    portKind: entry.portKind,
                    portNumber: entry.portNumber,
                    portLabel: entry.portLabel,
                    role: .powerInStandby,
                    connectionActive: true,
                    deviceName: deviceName,
                    manufacturer: entry.usbManufacturer ?? standby?.manufacturer,
                    cableType: entry.cableType,
                    activeTransports: entry.activeTransports,
                    maxPDWatts: Double(entry.standbyMaxPowerMW ?? 0) / 1000.0
                )
            }

            if entry.connectionActive {
                let deviceName: String? = {
                    if let name = entry.usbProductName?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !name.isEmpty
                    {
                        return name
                    }
                    if entry.isDisplayPortActive {
                        return "External Display"
                    }
                    return nil
                }()
                return PhysicalPortStatus(
                    id: id,
                    portKind: entry.portKind,
                    portNumber: entry.portNumber,
                    portLabel: entry.portLabel,
                    role: .dataOnly,
                    connectionActive: true,
                    deviceName: deviceName,
                    manufacturer: entry.usbManufacturer,
                    cableType: entry.cableType,
                    activeTransports: entry.activeTransports
                )
            }

            return PhysicalPortStatus(
                id: id,
                portKind: entry.portKind,
                portNumber: entry.portNumber,
                portLabel: entry.portLabel,
                role: .idle,
                connectionActive: false,
                cableType: entry.cableType,
                activeTransports: entry.activeTransports
            )
        }
    }

    private static func portSortOrder(_ kind: PowerPortKind) -> Int {
        switch kind {
        case .magSafe: return 0
        case .usbC: return 1
        case .unknown: return 2
        }
    }

    private static func matchOutboundPort(
        portIndex: Int,
        fedDetails: [RawFedPortEntry],
        portTopology: [IOPortTopologyEntry]
    ) -> IOPortTopologyEntry? {
        if let direct = portTopology.first(where: { $0.portKind == .usbC && $0.portNumber == portIndex }) {
            return direct
        }

        // Fallback: correlate via FedDetails VID/PID against IOPort SOP VID/PID.
        let fedCandidates: [RawFedPortEntry] = [
            fedDetails.first(where: { $0.arrayIndex == portIndex && $0.vendorID > 0 }),
            fedDetails.first(where: { $0.arrayIndex == portIndex - 1 && $0.vendorID > 0 })
        ].compactMap { $0 }

        for fed in fedCandidates {
            if let match = portTopology.first(where: { port in
                guard port.portKind == .usbC, let vid = port.sopVendorID, vid == fed.vendorID else {
                    return false
                }
                if fed.productID > 0, let pid = port.sopProductID {
                    return pid == fed.productID
                }
                return true
            }) {
                return match
            }
        }

        return nil
    }
}
