import SwiftUI

/// Live map of power: charger and battery flow into the Mac, the Mac flows on to USB-C devices.
struct PowerFlowDiagram: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let snapshot: PowerSnapshot
    let language: AppLanguage
    let isAnimating: Bool

    var body: some View {
        let graph = FlowGraph(snapshot: snapshot, language: language)

        GeometryReader { geometry in
            let layout = FlowLayout(graph: graph, width: geometry.size.width)
            ZStack(alignment: .topLeading) {
                DotGrid(color: PowerFlowTheme.hairlineDivider(for: colorScheme))

                FlowLinksView(
                    links: linkStyles(graph: graph, layout: layout),
                    isAnimating: isAnimating && !reduceMotion
                )

                ForEach([graph.mac] + graph.sources + graph.outputs) { node in
                    if let frame = layout.frames[node.id] {
                        FlowNodeView(node: node, icon: icon(for: node), tint: tint(for: node))
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .transition(.opacity)
                    }
                }

                handles(graph: graph, layout: layout)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: graph.structure)
        }
        .frame(height: FlowLayout.height(for: graph))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(PowerFlowTheme.nestedTileFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(PowerFlowTheme.hairlineDivider(for: colorScheme), lineWidth: 0.65)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(graph))
    }

    // MARK: - Links

    private func linkStyles(graph: FlowGraph, layout: FlowLayout) -> [FlowLinksView.LinkStyle] {
        graph.links.compactMap { link in
            layout.routes[link.id].map {
                FlowLinksView.LinkStyle(
                    id: link.id,
                    route: $0,
                    tint: NSColor(tint(for: link)),
                    watts: link.watts,
                    isActive: link.isActive
                )
            }
        }
    }

    /// Connection points where lines meet their nodes; lines that share a point share its handle.
    private func handles(graph: FlowGraph, layout: FlowLayout) -> some View {
        var seen = Set<CGPoint>()
        var handles: [Handle] = []
        for link in graph.links.sorted(by: { $0.isActive && !$1.isActive }) {
            guard let route = layout.routes[link.id] else { continue }
            for (end, point) in [("start", route.start), ("end", route.end)] where seen.insert(point).inserted {
                handles.append(Handle(id: "\(link.id)-\(end)", point: point, color: tint(for: link)))
            }
        }
        return ForEach(handles) { handle in
            Circle()
                .fill(handle.color)
                .frame(width: 6, height: 6)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.75))
                .position(handle.point)
        }
    }

    private struct Handle: Identifiable {
        let id: String
        let point: CGPoint
        let color: Color
    }

    private func tint(for link: FlowGraph.Link) -> Color {
        guard link.isActive else {
            return PowerFlowTheme.mutedLabel(for: colorScheme)
        }
        switch link.kind {
        case .adapter: return PowerFlowTheme.acGold(for: colorScheme)
        case .discharge: return PowerFlowTheme.dischargeAmber(for: colorScheme)
        case .charge: return PowerFlowTheme.chargeGreen(for: colorScheme)
        case .outbound: return PowerFlowTheme.outboundCyan(for: colorScheme)
        }
    }

    // MARK: - Nodes

    private func tint(for node: FlowGraph.Node) -> Color {
        guard node.isActive else {
            return PowerFlowTheme.mutedLabel(for: colorScheme)
        }
        switch node.kind {
        case .adapter:
            return PowerFlowTheme.acGold(for: colorScheme)
        case .battery:
            return snapshot.isBatteryCharging
                ? PowerFlowTheme.chargeGreen(for: colorScheme)
                : PowerFlowTheme.dischargeAmber(for: colorScheme)
        case .mac:
            return PowerFlowTheme.primaryValue(for: colorScheme)
        case .device:
            return PowerFlowTheme.outboundCyan(for: colorScheme)
        }
    }

    private func icon(for node: FlowGraph.Node) -> String {
        switch node.kind {
        case .adapter:
            return PowerFlowTheme.portSymbol(for: snapshot.activeAdapter?.portKind ?? .unknown)
        case .battery:
            return PowerFlowTheme.batterySymbol(
                percent: snapshot.batteryPercent,
                isCharging: snapshot.isBatteryCharging
            )
        case .mac:
            return "laptopcomputer"
        case .device:
            let isDisplay = snapshot.outboundPorts.first { $0.id == node.id }?.isDisplayPortActive == true
            return isDisplay ? "display" : "cable.connector"
        }
    }

    private func accessibilitySummary(_ graph: FlowGraph) -> String {
        let names = Dictionary(
            uniqueKeysWithValues: ([graph.mac] + graph.sources + graph.outputs).map { ($0.id, $0.title) }
        )
        let flows = graph.links.filter(\.isActive).map { link in
            "\(names[link.from] ?? "") → \(names[link.to] ?? "") \(PowerFormatters.watts(link.watts, decimals: 1))"
        }
        return ([L10n.label(for: snapshot.flowMode, language: language)] + flows).joined(separator: ", ")
    }
}

private struct FlowNodeView: View {
    @Environment(\.colorScheme) private var colorScheme

    let node: FlowGraph.Node
    let icon: String
    let tint: Color

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PowerFlowTheme.nodeFill(for: colorScheme))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(node.isActive && node.kind != .mac ? 0.10 : 0))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(node.isActive ? 0.55 : 0.28), lineWidth: 0.9)
            )
    }

    @ViewBuilder
    private var content: some View {
        if node.kind == .mac {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(PowerFlowTheme.secondaryValue(for: colorScheme))
                Text(node.value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
        } else {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 17)
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.title)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                    Text(node.value)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(node.isActive ? tint : PowerFlowTheme.secondaryValue(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
        }
    }
}

private struct DotGrid: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 14
            var dots = Path()
            for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                    dots.addEllipse(in: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2))
                }
            }
            context.fill(dots, with: .color(color))
        }
        .accessibilityHidden(true)
    }
}
