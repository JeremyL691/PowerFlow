import AppKit
import Observation
import QuartzCore
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
    private weak var popoverHostingController: NSHostingController<MenuBarPopoverView>?
    private weak var observedButtonWindow: NSWindow?

    private var appearanceObservation: NSKeyValueObservation?
    private var popoverSizeObservation: NSKeyValueObservation?
    private var appResignActiveObserver: NotificationObserverToken?
    private var buttonWindowMoveObserver: NotificationObserverToken?
    private var buttonWindowScreenObserver: NotificationObserverToken?
    private var screenParametersObserver: NotificationObserverToken?

    private var globalClickMonitor: EventMonitorToken?
    private var localClickMonitor: EventMonitorToken?

    private var lastVisualSignature: VisualSignature?
    private var lastTooltip: String?
    private var lastTargetPopoverSize: NSSize?
    private var currentPopoverMaxHeight: CGFloat = 800
    private var isPendingPopoverShow = false
    private var isClosingProgrammatically = false
    private var popoverCloseGeneration: UInt64 = 0
    private var lastExternalCloseUptime: TimeInterval = -.greatestFiniteMagnitude
    private var isInvalidated = false

    var isPopoverShown: Bool {
        popover.isShown
    }

    init(monitor: PowerMonitor) {
        self.monitor = monitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        statusItem.autosaveName = Self.statusItemAutosaveName
        // A stored "hidden" flag under this name may outlive the item it was written for.
        if !statusItem.isVisible {
            statusItem.isVisible = true
        }
        configurePopover()
        configureStatusButton()
        observeButtonAppearance()
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
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = makeSettingsWindow()
        settingsWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        isPendingPopoverShow = false

        removeClickMonitors()
        removePopoverPresentationObservers()
        appearanceObservation?.invalidate()
        appearanceObservation = nil
        popoverSizeObservation?.invalidate()
        popoverSizeObservation = nil
        lastTargetPopoverSize = nil
        popoverHostingController = nil

        if popover.isShown {
            isClosingProgrammatically = true
            popover.animates = false
            popover.close()
        }
        popover.delegate = nil
        popover.contentViewController = nil
        monitor.setPopoverVisible(false)

        if let window = settingsWindow {
            window.delegate = nil
            window.contentViewController = nil
            window.close()
            settingsWindow = nil
        }

        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Setup

    private func configurePopover() {
        popover.behavior = .transient
        syncPopoverAnimation()
        popover.delegate = self
    }

    private func syncPopoverAnimation() {
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func computePopoverMaxHeight() -> CGFloat {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let availableBelowButton: CGFloat
        if let buttonWindow = statusItem.button?.window {
            let belowButton = buttonWindow.frame.minY - visibleFrame.minY
            availableBelowButton = belowButton > 100 ? min(visibleFrame.height, belowButton) : visibleFrame.height
        } else {
            availableBelowButton = visibleFrame.height
        }
        // Leave vertical headroom for NSPopover's arrow (~13pt), window shadow/chrome, and bottom
        // screen margin so AppKit never runs out of .minY space and flips the popover sideways.
        return max(360, floor(availableBelowButton - 72))
    }

    private func makePopoverView(maxHeight: CGFloat) -> MenuBarPopoverView {
        MenuBarPopoverView(
            monitor: monitor,
            maxHeight: maxHeight,
            openSettings: { [weak self] in
                self?.openSettings()
            },
            quitApp: { [weak self] in
                self?.quitApplication()
            }
        )
    }

    /// Built on demand and released on close so a hidden popover never re-renders.
    private func makePopoverContent() -> NSViewController {
        popoverSizeObservation?.invalidate()
        popoverSizeObservation = nil
        lastTargetPopoverSize = nil

        let maxHeight = computePopoverMaxHeight()
        currentPopoverMaxHeight = maxHeight
        let hostingController = NSHostingController(rootView: makePopoverView(maxHeight: maxHeight))
        popoverHostingController = hostingController
        hostingController.sizingOptions = .preferredContentSize
        let rawFittingSize = hostingController.sizeThatFits(
            in: NSSize(width: MenuBarPopoverView.width, height: .greatestFiniteMagnitude)
        )
        let fittingSize = NSSize(
            width: MenuBarPopoverView.width,
            height: min(rawFittingSize.height, maxHeight)
        )
        hostingController.view.frame.size = fittingSize
        popover.contentSize = fittingSize
        lastTargetPopoverSize = fittingSize

        popoverSizeObservation = hostingController.observe(
            \.preferredContentSize,
            options: [.new]
        ) { @Sendable [weak self] _, change in
            guard let preferred = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.isInvalidated, self.popover.isShown else { return }
                guard preferred.height.isFinite, preferred.height > 1 else { return }
                let targetSize = NSSize(
                    width: MenuBarPopoverView.width,
                    height: min(preferred.height, self.currentPopoverMaxHeight)
                )
                let previous = self.lastTargetPopoverSize ?? self.popover.contentSize
                guard abs(previous.width - targetSize.width) > 1.0
                    || abs(previous.height - targetSize.height) > 1.0
                else {
                    return
                }
                self.lastTargetPopoverSize = targetSize
                self.syncPopoverAnimation()
                self.popover.contentSize = targetSize
            }
        }
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

    private func observeButtonAppearance() {
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
    }

    private func installPopoverPresentationObservers(for buttonWindow: NSWindow) {
        removePopoverPresentationObservers()

        appResignActiveObserver = NotificationObserverToken(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: NSApp,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.closePopover(sender: nil)
                }
            }
        )

        screenParametersObserver = NotificationObserverToken(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reanchorPopoverIfNeeded(updateMaxHeight: true)
                }
            }
        )

        attachWindowObservers(to: buttonWindow)
    }

    private func attachWindowObservers(to window: NSWindow) {
        buttonWindowMoveObserver?.invalidate()
        buttonWindowScreenObserver?.invalidate()
        observedButtonWindow = window

        buttonWindowMoveObserver = NotificationObserverToken(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reanchorPopoverIfNeeded(updateMaxHeight: false)
                }
            }
        )

        buttonWindowScreenObserver = NotificationObserverToken(
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeScreenNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reanchorPopoverIfNeeded(updateMaxHeight: true)
                }
            }
        )
    }

    private func removePopoverPresentationObservers() {
        appResignActiveObserver?.invalidate()
        appResignActiveObserver = nil
        buttonWindowMoveObserver?.invalidate()
        buttonWindowMoveObserver = nil
        buttonWindowScreenObserver?.invalidate()
        buttonWindowScreenObserver = nil
        screenParametersObserver?.invalidate()
        screenParametersObserver = nil
        observedButtonWindow = nil
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

        if popover.isShown, let buttonWindow = button.window, buttonWindow !== observedButtonWindow {
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
        if snapshot.isAdapterSupplyingPower {
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

    func makeTooltip(snapshot: PowerSnapshot, settings: PowerSettings) -> String {
        Self.makeTooltip(snapshot: snapshot, settings: settings)
    }

    static func makeTooltip(snapshot: PowerSnapshot, settings: PowerSettings) -> String {
        let language = settings.appLanguage
        let appName = L10n.string(.appName, language: language)
        guard snapshot.isDataAvailable else {
            return "\(appName) · \(L10n.string(.flowUnknown, language: language))"
        }

        var parts: [String] = [appName, PowerFormatters.percent(snapshot.batteryPercent)]

        if snapshot.isAdapterSupplyingPower {
            let portLabel = snapshot.activeAdapter?.portLabel
                ?? L10n.string(.powerAdapter, language: language)
            let watts = snapshot.adapterInputPowerW > 0.05
                ? snapshot.adapterInputPowerW
                : snapshot.totalSystemLoadW
            if watts > 0.05 {
                parts.append("\(portLabel) (\(PowerFormatters.compactWatts(max(0, watts))))")
            } else {
                parts.append(portLabel)
            }
        } else {
            let loadW = snapshot.totalSystemLoadW > 0.05
                ? snapshot.totalSystemLoadW
                : abs(snapshot.batteryPowerW)
            let batteryLabel = L10n.string(.battery, language: language)
            if loadW > 0.05 {
                parts.append("\(batteryLabel) (\(PowerFormatters.compactWatts(max(0, loadW))))")
            } else {
                parts.append(batteryLabel)
            }
        }

        if snapshot.hasActiveOutboundPower {
            let outLabel = L10n.tr("Out", zh: "输出", language: language)
            parts.append("\(outLabel): \(PowerFormatters.compactWatts(max(0, snapshot.totalOutboundPowerW)))")
        }

        if snapshot.isLowPowerModeEnabled {
            parts.append(L10n.string(.lowPowerMode, language: language))
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Click & Context Menu Handling

    static func shouldOpenContextMenu(
        eventType: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        switch eventType {
        case .rightMouseDown, .rightMouseUp:
            return true
        case .leftMouseDown, .leftMouseUp:
            return modifierFlags.contains(.control)
        default:
            return false
        }
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard !isInvalidated else { return }

        if let event = NSApp.currentEvent,
           Self.shouldOpenContextMenu(eventType: event.type, modifierFlags: event.modifierFlags)
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
        NSApp.activate()

        // Defer showing popover past the current mouseDown cycle so macOS 15–27
        // does not immediately dismiss the transient popover on the same click.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPendingPopoverShow else { return }
            self.isPendingPopoverShow = false
            self.showPopover()
        }
    }

    private func canAnchorPopover(to button: NSStatusBarButton, in buttonWindow: NSWindow) -> Bool {
        guard statusItem.isVisible else { return false }
        guard buttonWindow.occlusionState.contains(.visible) else { return false }
        let frame = buttonWindow.frame
        guard frame.width > 0, frame.height > 0 else { return false }
        guard let screen = buttonWindow.screen else { return false }
        let intersection = screen.frame.intersection(frame)
        return !intersection.isNull && intersection.width >= 1 && intersection.height >= 1
    }

    private func showPopover() {
        guard !isInvalidated, !popover.isShown else { return }
        guard let button = statusItem.button,
              let buttonWindow = button.window,
              canAnchorPopover(to: button, in: buttonWindow)
        else {
            return
        }

        isClosingProgrammatically = false
        syncPopoverAnimation()
        let savedTab = UserDefaults.standard.string(forKey: "popoverDetailTab")
        monitor.setEnergyTabVisible(savedTab == PopoverDetailTab.energy.rawValue)
        monitor.setPopoverVisible(true)

        popover.contentViewController = makePopoverContent()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard popover.isShown else {
            popoverSizeObservation?.invalidate()
            popoverSizeObservation = nil
            lastTargetPopoverSize = nil
            popoverHostingController = nil
            popover.contentViewController = nil
            monitor.setPopoverVisible(false)
            return
        }
        popover.contentViewController?.view.window?.makeKey()
        installClickMonitors()
        installPopoverPresentationObservers(for: buttonWindow)
    }

    private func closePopover(sender: Any?) {
        isPendingPopoverShow = false
        guard popover.isShown else {
            removeClickMonitors()
            removePopoverPresentationObservers()
            monitor.setPopoverVisible(false)
            return
        }

        syncPopoverAnimation()
        let previousGeneration = popoverCloseGeneration
        isClosingProgrammatically = true
        popover.performClose(sender)
        if popoverCloseGeneration == previousGeneration && popover.isShown {
            isClosingProgrammatically = false
        }
    }

    private func reanchorPopoverIfNeeded(updateMaxHeight: Bool) {
        guard !isInvalidated, popover.isShown, let button = statusItem.button else { return }
        guard let buttonWindow = button.window,
              canAnchorPopover(to: button, in: buttonWindow)
        else {
            closePopover(sender: nil)
            return
        }
        if buttonWindow !== observedButtonWindow {
            attachWindowObservers(to: buttonWindow)
        }
        if updateMaxHeight {
            updatePopoverMaxHeightIfNeeded()
        }
        popover.positioningRect = button.bounds
    }

    private func updatePopoverMaxHeightIfNeeded() {
        let newMaxHeight = computePopoverMaxHeight()
        guard abs(newMaxHeight - currentPopoverMaxHeight) > 0.5 else { return }
        currentPopoverMaxHeight = newMaxHeight
        guard let hostingController = popoverHostingController else { return }
        hostingController.rootView = makePopoverView(maxHeight: newMaxHeight)
        let rawFittingSize = hostingController.sizeThatFits(
            in: NSSize(width: MenuBarPopoverView.width, height: .greatestFiniteMagnitude)
        )
        let targetSize = NSSize(
            width: MenuBarPopoverView.width,
            height: min(rawFittingSize.height, newMaxHeight)
        )
        lastTargetPopoverSize = targetSize
        popover.contentSize = targetSize
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
        let size = SettingsView.windowSize
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("PowerFlow Settings", zh: "PowerFlow 设置", language: language)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
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
        popoverCloseGeneration &+= 1
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
        removePopoverPresentationObservers()
        popoverSizeObservation?.invalidate()
        popoverSizeObservation = nil
        lastTargetPopoverSize = nil
        popoverHostingController = nil
        popover.contentViewController = nil
        monitor.setPopoverVisible(false)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        if closingWindow === settingsWindow {
            closingWindow.delegate = nil
            closingWindow.contentViewController = nil
            settingsWindow = nil
        }
    }
}
