import AppKit
import SwiftUI

struct SettingsView: View {
    static let windowSize = CGSize(width: 480, height: 720)

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var settingsStore: PowerSettingsStore
    let monitor: PowerMonitor

    init(settingsStore: PowerSettingsStore, monitor: PowerMonitor) {
        self.settingsStore = settingsStore
        self.monitor = monitor
    }

    init(monitor: PowerMonitor) {
        self.init(settingsStore: monitor.settingsStore, monitor: monitor)
    }

    private var language: AppLanguage { settingsStore.settings.appLanguage }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let build, !build.isEmpty, build != short {
            return "\(short) (\(build))"
        }
        return short
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
            Divider()
            Form {
                menuBarSection
                generalSection
                privacySection
                aboutSection
            }
            .formStyle(.grouped)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .environment(\.locale, PowerFlowTheme.locale(for: language))
        .onAppear {
            settingsStore.refreshLaunchAtLoginStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settingsStore.refreshLaunchAtLoginStatus()
        }
    }

    // MARK: - Header

    private var settingsHeader: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                    .fill(PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast).opacity(colorScheme == .dark ? 0.16 : 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9.5, style: .continuous)
                            .strokeBorder(
                                PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast).opacity(colorScheme == .dark ? 0.36 : 0.30),
                                lineWidth: 0.75
                            )
                    )
                Image(systemName: "bolt.batteryblock.fill")
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(L10n.string(.appName, language: language))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))

                SettingsTelemetrySubtitle(monitor: monitor, appVersion: appVersion, language: language)
            }

            Spacer(minLength: 8)

            SettingsBatteryStatusChip(monitor: monitor, language: language)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(PowerFlowTheme.nestedTileFill(for: colorScheme, contrast: colorSchemeContrast))
    }

    // MARK: - Sections

    private var menuBarSection: some View {
        Section {
            Picker(
                L10n.string(.settingsDisplayMode, language: language),
                selection: $settingsStore.settings.menuBarDisplayMode
            ) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(L10n.label(for: mode, language: language))
                        .tag(mode)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.string(.settingsIconStyle, language: language))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))

                HStack(spacing: 10) {
                    ForEach(BatteryIconStyle.allCases) { style in
                        BatteryIconStylePreviewCard(
                            style: style,
                            title: L10n.label(for: style, language: language),
                            displayMode: settingsStore.settings.menuBarDisplayMode,
                            monitor: monitor,
                            isSelected: settingsStore.settings.batteryIconStyle == style
                        ) {
                            if reduceMotion {
                                settingsStore.settings.batteryIconStyle = style
                            } else {
                                withAnimation(.spring(duration: 0.24, bounce: 0.16)) {
                                    settingsStore.settings.batteryIconStyle = style
                                }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 1)

            HStack(alignment: .top, spacing: 6) {
                Image(
                    systemName: settingsStore.settings.menuBarDisplayMode.requiresPeriodicPolling
                        ? "clock.arrow.2.circlepath"
                        : "leaf.fill"
                )
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(
                    settingsStore.settings.menuBarDisplayMode.requiresPeriodicPolling
                        ? PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast)
                        : PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
                )
                .padding(.top, 1)

                Text(L10n.string(.settingsZeroPollingHint, language: language))
                    .font(PowerFlowTheme.Typography.captionFloor)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(L10n.string(.settingsMenuBar, language: language))
        }
    }

    private var generalSection: some View {
        Section {
            Picker(
                L10n.string(.settingsRefreshRate, language: language),
                selection: $settingsStore.settings.liveRefreshInterval
            ) {
                ForEach(LiveRefreshInterval.allCases) { interval in
                    Text(L10n.label(for: interval, language: language))
                        .tag(interval)
                }
            }

            Picker(
                L10n.string(.settingsTemperatureUnit, language: language),
                selection: $settingsStore.settings.temperatureUnit
            ) {
                ForEach(TemperatureUnit.allCases) { unit in
                    Text(L10n.label(for: unit, language: language))
                        .tag(unit)
                }
            }
            .pickerStyle(.segmented)

            Toggle(
                L10n.string(.settingsLaunchAtLogin, language: language),
                isOn: $settingsStore.launchAtLogin
            )

            if settingsStore.launchAtLoginRequiresApproval {
                HStack(alignment: .center, spacing: 8) {
                    Label(
                        L10n.string(.launchAtLoginRequiresApproval, language: language),
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(PowerFlowTheme.Typography.captionFloor)
                    .foregroundStyle(PowerFlowTheme.dischargeAmber(for: colorScheme, contrast: colorSchemeContrast))
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    Button(L10n.string(.openLoginItemsSettings, language: language)) {
                        settingsStore.openLoginItemsSettings()
                    }
                    .controlSize(.small)
                }
            }

            if let error = settingsStore.launchAtLoginError, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(PowerFlowTheme.Typography.captionFloor)
                    .foregroundStyle(PowerFlowTheme.warningRed(for: colorScheme, contrast: colorSchemeContrast))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(L10n.string(.settingsGeneral, language: language))
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(
                L10n.string(.settingsMaskSerials, language: language),
                isOn: $settingsStore.settings.maskSerialNumbers
            )

            Picker(
                L10n.string(.settingsLanguage, language: language),
                selection: $settingsStore.settings.appLanguage
            ) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(L10n.label(for: lang, language: language))
                        .tag(lang)
                }
            }
        } header: {
            Text(L10n.string(.settingsPrivacy, language: language))
        }
    }

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 7) {
                Text(
                    L10n.tr(
                        "MIT License · Open-source macOS power telemetry inspired by PowerTop (kDolphin) and powerflow (davelindo).",
                        zh: "MIT 开源许可 · 致敬 MIT 开源项目 PowerTop (kDolphin) 与 powerflow (davelindo)。",
                        language: language
                    )
                )
                .font(PowerFlowTheme.Typography.captionFloor)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    SettingsTelemetrySourceLabel(monitor: monitor, language: language)

                    Spacer()

                    Button(L10n.string(.settingsResetDefaults, language: language)) {
                        settingsStore.resetToDefaults()
                    }
                    .controlSize(.small)
                }
            }
        } header: {
            Text(L10n.string(.settingsAbout, language: language))
        }
    }
}

