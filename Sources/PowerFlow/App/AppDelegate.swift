import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsStore: PowerSettingsStore?
    private var monitor: PowerMonitor?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments

        if arguments.contains("--dump-snapshot") {
            runDumpSnapshotAndExit()
            return
        }

        let isSmokeLaunch = arguments.contains("--smoke-launch")
        let isSmokeUI = arguments.contains("--smoke-ui")
        let isSmokeMode = isSmokeLaunch || isSmokeUI
        let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        // Keep unit-test host lightweight unless explicitly running a CLI smoke mode.
        if isRunningUnitTests && !isSmokeMode {
            return
        }

        NSApp.setActivationPolicy(.accessory)

        let store: PowerSettingsStore
        if isSmokeUI {
            store = PowerSettingsStore(userDefaults: nil, manageLaunchAtLogin: false)
        } else {
            store = PowerSettingsStore(manageLaunchAtLogin: !isSmokeMode)
        }
        let powerMonitor = PowerMonitor(settingsStore: store)
        let controller = StatusItemController(monitor: powerMonitor)

        self.settingsStore = store
        self.monitor = powerMonitor
        self.statusItemController = controller

        powerMonitor.start()

        if isSmokeLaunch {
            scheduleSmokeLaunchVerification()
        } else if isSmokeUI {
            scheduleSmokeUIVerification()
        }
    }

    /// Opening the app again (Finder, Spotlight, Dock) is the way in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItemController?.reveal()
        return false
    }

    func openSettings() {
        statusItemController?.openSettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.invalidate()
        statusItemController = nil
        monitor?.stop()
        monitor = nil
    }

    // MARK: - CLI Verification Modes

    private func runDumpSnapshotAndExit() {
        let snapshot = PowerMonitor.captureSingleSnapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(snapshot)
            if let json = String(data: data, encoding: .utf8) {
                print(json)
            }
            fflush(stdout)
            exit(0)
        } catch {
            fputs("dump-snapshot error: \(error)\n", stderr)
            fflush(stderr)
            exit(1)
        }
    }

    private func scheduleSmokeLaunchVerification() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            let leakedWindows = NSApp.windows.filter { window in
                guard window.isVisible else { return false }
                let className = String(describing: type(of: window))
                if className.contains("StatusBar") || window.level == .statusBar {
                    return false
                }
                return window.frame.width > 1 && window.frame.height > 1
            }

            self?.statusItemController?.invalidate()
            self?.monitor?.stop()

            if leakedWindows.isEmpty {
                print("smoke-launch: ok (no leaked content windows)")
                fflush(stdout)
                exit(0)
            } else {
                let names = leakedWindows.map { "\(type(of: $0))(title: \($0.title))" }.joined(separator: ", ")
                fputs("smoke-launch: failed — leaked visible windows: \(names)\n", stderr)
                fflush(stderr)
                exit(1)
            }
        }
    }

    private func scheduleSmokeUIVerification() {
        // Give the status bar item a brief runloop turn to attach, then open the popover and sustain live 1Hz telemetry for 2.5s across multiple real telemetryQueue timer ticks.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let controller = self.statusItemController, let monitor = self.monitor else {
                fputs("smoke-ui: failed — missing controller or monitor\n", stderr)
                fflush(stderr)
                exit(1)
            }
            controller.reveal()
            monitor.setPopoverVisible(true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self else { exit(1) }
                let hadData = self.monitor?.snapshot.isDataAvailable ?? false
                self.statusItemController?.invalidate()
                self.monitor?.stop()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if hadData {
                        print("smoke-ui: ok")
                        fflush(stdout)
                        exit(0)
                    } else {
                        fputs("smoke-ui: failed — snapshot never populated during live 1Hz run\n", stderr)
                        fflush(stderr)
                        exit(1)
                    }
                }
            }
        }
    }
}
