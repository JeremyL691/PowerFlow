import AppKit
import SwiftUI

/// Leaf observer wrapper reading `monitor.energySnapshot` so top popover sections
/// do not re-render on process-energy-only updates.
struct EnergyDashboardSection: View {
    let monitor: PowerMonitor
    let powerSnapshot: PowerSnapshot
    @Binding var groupingMode: EnergyGroupingMode
    let limit: EnergyDashboardItemLimit
    let language: AppLanguage

    var body: some View {
        EnergyDashboardView(
            powerSnapshot: powerSnapshot,
            energySnapshot: monitor.energySnapshot,
            groupingMode: $groupingMode,
            limit: limit,
            language: language
        )
    }
}

/// Minimalist hardware power distribution + single-line ranked consumers with flat inline detail.
struct EnergyDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let powerSnapshot: PowerSnapshot
    let energySnapshot: EnergySnapshot
    @Binding var groupingMode: EnergyGroupingMode
    let limit: EnergyDashboardItemLimit
    let language: AppLanguage

    @State private var expandedItemID: String?

    private var hardwareBreakdown: HardwareEnergyBreakdown {
        HardwareEnergyBreakdown.from(snapshot: powerSnapshot)
    }

    private var consumers: [EnergyConsumerItem] {
        energySnapshot.consumers(for: groupingMode, limit: limit.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if hardwareBreakdown.isAvailable && !hardwareBreakdown.segments.isEmpty {
                HardwareEnergyBar(breakdown: hardwareBreakdown, language: language)
            }

            consumerBody
        }
        .onChange(of: groupingMode) { _, _ in
            expandedItemID = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 6) {
            HStack(spacing: 4.5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast))
                    .accessibilityHidden(true)

                Text(L10n.string(.energyDashboard, language: language))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
            }
            .help(L10n.string(.energyScopeFootnote, language: language))

            Spacer(minLength: 6)

            EnergyGroupingToggle(selection: $groupingMode, language: language)

            ActivityMonitorIconButton(language: language)
        }
    }

    // MARK: - Body States

    @ViewBuilder
    private var consumerBody: some View {
        switch energySnapshot.phase {
        case .idle, .warmingUp:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.mini)
                Text(L10n.string(.energySampling, language: language))
                    .font(PowerFlowTheme.Typography.captionFloor)
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 10)

        case .unavailable:
            emptyConsumersState

        case .ready:
            let items = consumers
            if items.isEmpty {
                emptyConsumersState
            } else {
                let maxPower = items.map(\.powerW).max() ?? 0
                let useImpactFallback = maxPower < 0.001
                let denominator = useImpactFallback
                    ? max(items.map(\.energyImpact).max() ?? 0, 0.001)
                    : maxPower

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        let numerator = useImpactFallback ? item.energyImpact : item.powerW
                        let relativeShare = (numerator.isFinite && denominator > 0)
                            ? min(1.0, max(0.0, numerator / denominator))
                            : 0

                        EnergyConsumerRow(
                            item: item,
                            groupingMode: groupingMode,
                            relativeShare: relativeShare,
                            isExpanded: expandedItemID == item.id,
                            language: language,
                            onToggle: { toggleExpansion(for: item.id) }
                        )
                    }
                }
            }
        }
    }

    private var emptyConsumersState: some View {
        HStack(spacing: 5) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast))
                .accessibilityHidden(true)

            Text(L10n.string(.energyNoActiveConsumers, language: language))
                .font(PowerFlowTheme.Typography.captionFloor)
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
    }

    private func toggleExpansion(for id: String) {
        let next: String? = (expandedItemID == id) ? nil : id
        if reduceMotion {
            expandedItemID = next
        } else {
            withAnimation(PowerFlowTheme.Motion.tab) {
                expandedItemID = next
            }
        }
    }
}

// MARK: - Quiet Header Controls