// MARK: - Live Snapshot Leaf Subviews (Isolate Observation From Grouped Form)

private struct SettingsTelemetrySubtitle: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let monitor: PowerMonitor
    let appVersion: String
    let language: AppLanguage

    var body: some View {
        Text("\(appVersion) · \(L10n.label(for: monitor.snapshot.telemetrySource, language: language))")
            .font(PowerFlowTheme.Typography.captionFloor)
            .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
            .lineLimit(1)
    }
}

private struct SettingsBatteryStatusChip: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let monitor: PowerMonitor
    let language: AppLanguage

    var body: some View {
        let snapshot = monitor.snapshot
        PowerFlowChip(
            icon: snapshot.isEffectivelyOnAC ? "bolt.fill" : "battery.75percent",
            text: snapshot.isDataAvailable
                ? PowerFormatters.percent(snapshot.batteryPercent)
                : L10n.string(.flowUnknown, language: language),
            tint: snapshot.isEffectivelyOnAC
                ? PowerFlowTheme.chargeGreen(for: colorScheme, contrast: colorSchemeContrast)
                : PowerFlowTheme.themeBlue(for: colorScheme, contrast: colorSchemeContrast)
        )
    }
}

private struct SettingsTelemetrySourceLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let monitor: PowerMonitor
    let language: AppLanguage

    var body: some View {
        Text(L10n.label(for: monitor.snapshot.telemetrySource, language: language))
            .font(PowerFlowTheme.Typography.captionFloor)
            .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast))
    }
}

// MARK: - Interactive Battery Icon Style Preview Card

private struct BatteryIconStylePreviewCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let style: BatteryIconStyle
    let title: String
    let displayMode: MenuBarDisplayMode
    let monitor: PowerMonitor
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private func renderSpec(for snapshot: PowerSnapshot) -> BatteryIconRenderSpec {
        if snapshot.isDataAvailable {
            return NativeBatteryIconRenderer.spec(
                for: snapshot,
                showsPercent: displayMode.showsPercentage,
                isDarkMenuBar: colorScheme == .dark,
                style: style
            )
        }
        return BatteryIconRenderSpec(
            percent: 82,
            state: .neutral,
            overlay: .chargingBolt,
            showsPercent: displayMode.showsPercentage,
            isDarkMenuBar: colorScheme == .dark,
            style: style
        )
    }

    private func previewTitle(for snapshot: PowerSnapshot) -> String {
        if snapshot.isDataAvailable {
            return StatusItemController.makeMenuBarTitle(snapshot: snapshot, mode: displayMode, style: style)
        }
        var parts: [String] = []
        if displayMode.showsPercentage && !style.drawsPercentInsideIcon {
            parts.append("82%")
        }
        if displayMode.showsWatts {
            parts.append("28W")
        }
        return parts.joined(separator: " · ")
    }

    private var cardFill: Color {
        let isDark = colorScheme == .dark
        if isSelected {
            return Color.accentColor.opacity(isDark ? 0.14 : 0.09)
        }
        if isHovered {
            return isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)
        }
        return PowerFlowTheme.nestedTileFill(for: colorScheme, contrast: colorSchemeContrast)
    }

    private var cardBorderColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.85)
        }
        if isHovered {
            return colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.18)
        }
        return PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let snapshot = monitor.snapshot

        Button(action: action) {
            VStack(spacing: 6.5) {
                miniMenuBarChrome(for: snapshot)
                    .accessibilityHidden(true)

                HStack(spacing: 5) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? Color.accentColor
                                : PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast)
                        )
                        .accessibilityHidden(true)

                    Text(title)
                        .font(PowerFlowTheme.Typography.rowLabel)
                        .fontWeight(isSelected ? .semibold : .medium)
                        .foregroundStyle(
                            isSelected
                                ? PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast)
                                : PowerFlowTheme.secondaryValue(for: colorScheme, contrast: colorSchemeContrast)
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7.5)
            .frame(maxWidth: .infinity)
            .background(shape.fill(cardFill))
            .overlay(
                shape.strokeBorder(
                    cardBorderColor,
                    lineWidth: isSelected ? 1.5 : (colorSchemeContrast == .increased ? 0.85 : 0.6)
                )
            )
            .contentShape(shape)
            .scaleEffect(isHovered && !isSelected && !reduceMotion ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeOut(duration: 0.14)) {
                    isHovered = hovering
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private func miniMenuBarChrome(for snapshot: PowerSnapshot) -> some View {
        let spec = renderSpec(for: snapshot)
        let renderedImage = NativeBatteryIconRenderer.render(spec: spec)
        let titleText = previewTitle(for: snapshot)
        let showExternalCaption = !titleText.isEmpty

        return HStack(spacing: 5.5) {
            Spacer(minLength: 4)

            if showExternalCaption {
                Text(titleText)
                    .font(.system(size: 11, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Image(nsImage: renderedImage)
                .renderingMode(spec.usesTemplateRendering ? .template : .original)
                .interpolation(.high)
                .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme, contrast: colorSchemeContrast))

            Image(systemName: "wifi")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast).opacity(0.55))

            Image(systemName: "switch.2")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme, contrast: colorSchemeContrast).opacity(0.45))
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color.black.opacity(0.36)
                        : Color.white.opacity(0.76)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    PowerFlowTheme.hairlineDivider(for: colorScheme, contrast: colorSchemeContrast),
                    lineWidth: 0.5
                )
        )
    }
}
