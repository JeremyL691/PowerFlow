import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class PowerMonitor {
    static let summaryRefreshInterval: TimeInterval = 3.0
    static let summaryTimerLeewayMilliseconds: Int = 500
    static let liveTimerLeewayMilliseconds: Int = 100
    nonisolated static let portTopologyRefreshInterval: TimeInterval = 30.0
    static let wakeRefreshCoalesceWindow: TimeInterval = 1.0
    /// Coalesced follow-up refresh offsets after plug/unplug events so AC handshake (3.0s)
    /// and unplug debounce (1.5s) converge smoothly even in zero-polling dormant mode.
    static let plugEventBurstOffsets: [TimeInterval] = [0.2, 0.8, 2.0, 3.2]

    private(set) var snapshot: PowerSnapshot = .empty
    let settingsStore: PowerSettingsStore
    private(set) var isLiveStreaming: Bool = false
    private(set) var isPopoverVisible: Bool = false
    private(set) var activePollingTier: PowerPollingTier = .suspended

    @ObservationIgnored private let smartBatteryReader: any SmartBatteryReadingProvider
    @ObservationIgnored private let ioPortReader: any IOPortReadingProvider
    @ObservationIgnored private let smcReader: SMCReader
    @ObservationIgnored private let notifier: any PowerEventNotifying
    @ObservationIgnored private let resolver: PowerFlowResolver
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let lowPowerModeProvider: @Sendable () -> Bool
    @ObservationIgnored private let thermalStateProvider: @Sendable () -> ProcessInfo.ThermalState
    @ObservationIgnored private let isDisplayAsleepProvider: @Sendable () -> Bool
    @ObservationIgnored private let uptimeProvider: @Sendable () -> TimeInterval

    @ObservationIgnored private let telemetryQueue = DispatchQueue(
        label: "com.powerflow.monitor.telemetry",
        qos: .utility
    )
    @ObservationIgnored private let workerState = WorkerState()

    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isSystemAsleep = false
    @ObservationIgnored private var isScreenAsleep = false
    @ObservationIgnored private var needsPostWakeFullScan = false
    @ObservationIgnored private var lastWakeRefreshUptime: TimeInterval = -.greatestFiniteMagnitude

    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private var burstWorkItems: [DispatchWorkItem] = []
    @ObservationIgnored private var burstEndUptime: TimeInterval = -.greatestFiniteMagnitude

    var hasActiveTimer: Bool {
        timer != nil
    }

    var hasPendingBurstRefreshes: Bool {
        uptimeProvider() < burstEndUptime
    }

    init(
        settingsStore: PowerSettingsStore,
        smartBatteryReader: any SmartBatteryReadingProvider = SmartBatteryReader(),
        ioPortReader: any IOPortReadingProvider = IOPortPowerReader(),
        smcReader: SMCReader = SMCReader(),
        notifier: (any PowerEventNotifying)? = nil,
        resolver: PowerFlowResolver = PowerFlowResolver(),
        clock: @escaping @Sendable () -> Date = Date.init,
        lowPowerModeProvider: @escaping @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
        thermalStateProvider: @escaping @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState },
        isDisplayAsleepProvider: @escaping @Sendable () -> Bool = { CGDisplayIsAsleep(CGMainDisplayID()) != 0 },
        uptimeProvider: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.settingsStore = settingsStore
        self.smartBatteryReader = smartBatteryReader
        self.ioPortReader = ioPortReader
        self.smcReader = smcReader
        self.notifier = notifier ?? PowerSourceNotifier()
        self.resolver = resolver
        self.clock = clock
        self.lowPowerModeProvider = lowPowerModeProvider
        self.thermalStateProvider = thermalStateProvider
        self.isDisplayAsleepProvider = isDisplayAsleepProvider
        self.uptimeProvider = uptimeProvider

        let existingOnChange = settingsStore.onChange
        settingsStore.onChange = { [weak self] newSettings in
            existingOnChange?(newSettings)
            self?.handleSettingsChanged(newSettings)
        }
    }

    // MARK: - Public Lifecycle

    func start() {
        guard !isStarted else { return }
        BatteryChargeLimitResolver.startMonitoringExternalLimiters()
        isStarted = true
        isSystemAsleep = false
        isScreenAsleep = isDisplayAsleepProvider()
        needsPostWakeFullScan = isScreenAsleep

        notifier.start { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleSystemEvent(event)
            }
        }

        reconfigureScheduling(triggerImmediateRefresh: true, forcePortScanOnImmediate: true)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        notifier.stop()
        cancelTimer()
        cancelBurstRefreshes()
        activePollingTier = .suspended
        isLiveStreaming = false
    }

    func refreshNow() {
        let uiVisible = isPopoverVisible
        scheduleAsyncSample(
            includeCellTopology: uiVisible,
            includeHealthDetails: uiVisible,
            includePortTopology: uiVisible,
            fullSMC: uiVisible,
            includeChargeLimit: uiVisible,
            restartBurstsOnPlugChange: false
        )
    }

    func setPopoverVisible(_ visible: Bool) {
        guard isPopoverVisible != visible else { return }
        isPopoverVisible = visible
        reconfigureScheduling(triggerImmediateRefresh: visible, forcePortScanOnImmediate: visible)
    }

    /// Synchronously captures a full live hardware snapshot (used by `--dump-snapshot`).
    nonisolated static func captureSingleSnapshot(
        smartBatteryReader: any SmartBatteryReadingProvider = SmartBatteryReader(),
        ioPortReader: any IOPortReadingProvider = IOPortPowerReader(),
        smcReader: SMCReader = SMCReader(),
        resolver: PowerFlowResolver = PowerFlowResolver(
            polarityCalibrator: SMCPolarityCalibrator(userDefaults: nil)
        ),
        isLowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled,
        timestamp: Date = Date()
    ) -> PowerSnapshot {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                BatteryChargeLimitResolver.startMonitoringExternalLimiters()
            }
        }
        let reading = smartBatteryReader.readSmartBattery(
            includeCellTopology: true,
            includeHealthDetails: true
        )
        let smc = smcReader.readSample(full: true)
        let topology = ioPortReader.readPortTopology()
        let phase: PowerConnectionPhase = (reading?.isExternalConnected == true) ? .onAC : .onBattery

        return resolver.resolve(
            reading: reading,
            smc: smc,
            portTopology: topology,
            connectionPhase: phase,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            timestamp: timestamp,
            isInTransition: false,
            includeChargeLimit: true,
            hasLivePortOutputs: true
        )
    }

    // MARK: - Scheduling & Policy

    static func computePollingTier(
        isStarted: Bool,
        isSystemAsleep: Bool,
        isScreenAsleep: Bool,
        isPopoverVisible: Bool,
        settings: PowerSettings
    ) -> PowerPollingTier {
        guard isStarted, !isSystemAsleep, !isScreenAsleep else {
            return .suspended
        }
        if isPopoverVisible {
            return .live(interval: settings.liveRefreshInterval.rawValue)
        }
        if settings.menuBarDisplayMode.requiresPeriodicPolling {
            return .summary(interval: summaryRefreshInterval)
        }
        return .dormant
    }

    private func handleSettingsChanged(_ newSettings: PowerSettings) {
        guard isStarted else { return }
        let previousTier = activePollingTier
        reconfigureScheduling(
            triggerImmediateRefresh: previousTier == .dormant && newSettings.menuBarDisplayMode.requiresPeriodicPolling,
            forcePortScanOnImmediate: false
        )
    }

    private func handleSystemEvent(_ event: PowerSystemEvent) {
        guard isStarted else { return }

        switch event {
        case .powerSourceChanged:
            guard !isSystemAsleep && !isScreenAsleep else { return }
            let uiVisible = isPopoverVisible
            // Follow-up bursts are only scheduled if the sample detects an actual external-power
            // transition (not routine 1% SoC / TimeRemaining IOPS notifications).
            scheduleAsyncSample(
                includeCellTopology: uiVisible,
                includeHealthDetails: uiVisible,
                includePortTopology: uiVisible,
                fullSMC: uiVisible,
                includeChargeLimit: uiVisible,
                restartBurstsOnPlugChange: true
            )

        case .lowPowerModeChanged:
            guard !isSystemAsleep && !isScreenAsleep else { return }
            let uiVisible = isPopoverVisible
            scheduleAsyncSample(
                includeCellTopology: uiVisible,
                includeHealthDetails: uiVisible,
                includePortTopology: uiVisible,
                fullSMC: uiVisible,
                includeChargeLimit: uiVisible,
                restartBurstsOnPlugChange: false
            )

        case .systemWillSleep:
            isSystemAsleep = true
            cancelTimer()
            cancelBurstRefreshes()
            reconfigureScheduling(triggerImmediateRefresh: false, forcePortScanOnImmediate: false)

        case .screensDidSleep:
            isScreenAsleep = true
            cancelTimer()
            cancelBurstRefreshes()
            reconfigureScheduling(triggerImmediateRefresh: false, forcePortScanOnImmediate: false)

        case .systemDidWake:
            isSystemAsleep = false
            isScreenAsleep = isDisplayAsleepProvider()
            // Power and sensor discovery state may have changed during sleep.
            workerState.resetConnectionPhase()
            resolver.resetEstimator()
            smcReader.resetDiscoveryCaches()
            if isScreenAsleep {
                needsPostWakeFullScan = true
                reconfigureScheduling(triggerImmediateRefresh: false, forcePortScanOnImmediate: false)
            } else {
                needsPostWakeFullScan = false
                lastWakeRefreshUptime = uptimeProvider()
                reconfigureScheduling(triggerImmediateRefresh: true, forcePortScanOnImmediate: true)
            }

        case .screensDidWake:
            let wasScreenAsleep = isScreenAsleep
            isScreenAsleep = false
            let recentlyRefreshedOnWake = !wasScreenAsleep
                && (uptimeProvider() - lastWakeRefreshUptime) < Self.wakeRefreshCoalesceWindow
            let shouldRefresh = !recentlyRefreshedOnWake
            let forceFullScan = needsPostWakeFullScan || isPopoverVisible
            if shouldRefresh {
                needsPostWakeFullScan = false
            }
            reconfigureScheduling(triggerImmediateRefresh: shouldRefresh, forcePortScanOnImmediate: forceFullScan)
        }
    }

    private func reconfigureScheduling(
        triggerImmediateRefresh: Bool,
        forcePortScanOnImmediate: Bool
    ) {
        let newTier = Self.computePollingTier(
            isStarted: isStarted,
            isSystemAsleep: isSystemAsleep,
            isScreenAsleep: isScreenAsleep,
            isPopoverVisible: isPopoverVisible,
            settings: settingsStore.settings
        )

        let previousTier = activePollingTier
        let tierChanged = newTier != previousTier
        activePollingTier = newTier
        if isLiveStreaming != newTier.includesFullHardwareScan {
            isLiveStreaming = newTier.includesFullHardwareScan
        }

        if tierChanged {
            cancelTimer()

            switch newTier {
            case .suspended:
                cancelBurstRefreshes()
            case .dormant:
                // Zero-polling dormant mode: no recurring timer is created. One sample is taken when
                // live polling stops so a plug transition in progress can still converge.
                if previousTier.includesFullHardwareScan && !triggerImmediateRefresh {
                    scheduleAsyncSample(
                        includeCellTopology: false,
                        includeHealthDetails: false,
                        includePortTopology: false,
                        fullSMC: false,
                        includeChargeLimit: false,
                        restartBurstsOnPlugChange: true
                    )
                }
            case .summary(let interval):
                startTimer(
                    interval: interval,
                    leewayMilliseconds: Self.summaryTimerLeewayMilliseconds,
                    fullHardwareScan: false
                )
            case .live(let interval):
                cancelBurstRefreshes()
                startTimer(
                    interval: interval,
                    leewayMilliseconds: Self.liveTimerLeewayMilliseconds,
                    fullHardwareScan: true
                )
            }
        }

        if triggerImmediateRefresh && newTier != .suspended {
            let uiVisible = isPopoverVisible
            let includeDetails = uiVisible || forcePortScanOnImmediate
            scheduleAsyncSample(
                includeCellTopology: uiVisible,
                includeHealthDetails: includeDetails,
                includePortTopology: includeDetails,
                fullSMC: includeDetails,
                includeChargeLimit: includeDetails,
                restartBurstsOnPlugChange: false
            )
        }
    }

    private func startTimer(
        interval: TimeInterval,
        leewayMilliseconds: Int,
        fullHardwareScan: Bool
    ) {
        cancelTimer()

        let intervalMs = max(100, Int((interval * 1000.0).rounded()))
        let handler = makeSampleClosure(
            includeCellTopology: fullHardwareScan,
            includeHealthDetails: fullHardwareScan,
            includePortTopology: fullHardwareScan,
            fullSMC: fullHardwareScan,
            includeChargeLimit: fullHardwareScan,
            restartBurstsOnPlugChange: false
        )
        timer = Self.makeTelemetryTimer(
            queue: telemetryQueue,
            intervalMilliseconds: intervalMs,
            leewayMilliseconds: leewayMilliseconds,
            handler: handler
        )
    }

    private func cancelTimer() {
        guard let existing = timer else { return }
        timer = nil
        existing.setEventHandler(handler: nil)
        existing.cancel()
    }

    private func schedulePlugEventBursts() {
        cancelBurstRefreshes()
        guard isStarted, !isSystemAsleep, !isScreenAsleep else { return }
        burstEndUptime = uptimeProvider() + (Self.plugEventBurstOffsets.last ?? 0)
        let includeCells = isPopoverVisible

        for offset in Self.plugEventBurstOffsets {
            let handler = makeSampleClosure(
                includeCellTopology: includeCells,
                includeHealthDetails: includeCells,
                includePortTopology: true,
                fullSMC: true,
                includeChargeLimit: includeCells,
                restartBurstsOnPlugChange: false
            )
            let item = Self.makeTelemetryWorkItem(handler: handler)
            burstWorkItems.append(item)
            Self.enqueueTelemetryWork(on: telemetryQueue, after: offset, workItem: item)
        }
    }

    private func cancelBurstRefreshes() {
        for item in burstWorkItems {
            item.cancel()
        }
        burstWorkItems.removeAll()
        burstEndUptime = -.greatestFiniteMagnitude
    }

    private func scheduleAsyncSample(
        includeCellTopology: Bool,
        includeHealthDetails: Bool,
        includePortTopology: Bool,
        fullSMC: Bool,
        includeChargeLimit: Bool,
        restartBurstsOnPlugChange: Bool
    ) {
        let handler = makeSampleClosure(
            includeCellTopology: includeCellTopology,
            includeHealthDetails: includeHealthDetails,
            includePortTopology: includePortTopology,
            fullSMC: fullSMC,
            includeChargeLimit: includeChargeLimit,
            restartBurstsOnPlugChange: restartBurstsOnPlugChange
        )
        Self.enqueueTelemetryWork(on: telemetryQueue, handler: handler)
    }

    // MARK: - Nonisolated GCD Helpers (Swift 6 Safe)

    private nonisolated func makeSampleClosure(
        includeCellTopology: Bool,
        includeHealthDetails: Bool,
        includePortTopology: Bool,
        fullSMC: Bool,
        includeChargeLimit: Bool,
        restartBurstsOnPlugChange: Bool
    ) -> @Sendable () -> Void {
        { [weak self] in
            self?.performSampleOnTelemetryQueue(
                includeCellTopology: includeCellTopology,
                includeHealthDetails: includeHealthDetails,
                includePortTopology: includePortTopology,
                fullSMC: fullSMC,
                includeChargeLimit: includeChargeLimit,
                restartBurstsOnPlugChange: restartBurstsOnPlugChange
            )
        }
    }

    private nonisolated static func makeTelemetryTimer(
        queue: DispatchQueue,
        intervalMilliseconds: Int,
        leewayMilliseconds: Int,
        handler: @escaping @Sendable () -> Void
    ) -> DispatchSourceTimer {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + .milliseconds(intervalMilliseconds),
            repeating: .milliseconds(intervalMilliseconds),
            leeway: .milliseconds(leewayMilliseconds)
        )
        source.setEventHandler(handler: handler)
        source.resume()
        return source
    }

    private nonisolated static func makeTelemetryWorkItem(
        handler: @escaping @Sendable () -> Void
    ) -> DispatchWorkItem {
        DispatchWorkItem(block: handler)
    }

    private nonisolated static func enqueueTelemetryWork(
        on queue: DispatchQueue,
        handler: @escaping @Sendable () -> Void
    ) {
        queue.async(execute: handler)
    }

    private nonisolated static func enqueueTelemetryWork(
        on queue: DispatchQueue,
        after offset: TimeInterval,
        workItem: DispatchWorkItem
    ) {
        queue.asyncAfter(deadline: .now() + offset, execute: workItem)
    }

    private nonisolated func performSampleOnTelemetryQueue(
        includeCellTopology: Bool,
        includeHealthDetails: Bool,
        includePortTopology: Bool,
        fullSMC: Bool,
        includeChargeLimit: Bool,
        restartBurstsOnPlugChange: Bool
    ) {
        let now = clock()
        let reading = smartBatteryReader.readSmartBattery(
            includeCellTopology: includeCellTopology,
            includeHealthDetails: includeHealthDetails
        )
        let smc = smcReader.readSample(full: fullSMC)
        let lowPower = lowPowerModeProvider()

        let phase: PowerConnectionPhase
        let shouldScanPorts: Bool
        let plugChanged: Bool
        let isInTransition: Bool

        if let reading {
            let hasValidACTelemetry = (smc.deliveryRateW ?? 0) > 0.5
                || (reading.telemetrySystemPowerInMW ?? 0) > 500
                || reading.activeAdapter != nil
            let eval = workerState.advanceConnectionPhase(
                isExternalConnected: reading.isExternalConnected,
                hasValidACTelemetry: hasValidACTelemetry,
                now: now
            )
            let periodicOrAdapterRefresh = workerState.evaluatePortTopologyRefresh(
                reading: reading,
                now: now,
                refreshInterval: Self.portTopologyRefreshInterval
            )
            phase = eval.phase
            isInTransition = eval.isInTransition
            shouldScanPorts = includePortTopology
                || eval.externalConnectedChanged
                || eval.isInTransition
                || periodicOrAdapterRefresh
            plugChanged = eval.externalConnectedChanged && (restartBurstsOnPlugChange || isInTransition)
        } else {
            workerState.resetConnectionPhase()
            phase = .onBattery
            shouldScanPorts = includePortTopology
            plugChanged = false
            isInTransition = false
        }

        let topology: [IOPortTopologyEntry]
        if shouldScanPorts {
            let scanned = ioPortReader.readPortTopology()
            workerState.setCachedPortTopology(scanned, at: now)
            topology = scanned
        } else {
            topology = workerState.cachedPortTopology()
        }

        let resolved = resolver.resolve(
            reading: reading,
            smc: smc,
            portTopology: topology,
            connectionPhase: phase,
            isLowPowerModeEnabled: lowPower,
            thermalState: thermalStateProvider(),
            timestamp: now,
            isInTransition: isInTransition,
            includeChargeLimit: includeChargeLimit,
            hasLivePortOutputs: fullSMC
        )

        Task { @MainActor [weak self] in
            guard let self, self.isStarted else { return }
            self.snapshot = resolved
            guard !self.activePollingTier.includesFullHardwareScan else { return }
            if plugChanged || (isInTransition && !self.hasPendingBurstRefreshes) {
                self.schedulePlugEventBursts()
            }
        }
    }

    // MARK: - Thread-Safe Worker State

    private final class WorkerState: @unchecked Sendable {
        struct ConnectionEvaluation: Sendable {
            let phase: PowerConnectionPhase
            let externalConnectedChanged: Bool
            let isInTransition: Bool
        }

        private struct AdapterTopologyFingerprint: Equatable, Sendable {
            let activeAdapterID: Int?
            let activeWatts: Double?
            let rawAdapterCount: Int
            let outboundPortIndices: [Int]

            init(reading: SmartBatteryReading) {
                self.activeAdapterID = reading.activeAdapter?.adapterID
                self.activeWatts = reading.activeAdapter?.watts
                self.rawAdapterCount = reading.rawAdapters.count
                self.outboundPortIndices = reading.powerOutDetails.map(\.portIndex).sorted()
            }
        }

        private let lock = NSLock()
        private var connectionMachine = PowerConnectionStateMachine()
        private var lastExternalConnected: Bool?
        private var portTopologyCache: [IOPortTopologyEntry] = []
        private var lastPortTopologyScanDate: Date?
        private var lastAdapterFingerprint: AdapterTopologyFingerprint?

        func advanceConnectionPhase(
            isExternalConnected: Bool,
            hasValidACTelemetry: Bool,
            now: Date
        ) -> ConnectionEvaluation {
            lock.lock()
            defer { lock.unlock() }
            let changed = lastExternalConnected != nil && lastExternalConnected != isExternalConnected
            lastExternalConnected = isExternalConnected
            let phase = connectionMachine.advance(
                isExternalConnected: isExternalConnected,
                hasValidACTelemetry: hasValidACTelemetry,
                now: now
            )
            return ConnectionEvaluation(
                phase: phase,
                externalConnectedChanged: changed,
                isInTransition: connectionMachine.isInTransition
            )
        }

        func evaluatePortTopologyRefresh(
            reading: SmartBatteryReading,
            now: Date,
            refreshInterval: TimeInterval
        ) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let fingerprint = AdapterTopologyFingerprint(reading: reading)
            let adapterChanged = lastAdapterFingerprint != nil && lastAdapterFingerprint != fingerprint
            lastAdapterFingerprint = fingerprint

            let isStale: Bool
            if let lastScan = lastPortTopologyScanDate {
                let elapsed = now.timeIntervalSince(lastScan)
                isStale = elapsed >= refreshInterval || elapsed < 0
            } else {
                isStale = true
            }
            return adapterChanged || isStale
        }

        func resetConnectionPhase() {
            lock.lock()
            defer { lock.unlock() }
            connectionMachine.reset()
            lastExternalConnected = nil
            lastPortTopologyScanDate = nil
            lastAdapterFingerprint = nil
        }

        func setCachedPortTopology(_ entries: [IOPortTopologyEntry], at now: Date) {
            lock.lock()
            portTopologyCache = entries
            lastPortTopologyScanDate = now
            lock.unlock()
        }

        func cachedPortTopology() -> [IOPortTopologyEntry] {
            lock.lock()
            defer { lock.unlock() }
            return portTopologyCache
        }
    }
}
