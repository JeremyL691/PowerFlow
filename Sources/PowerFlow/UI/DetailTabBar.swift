import SwiftUI

enum PopoverDetailTab: String, CaseIterable, Identifiable {
    case battery
    case charger
    case output

    var id: String { rawValue }
}

/// Battery / Charger / Output picker: a capsule track whose selection indicator is a shape —
/// morphing Liquid Glass on macOS 26, a sliding capsule below.
struct DetailTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selection: PopoverDetailTab
    let isOnAC: Bool
    let ratedAdapterWatts: Double
    let outboundPortCount: Int
    let language: AppLanguage

    @Namespace private var namespace
    @State private var hoveredTab: PopoverDetailTab?

    private var chargerBadge: String? {
        guard isOnAC, ratedAdapterWatts.isFinite, ratedAdapterWatts > 0.5 else { return nil }
        return "\(Int(ratedAdapterWatts.rounded())) W"
    }

    private var outputBadge: String? {
        outboundPortCount == 0 ? nil : "\(outboundPortCount)"
    }

    private func badge(for tab: PopoverDetailTab) -> String? {
        switch tab {
        case .battery: return nil
        case .charger: return chargerBadge
        case .output: return outputBadge
        }
    }

    private func icon(for tab: PopoverDetailTab) -> String {
        switch tab {
        case .battery: return "battery.100percent"
        case .charger: return "powerplug.fill"
        case .output: return "arrow.up.right.circle.fill"
        }
    }

    private func title(for tab: PopoverDetailTab) -> String {
        switch tab {
        case .battery: return L10n.string(.battery, language: language)
        case .charger: return L10n.tr("Charger", zh: "充电器", language: language)
        case .output: return L10n.tr("Output", zh: "输出", language: language)
        }
    }

    var body: some View {
        tabs
            .padding(3)
            .background(
                Capsule(style: .continuous)
                    .fill(PowerFlowTheme.tileFill(for: colorScheme, contrast: colorSchemeContrast))
            )
            .animation(reduceMotion ? nil : PowerFlowTheme.Motion.tab, value: selection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.tr("Details", zh: "详情", language: language))
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                tabRow(usesGlassSelection: true)
            }
        } else {
            tabRow(usesGlassSelection: false)
        }
    }

    private func tabRow(usesGlassSelection: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(PopoverDetailTab.allCases) { tab in
                tabButton(tab, usesGlassSelection: usesGlassSelection)
            }
        }
    }

    private func tabButton(_ tab: PopoverDetailTab, usesGlassSelection: Bool) -> some View {
        let isSelected = selection == tab

        return DetailTabButton(
            isSelected: isSelected,
            isHovered: hoveredTab == tab,
            icon: icon(for: tab),
            title: title(for: tab),
            badge: badge(for: tab)
        ) {
            selection = tab
        }
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .background {
            if !usesGlassSelection, isSelected {
                Capsule(style: .continuous)
                    .fill(
                        PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast)
                            .opacity(colorScheme == .dark ? 0.22 : 0.16)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.1), radius: 2, x: 0, y: 1)
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
        .modifier(GlassSelectionModifier(isSelected: isSelected, namespace: namespace, enabled: usesGlassSelection))
        .contentShape(Capsule())
        .onHover { hovering in
            let next: PopoverDetailTab? = hovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
            if reduceMotion {
                hoveredTab = next
            } else {
                withAnimation(PowerFlowTheme.Motion.hover) {
                    hoveredTab = next
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct GlassSelectionModifier: ViewModifier {
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
                            .tint(PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast).opacity(0.16))
                            .interactive(),
                        in: Capsule()
                    )
                    .glassEffectID("selection", in: namespace)
            } else {
                content
            }
        } else {
            content
        }
    }
}

private struct DetailTabButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let isSelected: Bool
    let isHovered: Bool
    let icon: String
    let title: String
    let badge: String?
    let action: () -> Void

    var body: some View {
        let labelColor = isSelected || isHovered
            ? PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast)
            : PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)

        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(labelColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