private struct EnergyGroupingToggle: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selection: EnergyGroupingMode
    let language: AppLanguage

    @Namespace private var namespace
    @State private var hoveredMode: EnergyGroupingMode?

    var body: some View {
        modeButtons
            .padding(2)
            .background(
                Capsule(style: .continuous)
                    .fill(PowerFlowTheme.nestedTileFill(for: colorScheme, contrast: colorSchemeContrast))
            )
            .overlay {
                if colorSchemeContrast == .increased {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                            lineWidth: 0.7
                        )
                }
            }
            .animation(reduceMotion ? nil : PowerFlowTheme.Motion.tab, value: selection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.string(.energyDashboard, language: language))
    }

    @ViewBuilder
    private var modeButtons: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                buttonRow(usesGlassSelection: true)
            }
        } else {
            buttonRow(usesGlassSelection: false)
        }
    }

    private func buttonRow(usesGlassSelection: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(EnergyGroupingMode.allCases) { mode in
                modeButton(mode, usesGlassSelection: usesGlassSelection)
            }
        }
    }

    private func modeButton(_ mode: EnergyGroupingMode, usesGlassSelection: Bool) -> some View {
        let isSelected = selection == mode
        let isHovered = hoveredMode == mode
        let labelColor = isSelected || isHovered
            ? PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast)
            : PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)

        return Button {
            selection = mode
        } label: {
            Text(L10n.label(for: mode, language: language))
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .padding(.horizontal, 7.5)
                .frame(height: 19)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if !usesGlassSelection, isSelected {
                Capsule(style: .continuous)
                    .fill(
                        PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast)
                            .opacity(colorScheme == .dark ? 0.22 : 0.14)
                    )
                    .matchedGeometryEffect(id: "energyModeSelection", in: namespace)
            }
        }
        .modifier(EnergyGlassSelectionModifier(isSelected: isSelected, namespace: namespace, enabled: usesGlassSelection))
        .contentShape(Capsule())
        .onHover { hovering in
            let next: EnergyGroupingMode? = hovering ? mode : (hoveredMode == mode ? nil : hoveredMode)
            if reduceMotion {
                hoveredMode = next
            } else {
                withAnimation(PowerFlowTheme.Motion.hover) {
                    hoveredMode = next
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct EnergyGlassSelectionModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let isSelected: Bool
    let namespace: Namespace.ID
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if enabled && isSelected {
                content
                    .glassEffect(
                        .regular
                            .tint(PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast).opacity(0.14))
                            .interactive(),
                        in: Capsule()
                    )
                    .glassEffectID("energyModeSelection", in: namespace)
            } else {
                content
            }
        } else {
            content
        }
    }
}

private struct ActivityMonitorIconButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let language: AppLanguage

    @State private var isHovered = false

    var body: some View {
        let shape = Circle()

        Button(action: openActivityMonitor) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(
                    isHovered
                        ? PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast)
                        : PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                )
                .frame(width: 22, height: 22)
                .background(
                    shape.fill(
                        isHovered
                            ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.055))
                            : .clear
                    )
                )
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(PowerFlowTheme.Motion.hover) {
                    isHovered = hovering
                }
            }
        }
        .help(L10n.string(.openActivityMonitor, language: language))
        .accessibilityLabel(L10n.string(.openActivityMonitor, language: language))
    }

    private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }
}

// MARK: - Single-Line Consumer Row & Flat Editorial Detail

