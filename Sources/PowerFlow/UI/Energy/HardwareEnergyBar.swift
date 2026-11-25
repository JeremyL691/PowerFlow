import SwiftUI

/// Whisper-quiet 4pt segmented hardware power bar with a crisp micro-legend.
struct HardwareEnergyBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let breakdown: HardwareEnergyBreakdown
    let language: AppLanguage

    private var visibleSegments: [HardwareEnergySegment] {
        breakdown.segments.filter { $0.watts.isFinite && $0.watts > 0 && $0.share.isFinite && $0.share > 0 }
    }

    var body: some View {
        if breakdown.isAvailable && !visibleSegments.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                segmentedBar
                legend
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        }
    }

    private var segmentedBar: some View {
        let segments = visibleSegments
        let shares = segments.map(\.share)
        let shape = Capsule(style: .continuous)

        return HardwareSegmentedBarLayout(shares: shares, spacing: 1.5) {
            ForEach(segments) { segment in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(segmentColor(for: segment.kind))
            }
        }
        .frame(height: 4)
        .background(
            shape.fill(PowerFlowTheme.gaugeTrack(for: colorScheme, contrast: colorSchemeContrast))
        )
        .clipShape(shape)
        .overlay {
            if colorSchemeContrast == .increased {
                shape.strokeBorder(
                    PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                    lineWidth: 0.75
                )
            }
        }
        .animation(reduceMotion ? nil : PowerFlowTheme.Motion.value, value: segments)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(visibleSegments) { segment in
                let formattedWatts = PowerFormatters.compactWatts(segment.watts)
                HStack(spacing: 4) {
                    Circle()
                        .fill(segmentColor(for: segment.kind))
                        .frame(width: 5, height: 5)
                    Text(L10n.label(for: segment.kind, language: language))
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                    Text(formattedWatts)
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .powerFlowNumericTransition(value: formattedWatts)
                        .foregroundStyle(PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
        }
    }

    private func segmentColor(for kind: HardwareEnergySegmentKind) -> Color {
        switch kind {
        case .soc:
            return PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast)
        case .display:
            return PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
                .opacity(colorSchemeContrast == .increased ? 1.0 : 0.85)
        case .outbound:
            return PowerFlowTheme.outboundTeal(for: colorScheme, contrast: colorSchemeContrast)
        case .other:
            return PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                .opacity(colorSchemeContrast == .increased ? 0.55 : 0.28)
        }
    }

    private var accessibilitySummary: String {
        let parts = visibleSegments.map { segment in
            let name = L10n.label(for: segment.kind, language: language)
            let watts = PowerFormatters.adaptiveWatts(segment.watts)
            let percent = Int((max(0, min(1, segment.share)) * 100.0).rounded())
            return "\(name) \(watts) (\(percent)%)"
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Proportional Bar Layout (Zero GeometryReader)

private struct HardwareSegmentedBarLayout: Layout {
    let shares: [Double]
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? proposal.replacingUnspecifiedDimensions().width
        return CGSize(width: max(0, width), height: 4)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty, bounds.width > 0 else { return }

        let count = subviews.count
        let weights: [Double] = (0..<count).map { index in
            guard index < shares.count else { return 0 }
            let value = shares[index]
            return (value.isFinite && value > 0) ? value : 0
        }
        let totalWeight = weights.reduce(0, +)
        let totalSpacing = spacing * CGFloat(max(0, count - 1))
        let available = max(0, bounds.width - totalSpacing)

        guard totalWeight > 0, available > 0 else {
            for subview in subviews {
                subview.place(
                    at: bounds.origin,
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: 0, height: bounds.height)
                )
            }
            return
        }

        let minSegmentWidth = min(3.0, available / CGFloat(count))
        var widths: [CGFloat] = weights.map { weight in
            guard weight > 0 else { return 0 }
            let proportional = available * CGFloat(weight / totalWeight)
            return max(proportional, minSegmentWidth)
        }

        let totalWidth = widths.reduce(0, +)
        if totalWidth > available, totalWidth > 0 {
            let scale = available / totalWidth
            widths = widths.map { $0 * scale }
        }

        var cursorX = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let segmentWidth = widths[index]
            subview.place(
                at: CGPoint(x: cursorX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: segmentWidth, height: bounds.height)
            )
            cursorX += segmentWidth + spacing
        }
    }
}
