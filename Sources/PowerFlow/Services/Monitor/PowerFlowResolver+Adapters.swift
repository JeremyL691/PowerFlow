import Foundation

extension PowerFlowResolver {
    // MARK: - Adapter & Port Topology Mapping

    static func resolveAdapters(
        activeRaw: RawAdapterEntry?,
        rawAdapters: [RawAdapterEntry],
        portTopology: [IOPortTopologyEntry]
    ) -> (active: AdapterSourceInfo?, standby: [AdapterSourceInfo]) {
        let winningPort = portTopology.first(where: { $0.isWinningPowerSource })
            ?? portTopology.first(where: { $0.portKind == .magSafe && $0.connectionActive })

        let primaryRaw = activeRaw ?? rawAdapters.first

        let activeInfo: AdapterSourceInfo?
        if primaryRaw != nil || winningPort != nil {
            let portKind = winningPort?.portKind ?? inferPortKind(from: primaryRaw)
            let portNumber = winningPort?.portNumber
            let portLabel = winningPort?.portLabel ?? defaultPortLabel(for: portKind, number: portNumber)

            let ratedWatts: Double = {
                if let w = primaryRaw?.watts, w > 0 { return w }
                if let mw = winningPort?.winningMaxPowerMW, mw > 0 { return Double(mw) / 1000.0 }
                return 0
            }()
            let ratedVoltageV = primaryRaw.map { Double($0.voltageMV) / 1000.0 } ?? 0
            let ratedCurrentA: Double = {
                if let ma = primaryRaw?.currentMA, ma > 0 { return Double(ma) / 1000.0 }
                if let ma = winningPort?.winningMaxCurrentMA, ma > 0 { return Double(ma) / 1000.0 }
                if ratedWatts > 0 && ratedVoltageV > 1.0 { return ratedWatts / ratedVoltageV }
                return 0
            }()

            let idSuffix = primaryRaw?.adapterID.map(String.init) ?? "0"
            activeInfo = AdapterSourceInfo(
                id: "active-\(portLabel)-\(idSuffix)",
                isActive: true,
                portKind: portKind,
                portNumber: portNumber,
                portLabel: portLabel,
                name: primaryRaw?.name,
                manufacturer: primaryRaw?.manufacturer ?? winningPort?.usbManufacturer,
                serialNumber: primaryRaw?.serialNumber,
                model: primaryRaw?.model,
                description: primaryRaw?.description,
                ratedWatts: ratedWatts,
                ratedVoltageV: ratedVoltageV,
                ratedCurrentA: ratedCurrentA,
                connectedDeviceName: winningPort?.usbProductName,
                firmwareVersion: primaryRaw?.firmwareVersion,
                hardwareVersion: primaryRaw?.hardwareVersion,
                adapterID: primaryRaw?.adapterID,
                pdProfiles: primaryRaw?.pdProfiles ?? [],
                activePDProfileIndex: primaryRaw?.activeHvcIndex
            )
        } else {
            activeInfo = nil
        }

        // Build standby pool from AppleRawAdapterDetails excluding the active adapter entry.
        var remainingRaw = rawAdapters
        if let activeRaw {
            if let matchIdx = remainingRaw.firstIndex(where: { matchesActiveAdapter($0, activeRaw) }) {
                remainingRaw.remove(at: matchIdx)
            }
        } else if !remainingRaw.isEmpty && primaryRaw != nil {
            remainingRaw.removeFirst()
        }

        var standbyList: [AdapterSourceInfo] = []
        let standbyPorts = portTopology.filter {
            $0.connectionActive && !$0.isWinningPowerSource && ($0.standbyMaxPowerMW ?? 0) > 0
        }

        for port in standbyPorts {
            let portWatts = Double(port.standbyMaxPowerMW ?? 0) / 1000.0
            let matchedRaw: RawAdapterEntry?
            if let idx = remainingRaw.firstIndex(where: { abs($0.watts - portWatts) <= 3.0 }) {
                matchedRaw = remainingRaw.remove(at: idx)
            } else if !remainingRaw.isEmpty {
                matchedRaw = remainingRaw.removeFirst()
            } else {
                matchedRaw = nil
            }

            let deviceName = port.usbProductName ?? (port.isDisplayPortActive ? "External Display" : nil)
            let ratedWatts = portWatts > 0 ? portWatts : (matchedRaw?.watts ?? 0)
            let ratedVoltageV = matchedRaw.map { Double($0.voltageMV) / 1000.0 } ?? 0
            let ratedCurrentA = matchedRaw.map { Double($0.currentMA) / 1000.0 } ?? 0

            standbyList.append(
                AdapterSourceInfo(
                    id: "standby-\(port.portLabel)",
                    isActive: false,
                    portKind: port.portKind,
                    portNumber: port.portNumber,
                    portLabel: port.portLabel,
                    name: matchedRaw?.name ?? deviceName,
                    manufacturer: matchedRaw?.manufacturer ?? port.usbManufacturer,
                    serialNumber: matchedRaw?.serialNumber,
                    model: matchedRaw?.model,
                    description: matchedRaw?.description,
                    ratedWatts: ratedWatts,
                    ratedVoltageV: ratedVoltageV,
                    ratedCurrentA: ratedCurrentA,
                    connectedDeviceName: deviceName,
                    firmwareVersion: matchedRaw?.firmwareVersion,
                    hardwareVersion: matchedRaw?.hardwareVersion,
                    adapterID: matchedRaw?.adapterID,
                    pdProfiles: matchedRaw?.pdProfiles ?? [],
                    activePDProfileIndex: matchedRaw?.activeHvcIndex
                )
            )
        }

        // If IOPort topology was not scanned (e.g. lightweight mode), still surface extra raw adapters.
        if portTopology.isEmpty {
            for (offset, raw) in remainingRaw.enumerated() where raw.watts > 0 {
                let kind = inferPortKind(from: raw)
                let label = defaultPortLabel(for: kind, number: nil)
                standbyList.append(
                    AdapterSourceInfo(
                        id: "standby-raw-\(raw.index)-\(offset)",
                        isActive: false,
                        portKind: kind,
                        portNumber: nil,
                        portLabel: label,
                        name: raw.name,
                        manufacturer: raw.manufacturer,
                        serialNumber: raw.serialNumber,
                        model: raw.model,
                        description: raw.description,
                        ratedWatts: raw.watts,
                        ratedVoltageV: Double(raw.voltageMV) / 1000.0,
                        ratedCurrentA: Double(raw.currentMA) / 1000.0,
                        connectedDeviceName: raw.name,
                        firmwareVersion: raw.firmwareVersion,
                        hardwareVersion: raw.hardwareVersion,
                        adapterID: raw.adapterID,
                        pdProfiles: raw.pdProfiles,
                        activePDProfileIndex: raw.activeHvcIndex
                    )
                )
            }
        }

        return (activeInfo, standbyList)
    }