private struct EnergyConsumerRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let item: EnergyConsumerItem
    let groupingMode: EnergyGroupingMode
    let relativeShare: Double
    let isExpanded: Bool
    let language: AppLanguage
    let onToggle: () -> Void

    @State private var isHovered = false

    private var formattedPower: String {
        PowerFormatters.adaptiveWatts(item.powerW)
    }

    private var formattedCPU: String? {
        guard item.cpuPercent.isFinite, item.cpuPercent >= 0.1 else { return nil }
        return PowerFormatters.cpuPercent(item.cpuPercent)
    }

    private var formattedPCoreShare: String {
        guard let share = item.pCoreShare, share.isFinite else { return "—" }
        let clamped = min(1.0, max(0.0, share)) * 100.0
        return PowerFormatters.precisePercent(clamped, decimals: 0)
    }

    private var barTint: Color {
        let base = PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast)
        let darkAlpha: Double = isExpanded ? 0.16 : (isHovered ? 0.14 : 0.095)
        let lightAlpha: Double = isExpanded ? 0.12 : (isHovered ? 0.10 : 0.065)
        return base.opacity(colorScheme == .dark ? darkAlpha : lightAlpha)
    }

    private var hoverFill: Color {
        if isExpanded {
            return colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.038)
        }
        if isHovered {
            return colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.028)
        }
        return .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowButton

            if isExpanded {
                inlineDetails
                    .transition(.opacity)
            }
        }
    }

    private var rowButton: some View {
        let rowShape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        return Button(action: onToggle) {
            HStack(alignment: .center, spacing: 8) {
                appIcon

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(item.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if groupingMode == .byApp && item.processCount > 1 {
                        Text("· \(item.processCount)")
                            .font(.system(size: 10.5, weight: .regular))
                            .monospacedDigit()
                            .foregroundStyle(
                                PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                                    .opacity(colorSchemeContrast == .increased ? 1.0 : 0.72)
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if item.isPreventingSleep {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast))
                            .help(L10n.sleepAssertionDescription(item.sleepAssertionTypes, language: language))
                            .accessibilityHidden(true)
                    }
                }

                Spacer(minLength: 6)

                if let formattedCPU {
                    Text(formattedCPU)
                        .font(.system(size: 11, weight: .regular))
                        .monospacedDigit()
                        .powerFlowNumericTransition(value: formattedCPU)
                        .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Text(formattedPower)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .powerFlowNumericTransition(value: formattedPower)
                    .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
                    .frame(minWidth: 48, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(
                        PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                            .opacity(isHovered || isExpanded ? 0.9 : 0.45)
                    )
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(reduceMotion ? nil : PowerFlowTheme.Motion.tab, value: isExpanded)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 7)
            .frame(height: 30)
            .background {
                ZStack(alignment: .leading) {
                    rowShape.fill(hoverFill)
                    ProportionalRowFillLayout(fraction: relativeShare) {
                        rowShape.fill(barTint)
                    }
                    .animation(reduceMotion ? nil : PowerFlowTheme.Motion.value, value: relativeShare)
                }
                .clipShape(rowShape)
            }
            .contentShape(rowShape)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(PowerFlowTheme.Motion.hover) {
                    isHovered = hovering
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityValue(rowAccessibilityValue)
        .accessibilityHint(
            isExpanded
                ? L10n.tr("Collapse details", zh: "收起详情", language: language)
                : L10n.tr("Expand details", zh: "展开详情", language: language)
        )
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let image = AppIconCache.shared.icon(forPath: item.iconPath) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(PowerFlowTheme.nestedTileFill(for: colorScheme, contrast: colorSchemeContrast))
                Image(systemName: item.bundleIdentifier != nil ? "app.fill" : "terminal.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
            }
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
        }
    }

    /// Flat, borderless detail section indented beneath the app name (no card-in-card).
    private var inlineDetails: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule(style: .continuous)
                .fill(
                    PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast)
                        .opacity(colorScheme == .dark ? 0.36 : 0.28)
                )
                .frame(width: 1.5)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 8) {
                        CompactMetricCell(
                            label: L10n.string(.energyImpact, language: language),
                            value: PowerFormatters.energyImpact(item.energyImpact)
                        )
                        CompactMetricCell(
                            label: L10n.string(.energyCPU, language: language),
                            value: PowerFormatters.cpuPercent(item.cpuPercent)
                        )
                        CompactMetricCell(
                            label: L10n.string(.energyPCoreShare, language: language),
                            value: formattedPCoreShare
                        )
                    }

                    HStack(alignment: .top, spacing: 8) {
                        CompactMetricCell(
                            label: L10n.string(.energyWakeups, language: language),
                            value: PowerFormatters.wakeupsPerSecond(item.wakeupsPerSecond)
                        )
                        CompactMetricCell(
                            label: L10n.string(.energyDiskIO, language: language),
                            value: PowerFormatters.byteRate(item.diskBytesPerSecond)
                        )
                        CompactMetricCell(
                            label: L10n.string(.energyMemory, language: language),
                            value: PowerFormatters.memoryBytes(item.memoryBytes)
                        )
                    }
                }

                if item.isPreventingSleep {
                    sleepAssertionLine
                }

                if groupingMode == .byApp && item.processes.count > 1 {
                    subprocessList
                }
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 7)
        .padding(.top, 5)
        .padding(.bottom, 8)
    }

    private var sleepAssertionLine: some View {
        let amber = PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
        let title = L10n.string(.energyPreventingSleep, language: language)
        let description = L10n.sleepAssertionDescription(item.sleepAssertionTypes, language: language)
        let text = (!description.isEmpty && description != title) ? "\(title) · \(description)" : title

        return HStack(spacing: 5) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(amber)
        .accessibilityElement(children: .combine)
    }

    private var subprocessList: some View {
        let topChildren = Array(item.processes.prefix(3))
        let remaining = max(0, item.processes.count - topChildren.count)

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(L10n.string(.energyProcessesSection, language: language))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))

                if remaining > 0 {
                    Text(L10n.tr("· +\(remaining) more", zh: "· 另有 \(remaining) 个", language: language))
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(
                            PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                                .opacity(colorSchemeContrast == .increased ? 1.0 : 0.72)
                        )
                }
            }

            ForEach(topChildren) { child in
                HStack(spacing: 6) {
                    Text(child.name)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    Text(PowerFormatters.cpuPercent(child.cpuPercent))
                        .font(.system(size: 10.5, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text(PowerFormatters.adaptiveWatts(child.powerW))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                        .frame(minWidth: 46, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var rowAccessibilityLabel: String {
        var parts = [item.displayName]
        if groupingMode == .byApp && item.processCount > 1 {
            parts.append(L10n.tr("\(item.processCount) processes", zh: "\(item.processCount) 个进程", language: language))
        }
        if item.isPreventingSleep {
            parts.append(L10n.string(.energyPreventingSleep, language: language))
        }
        return parts.joined(separator: ", ")
    }

    private var rowAccessibilityValue: String {
        let cpu = PowerFormatters.cpuPercent(item.cpuPercent)
        return "\(formattedPower), CPU \(cpu)"
    }
}

private struct CompactMetricCell: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text(label)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .powerFlowNumericTransition(value: value)
                .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Subtle Proportional Row Fill Layout (Zero GeometryReader)

private struct ProportionalRowFillLayout: Layout {
    let fraction: Double

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let clamped = fraction.isFinite ? min(1.0, max(0.0, fraction)) : 0
        let fillWidth: CGFloat = (clamped <= 0 || bounds.width <= 0)
            ? 0
            : min(bounds.width, max(6.0, bounds.width * CGFloat(clamped)))
        subview.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: fillWidth, height: bounds.height)
        )
    }
}
