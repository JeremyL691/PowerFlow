import AppKit

final class EventMonitorToken: @unchecked Sendable {
    private let lock = NSLock()
    private var monitor: Any?

    init(_ monitor: Any?) {
        self.monitor = monitor
    }

    func invalidate() {
        lock.lock()
        let current = monitor
        monitor = nil
        lock.unlock()

        guard let current else { return }
        if Thread.isMainThread {
            NSEvent.removeMonitor(current)
        } else {
            let boxed = UncheckedSendableBox(value: current)
            DispatchQueue.main.async {
                NSEvent.removeMonitor(boxed.value)
            }
        }
    }

    deinit {
        invalidate()
    }
}

final class NotificationObserverToken: @unchecked Sendable {
    private let lock = NSLock()
    private var token: NSObjectProtocol?

    init(_ token: NSObjectProtocol) {
        self.token = token
    }

    func invalidate() {
        lock.lock()
        let current = token
        token = nil
        lock.unlock()

        if let current {
            NotificationCenter.default.removeObserver(current)
        }
    }

    deinit {
        invalidate()
    }
}

private struct UncheckedSendableBox: @unchecked Sendable {
    let value: Any
}
