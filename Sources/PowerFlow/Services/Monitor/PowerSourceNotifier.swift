import AppKit
import Foundation
import IOKit.ps

enum PowerSystemEvent: Sendable, Equatable {
    case powerSourceChanged
    case lowPowerModeChanged
    case systemWillSleep
    case systemDidWake
    case screensDidSleep
    case screensDidWake
}

protocol PowerEventNotifying: AnyObject, Sendable {
    func start(onEvent: @escaping @Sendable (PowerSystemEvent) -> Void)
    func stop()
}

private final class IOPSCallbackBox: @unchecked Sendable {
    let handler: @Sendable () -> Void

    init(_ handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }
}

private func iopsNotificationCallback(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let box = Unmanaged<IOPSCallbackBox>.fromOpaque(context).takeUnretainedValue()
    box.handler()
}

/// Zero-polling system event monitor for power source changes, Low Power Mode,
/// system sleep/wake, and display sleep/wake.
final class PowerSourceNotifier: PowerEventNotifying, @unchecked Sendable {
    private let lock = NSLock()
    private var isStarted = false
    private var runLoopSource: CFRunLoopSource?
    private var iopsContextPointer: UnsafeMutableRawPointer?
    private var defaultCenterObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {}

    deinit {
        stop()
    }

    func start(onEvent: @escaping @Sendable (PowerSystemEvent) -> Void) {
        lock.lock()
        if isStarted {
            lock.unlock()
            return
        }
        isStarted = true

        // 1. IOKit Power Sources run loop source (AC plug/unplug, battery state changes)
        let box = IOPSCallbackBox {
            onEvent(.powerSourceChanged)
        }
        let retainedPtr = Unmanaged.passRetained(box).toOpaque()
        if let unmanagedSource = IOPSNotificationCreateRunLoopSource(iopsNotificationCallback, retainedPtr) {
            let source = unmanagedSource.takeRetainedValue()
            self.runLoopSource = source
            self.iopsContextPointer = retainedPtr
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        } else {
            Unmanaged<IOPSCallbackBox>.fromOpaque(retainedPtr).release()
        }

        // 2. Low Power Mode instant updates
        let lowPowerObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: nil
        ) { _ in
            onEvent(.lowPowerModeChanged)
        }
        defaultCenterObservers.append(lowPowerObserver)

        // 3. System & display sleep/wake lifecycle notifications
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let mappings: [(Notification.Name, PowerSystemEvent)] = [
            (NSWorkspace.willSleepNotification, .systemWillSleep),
            (NSWorkspace.didWakeNotification, .systemDidWake),
            (NSWorkspace.screensDidSleepNotification, .screensDidSleep),
            (NSWorkspace.screensDidWakeNotification, .screensDidWake),
        ]

        for (name, event) in mappings {
            let observer = workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { _ in
                onEvent(event)
            }
            workspaceObservers.append(observer)
        }

        lock.unlock()
    }

    func stop() {
        lock.lock()
        guard isStarted else {
            lock.unlock()
            return
        }
        isStarted = false

        let source = runLoopSource
        let contextPtr = iopsContextPointer
        let defaultTokens = defaultCenterObservers
        let workspaceTokens = workspaceObservers

        runLoopSource = nil
        iopsContextPointer = nil
        defaultCenterObservers.removeAll()
        workspaceObservers.removeAll()
        lock.unlock()

        for token in defaultTokens {
            NotificationCenter.default.removeObserver(token)
        }
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }

        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }

        if let contextPtr {
            if Thread.isMainThread {
                Unmanaged<IOPSCallbackBox>.fromOpaque(contextPtr).release()
            } else {
                // Defer release to the main queue so any in-flight main-runloop
                // C callback completes before the box is deallocated.
                let address = UInt(bitPattern: contextPtr)
                DispatchQueue.main.async {
                    guard let ptr = UnsafeMutableRawPointer(bitPattern: address) else { return }
                    Unmanaged<IOPSCallbackBox>.fromOpaque(ptr).release()
                }
            }
        }
    }
}
