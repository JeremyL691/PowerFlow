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
        let accent = modeTint

        GeometryReader { geometry in
            let layout = FlowLayout(graph: graph, width: geometry.size.width)
            ZStack(alignment: .topLeading) {
                MicroDotMatrix(
                    colorScheme: colorScheme,
                    contrast: colorSchemeContrast
                )

                FlowLinksView(
                    links: linkStyles(graph: graph, layout: layout),
                    isAnimating: isAnimating,
                    reduceMotion: reduceMotion,
                    isDark: colorScheme == .dark,
                    differentiateWithoutColor: differentiateWithoutColor
                )

                ForEach([graph.mac] + graph.sources + graph.outputs) { node in
                    if let frame = layout.frames[node.id] {
                        FlowNodeView(
                            node: node,
                            icon: icon(for: node),
                            tint: tint(for: node),
                            hubAccent: accent
                        )
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
        .powerFlowSurface(.heroStage(accent: accent), cornerRadius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(graph))
    }

    // MARK: - Mode Accent

    private var modeTint: Color? {
        switch snapshot.flowMode {
        case .adapterCharging:
            return PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        case .adapterBypass, .connectingAC:
            return PowerFlowTheme.acGold(for: colorScheme, contrast: colorSchemeContrast)
        case .adapterBatteryHybrid:
            return PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        case .batteryOnly, .batteryWhilePluggedIn:
            return snapshot.isLowBatteryWarning
                ? PowerFlowTheme.warningRed(for: colorScheme, contrast: colorSchemeContrast)
                : PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        case .unknown:
            return nil
        }
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

    /// Dual-ring energy port terminals where conduits meet their nodes; shared points share one terminal.
    private func handles(graph: FlowGraph, layout: FlowLayout) -> some View {
        var seen = Set<CGPoint>()
        var handles: [Handle] = []
        for link in graph.links.sorted(by: { $0.isActive && !$1.isActive }) {
            guard let route = layout.routes[link.id] else { continue }
            for (end, point) in [("start", route.start), ("end", route.end)] where seen.insert(point).inserted {
                handles.append(
                    Handle(
                        id: "\(link.id)-\(end)",
                        point: point,
                        color: tint(for: link),
                        isActive: link.isActive
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
        let isActive: Bool
    }

    private struct PortTerminalView: View {
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.colorSchemeContrast) private var colorSchemeContrast

        let handle: Handle

        var body: some View {
            if handle.isActive {
                ZStack {
                    Circle()
                        .fill(handle.color.opacity(colorScheme == .dark ? 0.30 : 0.22))
                        .frame(width: 7.5, height: 7.5)
                    Circle()
                        .strokeBorder(
                            handle.color.opacity(colorScheme == .dark ? 0.55 : 0.45),
                            lineWidth: 0.6
                        )
                        .frame(width: 7.5, height: 7.5)
                    Circle()
                        .fill(handle.color)
                        .frame(width: 3.5, height: 3.5)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(colorScheme == .dark ? 0.45 : 0.25))
                                .frame(width: 1.5, height: 1.5)
                        )
                }
            } else {
                Circle()
                    .fill(PowerFlowTheme.nodeFill(for: colorScheme, contrast: colorSchemeContrast))
                    .frame(width: 4.5, height: 4.5)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                handle.color.opacity(colorScheme == .dark ? 0.65 : 0.55),
                                lineWidth: 1.0
                            )
                    )
            }
        }
    }

    private func tint(for link: FlowGraph.Link) -> Color {
        guard link.isActive else {
            return PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
        }
        switch link.kind {
        case .adapter:
            return PowerFlowTheme.acGold(for: colorScheme, contrast: colorSchemeContrast)
        case .discharge:
            return PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        case .charge:
            return PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
        case .outbound:
            return PowerFlowTheme.outboundCyan(for: colorScheme, contrast: colorSchemeContrast)
        }
    }

    // MARK: - Nodes

    private func tint(for node: FlowGraph.Node) -> Color {
        guard node.isActive else {
            return PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
        }
        switch node.kind {
        case .adapter:
            return PowerFlowTheme.acGold(for: colorScheme, contrast: colorSchemeContrast)
        case .battery:
            return snapshot.isBatteryCharging
                ? PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
                : PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        case .mac:
            return PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast)
        case .device:
            return PowerFlowTheme.outboundCyan(for: colorScheme, contrast: colorSchemeContrast)
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

    private var cornerRadius: CGFloat {
        node.kind == .mac ? 13 : 11
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                shape
                    .fill(PowerFlowTheme.nodeFill(for: colorScheme, contrast: colorSchemeContrast))

                if node.isActive && node.kind != .mac {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(colorScheme == .dark ? 0.095 : 0.065),
                                tint.opacity(colorScheme == .dark ? 0.020 : 0.012)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .overlay {
                if colorScheme == .light {
                    shape.strokeBorder(
                        PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                        lineWidth: colorSchemeContrast == .increased ? 1.0 : 0.6
                    )
                }

                shape.strokeBorder(
                    PowerFlowTheme.specularRimGradient(for: colorScheme, contrast: colorSchemeContrast),
                    lineWidth: 0.75
                )

                if node.isActive && node.kind != .mac {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                tint.opacity(borderTopOpacity),
                                tint.opacity(borderBottomOpacity)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: colorSchemeContrast == .increased ? 1.05 : 0.75
                    )
                } else if !node.isActive && differentiateWithoutColor {
                    shape.strokeBorder(
                        PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                            .opacity(0.45),
                        style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])
                    )
                } else if colorScheme == .dark && colorSchemeContrast == .increased {
                    shape.strokeBorder(
                        PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                        lineWidth: 1.0
                    )
                }
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.075),
                radius: colorScheme == .dark ? 5.5 : 4.5,
                x: 0,
                y: colorScheme == .dark ? 2.5 : 1.75
            )
    }

    private var borderTopOpacity: Double {
        if colorSchemeContrast == .increased {
            return colorScheme == .dark ? 0.62 : 0.56
        }
        return colorScheme == .dark ? 0.40 : 0.34
    }

    private var borderBottomOpacity: Double {
        if colorSchemeContrast == .increased {
            return colorScheme == .dark ? 0.34 : 0.30
        }
        return colorScheme == .dark ? 0.14 : 0.12
    }

    @ViewBuilder
    private var content: some View {
        if node.kind == .mac {
            VStack(spacing: 4) {
                macMedallion
                Text(node.value)
                    .font(PowerFlowTheme.Typography.nodeHubValue)
                    .monospacedDigit()
                    .powerFlowNumericTransition()
                    .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
            }
            .padding(.horizontal, 6)
        } else {
            let isDevice = node.kind == .device
            let wellSize: CGFloat = isDevice ? 20 : 22
            let wellRadius: CGFloat = isDevice ? 6 : 6.5

            HStack(spacing: isDevice ? 5 : 5.5) {
                ZStack {
                    RoundedRectangle(cornerRadius: wellRadius, style: .continuous)
                        .fill(tint.opacity(node.isActive ? (colorScheme == .dark ? 0.16 : 0.12) : 0.08))
                    RoundedRectangle(cornerRadius: wellRadius, style: .continuous)
                        .strokeBorder(
                            tint.opacity(node.isActive ? (colorScheme == .dark ? 0.28 : 0.20) : 0.12),
                            lineWidth: 0.5
                        )
                    Image(systemName: icon)
                        .font(.system(size: isDevice ? 9.5 : 10.5, weight: .semibold))
                        .foregroundStyle(
                            node.isActive
                                ? tint
                                : PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                        )
                }
                .frame(width: wellSize, height: wellSize)

                VStack(alignment: .leading, spacing: 1) {
                    Text(node.title)
                        .font(PowerFlowTheme.Typography.captionFloor)
                        .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                    Text(node.value)
                        .font(PowerFlowTheme.Typography.nodeValue)
                        .monospacedDigit()
                        .powerFlowNumericTransition()
                        .foregroundStyle(
                            node.isActive
                                ? tint
                                : PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast)
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                        .allowsTightening(true)
                        .truncationMode(.tail)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6.5)
        }
    }

    private var macMedallion: some View {
        let ringTint = hubAccent ?? PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast)
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            ringTint.opacity(colorScheme == .dark ? 0.16 : 0.12),
                            colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.025)
                        ],
                        center: .top,
                        startRadius: 2,
                        endRadius: 16
                    )
                )
                .frame(width: 29, height: 29)

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            ringTint.opacity(colorScheme == .dark ? 0.36 : 0.28),
                            PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.7
                )
                .frame(width: 29, height: 29)

            Circle()
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07),
                    lineWidth: 0.5
                )
                .frame(width: 22.5, height: 22.5)

            Image(systemName: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
        }
    }
}

private struct MicroDotMatrix: View {
    let colorScheme: ColorScheme
    let contrast: ColorSchemeContrast

    var body: some View {
        let dotAlpha: Double = if contrast == .increased {
            colorScheme == .dark ? 0.16 : 0.14
        } else {
            colorScheme == .dark ? 0.11 : 0.095
        }
        let dotColor = colorScheme == .dark
            ? Color.white.opacity(dotAlpha)
            : Color.black.opacity(dotAlpha)

        Canvas { context, size in
            let spacing: CGFloat = 16
            var dots = Path()
            for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                    dots.addEllipse(in: CGRect(x: x - 0.5, y: y - 0.5, width: 1.0, height: 1.0))
                }
            }
            context.fill(dots, with: .color(dotColor))
        }
        .mask {
            EllipticalGradient(
                stops: [
                    .init(color: .white, location: 0.0),
                    .init(color: .white.opacity(0.82), location: 0.48),
                    .init(color: .clear, location: 1.0)
                ],
                center: .center,
                startRadiusFraction: 0.0,
                endRadiusFraction: 0.48
            )
        }
        .accessibilityHidden(true)
    }
}
