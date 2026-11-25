import Foundation
@testable import PowerFlow

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        _value += 1
        let next = _value
        lock.unlock()
        return next
    }
}

final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        self._value = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            _value = newValue
            lock.unlock()
        }
    }
}

final class DynamicSmartBatteryReader: SmartBatteryReadingProvider, @unchecked Sendable {
    private let provider: @Sendable () -> SmartBatteryReading?

    init(provider: @escaping @Sendable () -> SmartBatteryReading?) {
        self.provider = provider
    }

    func readSmartBattery(includeCellTopology: Bool) -> SmartBatteryReading? {
        provider()
    }

    func readSmartBattery(includeCellTopology: Bool, includeHealthDetails: Bool) -> SmartBatteryReading? {
        provider()
    }
}

final class MockSmartBatteryReader: SmartBatteryReadingProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _reading: SmartBatteryReading?
    private var _readCount = 0
    private var _cellTopologyScanCount = 0
    private var _healthDetailsScanCount = 0

    init(reading: SmartBatteryReading?) {
        self._reading = reading
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _readCount
    }

    var cellTopologyScanCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _cellTopologyScanCount
    }

    var healthDetailsScanCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _healthDetailsScanCount
    }

    func setReading(_ reading: SmartBatteryReading?) {
        lock.lock()
        _reading = reading
        lock.unlock()
    }

    func resetCounters() {
        lock.lock()
        _readCount = 0
        _cellTopologyScanCount = 0
        _healthDetailsScanCount = 0
        lock.unlock()
    }

    func readSmartBattery(includeCellTopology: Bool) -> SmartBatteryReading? {
        readSmartBattery(includeCellTopology: includeCellTopology, includeHealthDetails: true)
    }

    func readSmartBattery(includeCellTopology: Bool, includeHealthDetails: Bool) -> SmartBatteryReading? {
        lock.lock()
        _readCount += 1
        if includeCellTopology {
            _cellTopologyScanCount += 1
        }
        if includeHealthDetails {
            _healthDetailsScanCount += 1
        }
        let current = _reading
        lock.unlock()
        return current
    }
}

final class MockIOPortReader: IOPortReadingProvider, @unchecked Sendable {
    private let lock = NSLock()
    let entries: [IOPortTopologyEntry]
    private var _readCount = 0

    init(entries: [IOPortTopologyEntry]) {
        self.entries = entries
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _readCount
    }

    func resetCounters() {
        lock.lock()
        _readCount = 0
        lock.unlock()
    }

    func readPortTopology() -> [IOPortTopologyEntry] {
        lock.lock()
        _readCount += 1
        lock.unlock()
        return entries
    }
}

final class MockProcessEnergyReader: ProcessEnergyReadingProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var _samples: [RawProcessEnergySample]
    private var _queuedResponses: [[RawProcessEnergySample]]
    private var _provider: (@Sendable () -> [RawProcessEnergySample])?
    private var _readCount = 0

    init(samples: [RawProcessEnergySample] = []) {
        self._samples = samples
        self._queuedResponses = []
        self._provider = nil
    }

    init(queuedResponses: [[RawProcessEnergySample]], fallback: [RawProcessEnergySample] = []) {
        self._samples = fallback
        self._queuedResponses = queuedResponses
        self._provider = nil
    }

    init(provider: @escaping @Sendable () -> [RawProcessEnergySample]) {
        self._samples = []
        self._queuedResponses = []
        self._provider = provider
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _readCount
    }

    func setSamples(_ samples: [RawProcessEnergySample]) {
        lock.lock()
        _samples = samples
        _queuedResponses.removeAll()
        _provider = nil
        lock.unlock()
    }

    func enqueue(_ samples: [RawProcessEnergySample]) {
        lock.lock()
        _queuedResponses.append(samples)
        lock.unlock()
    }

    func resetCounters() {
        lock.lock()
        _readCount = 0
        lock.unlock()
    }

    func readProcessSamples() -> [RawProcessEnergySample] {
        lock.lock()
        _readCount += 1
        if !_queuedResponses.isEmpty {
            let next = _queuedResponses.removeFirst()
            lock.unlock()
            return next
        }
        let provider = _provider
        let fallback = _samples
        lock.unlock()
        return provider?() ?? fallback
    }
}

struct SilentSMCKeyReader: SMCKeyReading {
    func readKey(_ key: String) -> SMCValue? {
        nil
    }
}

final class MockPowerEventNotifier: PowerEventNotifying, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (PowerSystemEvent) -> Void)?

    func start(onEvent: @escaping @Sendable (PowerSystemEvent) -> Void) {
        lock.lock()
        handler = onEvent
        lock.unlock()
    }

    func stop() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    func emit(_ event: PowerSystemEvent) {
        lock.lock()
        let callback = handler
        lock.unlock()
        callback?(event)
    }
}

/// Keeps values in memory so tests never leave preference files behind.
final class InMemoryUserDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]
    private var _writeCount = 0

    var writeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _writeCount
    }

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return storage[defaultName]
    }

    override func data(forKey defaultName: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[defaultName] as? Data
    }

    override func string(forKey defaultName: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[defaultName] as? String
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock()
        storage[defaultName] = value
        _writeCount += 1
        lock.unlock()
    }

    override func removeObject(forKey defaultName: String) {
        lock.lock()
        storage[defaultName] = nil
        lock.unlock()
    }
}
