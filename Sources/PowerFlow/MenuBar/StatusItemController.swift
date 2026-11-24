import AppKit
import Observation
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private struct VisualSignature: Equatable {
        let iconSpec: BatteryIconRenderSpec
        let title: String
    }

    /// AppKit's default name for the first item, pinned so the position remembered by macOS and
    /// menu bar managers survives updates.
    private static let statusItemAutosaveName = "Item-0"

    private let monitor: PowerMonitor
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    private var settingsWindow: NSWindow?

    private var appearanceObservation: NSKeyValueObservation?
    private var buttonWindowMoveObserver: NotificationObserverToken?
    private var buttonWindowScreenObserver: NotificationObserverToken?
    private var screenParametersObserver: NotificationObserverToken?

    private var globalClickMonitor: EventMonitorToken?
    private var localClickMonitor: EventMonitorToken?

    private var lastVisualSignature: VisualSignature?
    private var lastTooltip: String?
    private var isPendingPopoverShow = false
    private var isClosingProgrammatically = false
    private var lastExternalCloseUptime: TimeInterval = -.greatestFiniteMagnitude
    private var isInvalidated = false

    init(monitor: PowerMonitor) {
        self.monitor = monitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        statusItem.autosaveName = Self.statusItemAutosaveName
        // A stored "hidden" flag under this name may outlive the item it was written for.
        statusItem.isVisible = true
        configurePopover()
        configureStatusButton()
        observeButtonAppearanceAndPosition()
        observeMonitorState()
    }

    // MARK: - Public Lifecycle

    /// Shows the popover, or Settings when the menu bar icon is hidden and nothing can anchor it.
    func reveal() {
        guard !isInvalidated else { return }
        showPopover()
        if !popover.isShown {
            openSettings()
        }
    }

    func openSettings() {
        guard !isInvalidated else { return }
        closePopover(sender: nil)

        if let existing = settingsWindow {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = makeSettingsWindow()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        isPendingPopoverShow = false

        removeClickMonitors()
        appearanceObservation?.invalidate()
        appearanceObservation = nil

        buttonWindowMoveObserver?.invalidate()
        buttonWindowMoveObserver = nil
        buttonWindowScreenObserver?.invalidate()
        buttonWindowScreenObserver = nil
        screenParametersObserver?.invalidate()
        screenParametersObserver = nil

        if popover.isShown {
            isClosingProgrammatically = true
            popover.performClose(nil)
        }
        popover.delegate = nil
        popover.contentViewController = nil
        monitor.setPopoverVisible(false)

        if let window = settingsWindow {
            window.delegate = nil
            window.close()
            settingsWindow = nil
        }

        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Setup

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    /// Built on demand and released on close so a hidden popover never re-renders.
    private func makePopoverContent() -> NSViewController {
        let visibleHeight = (statusItem.button?.window?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let contentView = MenuBarPopoverView(
            monitor: monitor,
            maxHeight: visibleHeight - 24,
            openSettings: { [weak self] in
                self?.openSettings()
            },
            quitApp: { [weak self] in
                self?.quitApplication()
            }
        )
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.sizingOptions = .preferredContentSize
        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: MenuBarPopoverView.width, height: .greatestFiniteMagnitude)
        )
        hostingController.view.frame.size = fittingSize
        popover.contentSize = fittingSize
        return hostingController
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
    }

    private func observeButtonAppearanceAndPosition() {
        guard let button = statusItem.button else { return }

        appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { @Sendable [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isInvalidated else { return }
                self.updateStatusItem(
                    snapshot: self.monitor.snapshot,
                    settings: self.monitor.settingsStore.settings
                )
            }
        }

        screenParametersObserver = NotificationObserverToken(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reanchorPopoverIfNeeded()
                }
            }
        )

        if let buttonWindow = button.window {
            attachWindowObservers(to: buttonWindow)
        }
    }

    private func attachWindowObservers(to window: NSWindow) {
        buttonWindowMoveObserver?.invalidate()
        buttonWindowScreenObserver?.invalidate()

        buttonWindowMoveObserver = NotificationObserverToken(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reanchorPopoverIfNeeded()
                }
            }
        )

        buttonWindowScreenObserver = NotificationObserverToken(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reanchorPopoverIfNeeded()
                }
            }
        )
    }

    private func observeMonitorState() {
        guard !isInvalidated else { return }
        withObservationTracking {
            let snapshot = monitor.snapshot
            let settings = monitor.settingsStore.settings
            updateStatusItem(snapshot: snapshot, settings: settings)
            if let window = settingsWindow {
                let title = L10n.tr("PowerFlow Settings", zh: "PowerFlow 设置", language: settings.appLanguage)
                if window.title != title {
                    window.title = title
                }
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeMonitorState()
            }
        }
    }

    // MARK: - Status Item Rendering

    private func updateStatusItem(snapshot: PowerSnapshot, settings: PowerSettings) {
        guard !isInvalidated, let button = statusItem.button else { return }

        if buttonWindowMoveObserver == nil, let buttonWindow = button.window {
            attachWindowObservers(to: buttonWindow)
        }

        let mode = settings.menuBarDisplayMode
        let iconSpec = NativeBatteryIconRenderer.spec(
            for: snapshot,
            showsPercent: mode.showsPercentage,
            isDarkMenuBar: isDarkMenuBar(for: button),
            style: settings.batteryIconStyle
        )
        let titleText = Self.makeMenuBarTitle(snapshot: snapshot, mode: mode, style: iconSpec.style)
        let visualSignature = VisualSignature(iconSpec: iconSpec, title: titleText)

        if visualSignature != lastVisualSignature {
            lastVisualSignature = visualSignature
            button.image = NativeBatteryIconRenderer.render(spec: iconSpec)

            if titleText.isEmpty {
                button.imagePosition = .imageOnly
                button.attributedTitle = NSAttributedString(string: "")
            } else {
                // macOS places the battery text before the icon.
                button.imagePosition = .imageTrailing
                let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .baselineOffset: 0.5
                ]
                button.attributedTitle = NSAttributedString(string: "\(titleText) ", attributes: attributes)
            }
        }

        let tooltip = makeTooltip(snapshot: snapshot, settings: settings)
        if tooltip != lastTooltip {
            lastTooltip = tooltip
            button.toolTip = tooltip
            button.setAccessibilityLabel(tooltip)
        }
    }

    private func isDarkMenuBar(for button: NSStatusBarButton) -> Bool {
        let best = button.effectiveAppearance.bestMatch(
            from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight]
        )
        return best == .darkAqua || best == .vibrantDark
    }

    /// Text beside the icon. The solid style carries the percentage inside the icon instead.
    static func makeMenuBarTitle(
        snapshot: PowerSnapshot,
        mode: MenuBarDisplayMode,
        style: BatteryIconStyle
    ) -> String {
        var parts: [String] = []
        if mode.showsPercentage && !style.drawsPercentInsideIcon {
            parts.append(snapshot.isDataAvailable ? PowerFormatters.percent(snapshot.batteryPercent) : "--%")
        }
        if mode.showsWatts {
            parts.append(compactWattsText(for: snapshot))
        }
        return parts.joined(separator: " · ")
    }

    private static func compactWattsText(for snapshot: PowerSnapshot) -> String {
        guard snapshot.isDataAvailable else { return "--W" }
        let watts: Double
        if snapshot.isEffectivelyOnAC {
            watts = snapshot.adapterInputPowerW > 0.05
                ? snapshot.adapterInputPowerW
                : snapshot.totalSystemLoadW
        } else {
            watts = snapshot.totalSystemLoadW > 0.05
                ? snapshot.totalSystemLoadW
                : abs(snapshot.batteryPowerW)
        }
        return PowerFormatters.compactWatts(max(0, watts))
    }

    private func makeTooltip(snapshot: PowerSnapshot, settings: PowerSettings) -> String {
        let language = settings.appLanguage
        let appName = L10n.string(.appName, language: language)
        guard snapshot.isDataAvailable else {
            return "\(appName) · \(L10n.string(.flowUnknown, language: language))"
        }

        var parts: [String] = [appName, PowerFormatters.percent(snapshot.batteryPercent)]

        if snapshot.isEffectivelyOnAC {
            let portLabel = snapshot.activeAdapter?.portLabel
                ?? L10n.string(.powerAdapter, language: language)
            let watts = snapshot.adapterInputPowerW > 0.05
                ? snapshot.adapterInputPowerW
                : snapshot.totalSystemLoadW
            if watts > 0.05 {
                parts.append("\(portLabel) (\(PowerFormatters.watts(watts, decimals: 1)))")
            } else {
                parts.append(portLabel)
            }
        } else {
            let loadW = snapshot.totalSystemLoadW > 0.05
                ? snapshot.totalSystemLoadW
                : abs(snapshot.batteryPowerW)
            let batteryLabel = L10n.string(.battery, language: language)
            if loadW > 0.05 {
                parts.append("\(batteryLabel) (\(PowerFormatters.watts(loadW, decimals: 1)))")
            } else {
                parts.append(batteryLabel)
            }
        }

        if snapshot.hasActiveOutboundPower {
            let outLabel = L10n.tr("Out", zh: "输出", language: language)
            parts.append("\(outLabel): \(PowerFormatters.watts(snapshot.totalOutboundPowerW, decimals: 1))")
        }

        if snapshot.isLowPowerModeEnabled {
            parts.append(L10n.string(.lowPowerMode, language: language))
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Click & Context Menu Handling

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard !isInvalidated else { return }

        if let event = NSApp.currentEvent,
           event.type == .rightMouseDown
            || event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)
        {
            closePopover(sender: sender)
            showContextMenu(relativeTo: sender)
            return
        }

        if popover.isShown {
            closePopover(sender: sender)
            return
        }

        if ProcessInfo.processInfo.systemUptime - lastExternalCloseUptime < 0.15 {
            return
        }

        guard !isPendingPopoverShow else { return }
        isPendingPopoverShow = true

        // Defer showing popover past the current mouseDown cycle so macOS 15–27
        // does not immediately dismiss the transient popover on the same click.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPendingPopoverShow = false
            self.showPopover()
        }
    }

    private func showPopover() {
        guard !isInvalidated, !popover.isShown else { return }
        guard let button = statusItem.button, button.window != nil else { return }

        isClosingProgrammatically = false

        if buttonWindowMoveObserver == nil, let buttonWindow = button.window {
            attachWindowObservers(to: buttonWindow)
        }

        popover.contentViewController = makePopoverContent()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard popover.isShown else {
            popover.contentViewController = nil
            return
        }
        popover.contentViewController?.view.window?.makeKey()
        installClickMonitors()
        monitor.setPopoverVisible(true)
    }

    private func closePopover(sender: Any?) {
        isPendingPopoverShow = false
        removeClickMonitors()
        if popover.isShown {
            isClosingProgrammatically = true
            popover.performClose(sender)
        }
        monitor.setPopoverVisible(false)
    }

    private func reanchorPopoverIfNeeded() {
        guard !isInvalidated, popover.isShown, let button = statusItem.button else { return }
        guard button.window != nil else {
            closePopover(sender: nil)
            return
        }
        popover.positioningRect = button.bounds
    }

    private func installClickMonitors() {
        removeClickMonitors()

        let globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover(sender: nil)
            }
        }
        globalClickMonitor = EventMonitorToken(globalMonitor)

        let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard self.popover.isShown else { return event }

            if event.type == .keyDown {
                if event.keyCode == 53 { // Escape
                    self.closePopover(sender: nil)
                    return nil
                }
                return event
            }

            let popoverWindow = self.popover.contentViewController?.view.window
            let statusButtonWindow = self.statusItem.button?.window

            if event.window === popoverWindow || event.window === statusButtonWindow {
                return event
            }

            self.closePopover(sender: nil)
            return event
        }
        localClickMonitor = EventMonitorToken(localMonitor)
    }

    private func removeClickMonitors() {
        globalClickMonitor?.invalidate()
        globalClickMonitor = nil
        localClickMonitor?.invalidate()
        localClickMonitor = nil
    }

    private func showContextMenu(relativeTo button: NSStatusBarButton) {
        let language = monitor.settingsStore.settings.appLanguage
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: L10n.string(.settings, language: language),
            action: #selector(menuOpenSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.string(.quitPowerFlow, language: language),
            action: #selector(menuQuitApplication(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
    }

    @objc private func menuOpenSettings(_ sender: Any?) {
        openSettings()
    }

    @objc private func menuQuitApplication(_ sender: Any?) {
        quitApplication()
    }

    private func quitApplication() {
        invalidate()
        NSApp.terminate(nil)
    }

    // MARK: - Window Builders

    private func makeSettingsWindow() -> NSWindow {
        let language = monitor.settingsStore.settings.appLanguage
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("PowerFlow Settings", zh: "PowerFlow 设置", language: language)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self

        let rootView = SettingsView(settingsStore: monitor.settingsStore, monitor: monitor)
        window.contentViewController = NSHostingController(rootView: rootView)
        return window
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        isClosingProgrammatically = false
        monitor.setPopoverVisible(true)
    }

    func popoverWillClose(_ notification: Notification) {
        if !isClosingProgrammatically {
            lastExternalCloseUptime = ProcessInfo.processInfo.systemUptime
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if !isClosingProgrammatically {
            lastExternalCloseUptime = ProcessInfo.processInfo.systemUptime
        }
        isClosingProgrammatically = false
        removeClickMonitors()
        popover.contentViewController = nil
        monitor.setPopoverVisible(false)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        if closingWindow === settingsWindow {
            settingsWindow?.delegate = nil
            settingsWindow = nil
        }
    }
}
