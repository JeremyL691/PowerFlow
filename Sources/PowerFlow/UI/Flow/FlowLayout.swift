import CoreGraphics

/// Places the nodes of a `FlowGraph` and routes the links between them.
struct FlowLayout: Equatable {
    /// Cubic curve from one connection point to another.
    struct Route: Equatable {
        let start: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint

        /// S-curve between two columns.
        static func across(from start: CGPoint, to end: CGPoint) -> Route {
            let middle = (start.x + end.x) / 2
            return Route(
                start: start,
                control1: CGPoint(x: middle, y: start.y),
                control2: CGPoint(x: middle, y: end.y),
                end: end
            )
        }

        /// Straight line between two nodes of the same column.
        static func down(from start: CGPoint, to end: CGPoint) -> Route {
            Route(start: start, control1: start, control2: end, end: end)
        }
    }

    static let sourceSize = CGSize(width: 108, height: 46)
    static let deviceSize = CGSize(width: 100, height: 38)
    static let hubSize = CGSize(width: 86, height: 66)
    static let wideHubSize = CGSize(width: 116, height: 66)

    private static let inset: CGFloat = 10
    private static let sourceSpacing: CGFloat = 16
    /// Room for the visible flow from charger to battery.
    private static let chargingSpacing: CGFloat = 40
    private static let deviceSpacing: CGFloat = 8
    private static let attachmentSpacing: CGFloat = 18

    let frames: [String: CGRect]
    let routes: [String: Route]

    static func height(for graph: FlowGraph) -> CGFloat {
        let sources = stackHeight(
            count: graph.sources.count,
            item: sourceSize.height,
            spacing: spacing(for: graph)
        )
        let outputs = stackHeight(count: graph.outputs.count, item: deviceSize.height, spacing: deviceSpacing)
        return max(hubSize.height, sources, outputs) + inset * 2
    }

    init(graph: FlowGraph, width: CGFloat) {
        let midY = Self.height(for: graph) / 2
        var frames: [String: CGRect] = [:]

        Self.stack(
            graph.sources,
            size: Self.sourceSize,
            spacing: Self.spacing(for: graph),
            x: Self.inset,
            midY: midY,
            into: &frames
        )

        // The Mac sits between sources and devices, or at the far end when nothing draws from it.
        let hubSize = graph.outputs.isEmpty ? Self.wideHubSize : Self.hubSize
        let hubX: CGFloat
        if graph.outputs.isEmpty {
            hubX = graph.sources.isEmpty ? (width - hubSize.width) / 2 : width - Self.inset - hubSize.width
        } else {
            hubX = (width - hubSize.width) / 2
            Self.stack(
                graph.outputs,
                size: Self.deviceSize,
                spacing: Self.deviceSpacing,
                x: width - Self.inset - Self.deviceSize.width,
                midY: midY,
                into: &frames
            )
        }
        let hub = CGRect(x: hubX, y: midY - hubSize.height / 2, width: hubSize.width, height: hubSize.height)
        frames[FlowGraph.macID] = hub

        var routes: [String: Route] = [:]
        for link in graph.links {
            guard let from = frames[link.from], let to = frames[link.to] else { continue }
            if link.from != FlowGraph.macID && link.to != FlowGraph.macID {
                routes[link.id] = .down(
                    from: CGPoint(x: from.midX, y: from.maxY),
                    to: CGPoint(x: to.midX, y: to.minY)
                )
                continue
            }

            let peerID = link.from == FlowGraph.macID ? link.to : link.from
            let peer = link.from == FlowGraph.macID ? to : from
            let isSource = peer.midX < hub.midX
            // Spread the connection points of one side evenly around the hub's middle.
            let siblings = Self.hubPeers(of: graph, onSourceSide: isSource)
            let index = siblings.firstIndex(of: peerID) ?? 0
            let offset = (CGFloat(index) - CGFloat(siblings.count - 1) / 2) * Self.attachmentSpacing
            let hubPoint = CGPoint(x: isSource ? hub.minX : hub.maxX, y: hub.midY + offset)
            let peerPoint = CGPoint(x: isSource ? peer.maxX : peer.minX, y: peer.midY)
            routes[link.id] = link.from == FlowGraph.macID
                ? .across(from: hubPoint, to: peerPoint)
                : .across(from: peerPoint, to: hubPoint)
        }

        self.frames = frames
        self.routes = routes
    }

    private static func spacing(for graph: FlowGraph) -> CGFloat {
        graph.links.contains { $0.kind == .charge } ? chargingSpacing : sourceSpacing
    }

    private static func hubPeers(of graph: FlowGraph, onSourceSide: Bool) -> [String] {
        let linked = Set(
            graph.links
                .filter { $0.from == FlowGraph.macID || $0.to == FlowGraph.macID }
                .flatMap { [$0.from, $0.to] }
        )
        return (onSourceSide ? graph.sources : graph.outputs).map(\.id).filter(linked.contains)
    }

    private static func stackHeight(count: Int, item: CGFloat, spacing: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * item + CGFloat(count - 1) * spacing
    }

    private static func stack(
        _ nodes: [FlowGraph.Node],
        size: CGSize,
        spacing: CGFloat,
        x: CGFloat,
        midY: CGFloat,
        into frames: inout [String: CGRect]
    ) {
        var y = midY - stackHeight(count: nodes.count, item: size.height, spacing: spacing) / 2
        for node in nodes {
            frames[node.id] = CGRect(origin: CGPoint(x: x, y: y), size: size)
            y += size.height + spacing
        }
    }
}
