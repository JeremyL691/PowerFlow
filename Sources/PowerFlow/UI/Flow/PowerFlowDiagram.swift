import SwiftUI

/// Live map of power: charger and battery flow into the Mac, the Mac flows on to USB-C devices.
struct PowerFlowDiagram: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let snapshot: PowerSnapshot
    let language: AppLanguage
    let isAnimating: Bool

    var body: some View {
        let graph = FlowGraph(snapshot: snapshot, language: language)

        GeometryReader { geometry in
            let layout = FlowLayout(graph: graph, width: geometry.size.width)
            ZStack(alignment: .topLeading) {
                if let hubFrame = layout.frames[graph.mac.id], let tint = modeTint {
                    hubGlow(tint: tint, center: CGPoint(x: hubFrame.midX, y: hubFrame.midY))
                }

                FlowLinksView(
                    links: linkStyles(graph: graph, layout: layout),
                    isAnimating: isAnimating,
                    reduceMotion: reduceMotion,
                    isDark: colorScheme == .dark,
                    differentiateWithoutColor: differentiateWithoutColor,
                    hub: layout.frames[graph.mac.id],
                    hubTint: modeTint.map(NSColor.init),
                    hubWatts: snapshot.totalSystemLoadW
                )

                ForEach([graph.mac] + graph.sources + graph.outputs) { node in
                    if let frame = layout.frames[node.id] {
                        FlowNodeView(
                            node: node,
                            icon: icon(for: node),
                            tint: tint(for: node),
                            hubAccent: modeTint
                        )
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                    }
                }

                handles(graph: graph, layout: layout)
            }
        }
        .frame(height: FlowLayout.height(for: graph))
        .animation(reduceMotion ? nil : PowerFlowTheme.Motion.tab, value: graph.structure)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(graph))
    }

    private func hubGlow(tint: Color, center: CGPoint) -> some View {
        RadialGradient(
            colors: [
                tint.opacity(colorScheme == .dark ? 0.16 : 0.10),
                .clear
            ],
            center: .center,
            startRadius: 4,
            endRadius: 120
        )
        .frame(width: 240, height: 240)
        .position(center)
        .allowsHitTesting(false)
    }

    // MARK: - Mode Accent

    private var modeTint: Color? {
        guard snapshot.flowMode != .unknown else { return nil }
        if snapshot.isLowBatteryWarning {
            return PowerFlowTheme.warningRed(for: colorScheme, contrast: colorSchemeContrast)
        }
        return PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast)
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

    /// Energy port terminals where active conduits meet their nodes; shared points share one terminal.
    private func handles(graph: FlowGraph, layout: FlowLayout) -> some View {
        var seen = Set<CGPoint>()
        var handles: [Handle] = []
        for link in graph.links where link.isActive {
            guard let route = layout.routes[link.id] else { continue }
            for (end, point) in [("start", route.start), ("end", route.end)] where seen.insert(point).inserted {
                handles.append(
                    Handle(
                        id: "\(link.id)-\(end)",
                        point: point,
                        color: tint(for: link)
                    )
                )
            }
        }
        return ForEach(handles) { handle in
            PortTerminalView(handle: handle)
                .position(handle.point)
        }
    }

    private struct Handle: Identifiable {
        let id: String
        let point: CGPoint
        let color: Color
    }

    private struct PortTerminalView: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.colorSchemeContrast) private var colorSchemeContrast

        let handle: Handle

        var body: some View {
            Circle()
                .fill(handle.color)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .strokeBorder(
                            PowerFlowTheme.nodeFill(for: colorScheme, contrast: colorSchemeContrast),
                            lineWidth: 1.5
                        )
                )
        }
    }

    private func tint(for link: FlowGraph.Link) -> Color {
        guard link.isActive else {
            return PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
        }
        switch link.kind {
        case .adapter:
            return PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast)
        case .discharge:
            return PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        case .charge:
            return PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        case .outbound:
            return PowerFlowTheme.outboundTeal(for: colorScheme, contrast: colorSchemeContrast)
        }
    }

    // MARK: - Nodes

    private func tint(for node: FlowGraph.Node) -> Color {
        guard node.isActive else {
            return PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
        }
        switch node.kind {
        case .adapter:
            return PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast)
        case .battery:
            return snapshot.isBatteryCharging
                ? PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
                : PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        case .mac:
            return PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast)
        case .device:
            return PowerFlowTheme.outboundTeal(for: colorScheme, contrast: colorSchemeContrast)
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let node: FlowGraph.Node
    let icon: String
    let tint: Color
    let hubAccent: Color?

    var body: some View {
        if node.kind == .mac {
            hubBody
        } else {
            capsuleBody
        }
    }

    // MARK: - Capsule sources & devices

    private var capsuleBody: some View {
        let isDevice = node.kind == .device
        let discSize: CGFloat = isDevice ? 24 : 26

        return HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.12))
                Image(systemName: icon)
                    .font(.system(size: isDevice ? 11 : 12, weight: .semibold))
                    .foregroundStyle(
                        node.isActive
                            ? tint
                            : PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                    )
            }
            .frame(width: discSize, height: discSize)

            VStack(alignment: .leading, spacing: 1) {
                Text(node.title)
                    .font(PowerFlowTheme.Typography.captionFloor)
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .truncationMode(.tail)
                Text(node.value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .powerFlowNumericTransition(value: node.value)
                    .foregroundStyle(
                        node.isActive
                            ? tint
                            : PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Capsule(style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.065)
                        : Color.white.opacity(0.85)
                )
        }
        .overlay { capsuleStroke }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0 : 0.06),
            radius: 6,
            x: 0,
            y: 2
        )
    }

    @ViewBuilder
    private var capsuleStroke: some View {
        let shape = Capsule(style: .continuous)
        if node.isActive {
            shape.strokeBorder(
                LinearGradient(
                    colors: [tint.opacity(0.30), tint.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
        } else if differentiateWithoutColor {
            shape.strokeBorder(
                PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast).opacity(0.45),
                style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])
            )
        } else if colorSchemeContrast == .increased {
            shape.strokeBorder(
                PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                lineWidth: 1.0
            )
        }
    }

    // MARK: - Circular Mac hub

    private var hubBody: some View {
        let rimTint = hubAccent ?? PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)

        return VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
            Text(node.value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .powerFlowNumericTransition(value: node.value)
                .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Circle()
                .fill(PowerFlowTheme.nodeFill(for: colorScheme, contrast: colorSchemeContrast))
        }
        .overlay {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                            rimTint,
                            PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast)
                        ],
                        center: .center,
                        startAngle: .degrees(90),
                        endAngle: .degrees(450)
                    ),
                    lineWidth: 1.25
                )
        }
    }
}
