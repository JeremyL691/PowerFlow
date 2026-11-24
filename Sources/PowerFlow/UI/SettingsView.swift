import SwiftUI

struct SettingsView: View {
    @Bindable var settingsStore: PowerSettingsStore
    let monitor: PowerMonitor

    init(settingsStore: PowerSettingsStore, monitor: PowerMonitor) {
        self.settingsStore = settingsStore
        self.monitor = monitor
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
        Form {
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

                Picker(
                    L10n.string(.settingsIconStyle, language: language),
                    selection: $settingsStore.settings.batteryIconStyle
                ) {
                    ForEach(BatteryIconStyle.allCases) { style in
                        Text(L10n.label(for: style, language: language))
                            .tag(style)
                    }
                }
                .pickerStyle(.segmented)

                HStack(alignment: .top, spacing: 6) {
                    Image(
                        systemName: settingsStore.settings.menuBarDisplayMode.requiresPeriodicPolling
                            ? "clock.arrow.2.circlepath"
                            : "leaf.fill"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        settingsStore.settings.menuBarDisplayMode.requiresPeriodicPolling
                            ? Color.orange
                            : Color.green
                    )
                    .padding(.top, 1)

                    Text(L10n.string(.settingsZeroPollingHint, language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(L10n.string(.settingsMenuBar, language: language))
            }

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
            } header: {
                Text(L10n.string(.settingsGeneral, language: language))
            }

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

            Section {
                Toggle(
                    L10n.string(.settingsLaunchAtLogin, language: language),
                    isOn: $settingsStore.launchAtLogin
                )

                if let error = settingsStore.launchAtLoginError, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(L10n.string(.settingsStartup, language: language))
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(L10n.string(.appName, language: language)) \(appVersion)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(L10n.label(for: monitor.snapshot.telemetrySource, language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(
                        L10n.tr(
                            "MIT License · Open-source macOS power telemetry inspired by PowerTop (kDolphin) and powerflow (davelindo).",
                            zh: "MIT 开源许可 · 致敬 MIT 开源项目 PowerTop (kDolphin) 与 powerflow (davelindo)。",
                            language: language
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Spacer()
                        Button(L10n.string(.settingsResetDefaults, language: language)) {
                            settingsStore.resetToDefaults()
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
            } header: {
                Text(L10n.string(.settingsAbout, language: language))
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
        .onAppear {
            settingsStore.refreshLaunchAtLoginStatus()
        }
    }
}