    private static func matchesActiveAdapter(_ candidate: RawAdapterEntry, _ active: RawAdapterEntry) -> Bool {
        if let cID = candidate.adapterID, let aID = active.adapterID, cID == aID {
            if let cSerial = candidate.serialNumber, let aSerial = active.serialNumber {
                return cSerial == aSerial
            }
            return abs(candidate.watts - active.watts) < 0.5
        }
        return candidate.name == active.name
            && candidate.serialNumber == active.serialNumber
            && abs(candidate.watts - active.watts) < 0.5
            && candidate.voltageMV == active.voltageMV
    }

    private static func inferPortKind(from adapter: RawAdapterEntry?) -> PowerPortKind {
        let combined = [adapter?.description, adapter?.name, adapter?.model]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if combined.contains("magsafe") {
            return .magSafe
        }
        if combined.contains("usb") || combined.contains("pd") {
            return .usbC
        }
        return .unknown
    }

    private static func defaultPortLabel(for kind: PowerPortKind, number: Int?) -> String {
        switch kind {
        case .magSafe:
            return "MagSafe 3"
        case .usbC:
            if let number {
                return "USB-C \(number)"
            }
            return "USB-C"
        case .unknown:
            if let number {
                return "Port \(number)"
            }
            return "Power Adapter"
        }
    }
}
