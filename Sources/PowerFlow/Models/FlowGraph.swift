import Foundation

/// Where power comes from and where it goes right now: sources on the left, the Mac in the
/// middle, USB-C devices on the right.
struct FlowGraph: Equatable {
    enum NodeKind: Equatable {
        case adapter
        case battery
        case mac
        case device
    }

    struct Node: Identifiable, Equatable {
        let id: String
        let kind: NodeKind
        let title: String
        let value: String
        let isActive: Bool
    }

    enum LinkKind: Equatable {
        case adapter
        case discharge
        /// Charger straight to battery.
        case charge
        case outbound
    }

    /// Energy runs from `from` to `to`. An inactive link is connected but carries nothing.
    struct Link: Identifiable, Equatable {
        let id: String
        let from: String
        let to: String
        let kind: LinkKind
        let watts: Double
        let isActive: Bool
    }

    static let adapterID = "adapter"
    static let batteryID = "battery"
    static let macID = "mac"
    static let maxOutputNodes = 3

    let sources: [Node]
    let mac: Node
    let outputs: [Node]
    let links: [Link]

    /// Changes only when nodes or connections appear, vanish or reverse.
    var structure: [String] {
        (sources + outputs).map(\.id) + links.map { "\($0.from)>\($0.to)" }
    }
}

extension FlowGraph {
    private static let minimumWatts = 0.05
    /// Drives the animation while the charger is still negotiating and reports no power.
    private static let negotiatingWatts = 8.0

    init(snapshot: PowerSnapshot, language: AppLanguage) {
        guard snapshot.isDataAvailable else {
            self.init(
                sources: [],
                mac: Node(id: Self.macID, kind: .mac, title: "Mac", value: "—", isActive: false),
                outputs: [],
                links: []
            )
            return
        }

        var sources: [Node] = []
        var links: [Link] = []

        let batteryWatts = abs(snapshot.batteryPowerW)
        let isCharging = snapshot.isBatteryCharging && snapshot.isEffectivelyOnAC
        let isDischarging = !isCharging && snapshot.isBatteryDischarging

        if snapshot.isEffectivelyOnAC {
            let isConnecting = snapshot.flowMode == .connectingAC
                && snapshot.adapterInputPowerW < Self.minimumWatts
            let isSupplying = isConnecting
                || (snapshot.isAdapterSupplyingPower && snapshot.adapterInputPowerW >= Self.minimumWatts)
            sources.append(
                Node(
                    id: Self.adapterID,
                    kind: .adapter,
                    title: snapshot.activeAdapter?.portLabel ?? L10n.string(.powerAdapter, language: language),
                    value: Self.adapterValue(
                        snapshot,
                        isConnecting: isConnecting,
                        isSupplying: isSupplying,
                        language: language
                    ),
                    isActive: isSupplying
                )
            )
            // The charger feeds the Mac and, while charging, the battery; each branch carries its share.
            let toMac = isConnecting
                ? Self.negotiatingWatts
                : max(0, snapshot.adapterInputPowerW - (isCharging ? batteryWatts : 0))
            links.append(
                Link(
                    id: Self.adapterID,
                    from: Self.adapterID,
                    to: Self.macID,
                    kind: .adapter,
                    watts: toMac,
                    isActive: isSupplying && toMac >= Self.minimumWatts
                )
            )
        }

        sources.append(
            Node(
                id: Self.batteryID,
                kind: .battery,
                title: "\(L10n.string(.battery, language: language)) \(PowerFormatters.percent(snapshot.batteryPercent))",
                value: Self.batteryValue(
                    watts: batteryWatts,
                    isCharging: isCharging,
                    isDischarging: isDischarging,
                    language: language
                ),
                isActive: isCharging || isDischarging
            )
        )
        links.append(
            Link(
                id: Self.batteryID,
                from: isCharging ? Self.adapterID : Self.batteryID,
                to: isCharging ? Self.batteryID : Self.macID,
                kind: isCharging ? .charge : .discharge,
                watts: batteryWatts,
                isActive: isCharging || isDischarging
            )
        )

        let outputs = Self.outputNodes(for: snapshot, language: language)
        links += outputs.map { output in
            Link(
                id: output.node.id,
                from: Self.macID,
                to: output.node.id,
                kind: .outbound,
                watts: output.watts,
                isActive: true
            )
        }

        let macWatts = outputs.isEmpty ? snapshot.totalSystemLoadW : snapshot.netSystemLoadW
        self.init(
            sources: sources,
            mac: Node(
                id: Self.macID,
                kind: .mac,
                title: "Mac",
                value: PowerFormatters.watts(macWatts, decimals: 1),
                isActive: macWatts >= Self.minimumWatts
            ),
            outputs: outputs.map(\.node),
            links: links
        )
    }

    private static func adapterValue(
        _ snapshot: PowerSnapshot,
        isConnecting: Bool,
        isSupplying: Bool,
        language: AppLanguage
    ) -> String {
        if isConnecting {
            return L10n.string(.flowConnectingAC, language: language)
        }
        return isSupplying
            ? PowerFormatters.watts(snapshot.adapterInputPowerW, decimals: 1)
            : L10n.string(.standby, language: language)
    }

    private static func batteryValue(
        watts: Double,
        isCharging: Bool,
        isDischarging: Bool,
        language: AppLanguage
    ) -> String {
        if isCharging {
            return PowerFormatters.watts(watts, decimals: 1, signed: true)
        }
        if isDischarging {
            return PowerFormatters.watts(-watts, decimals: 1, signed: true)
        }
        return L10n.tr("Idle", zh: "待机", language: language)
    }

    /// One node per powered device; devices beyond the limit share the last node.
    private static func outputNodes(
        for snapshot: PowerSnapshot,
        language: AppLanguage
    ) -> [(node: Node, watts: Double)] {
        let ports = snapshot.outboundPorts
        let individual = ports.count > maxOutputNodes ? Array(ports.prefix(maxOutputNodes - 1)) : ports
        var result = individual.map { port in
            (
                node: Node(
                    id: port.id,
                    kind: .device,
                    title: L10n.deviceName(for: port, language: language),
                    value: PowerFormatters.watts(port.powerW, decimals: 1),
                    isActive: true
                ),
                watts: port.powerW
            )
        }
        let rest = ports.dropFirst(individual.count)
        if !rest.isEmpty {
            let watts = rest.reduce(0) { $0 + $1.powerW }
            result.append(
                (
                    node: Node(
                        id: "usb-c-out-rest",
                        kind: .device,
                        title: L10n.tr("\(rest.count) more", zh: "其他 \(rest.count) 个", language: language),
                        value: PowerFormatters.watts(watts, decimals: 1),
                        isActive: true
                    ),
                    watts: watts
                )
            )
        }
        return result
    }
}
