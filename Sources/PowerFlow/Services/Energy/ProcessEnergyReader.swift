import Darwin
import Foundation
import IOKit
import IOKit.pwr_mgt

/// Reads raw per-process energy, CPU, I/O, memory, and sleep-assertion telemetry in-process.
protocol ProcessEnergyReadingProvider: Sendable {
    func readProcessSamples() -> [RawProcessEnergySample]
}

/// Zero-root, zero-subprocess macOS process energy reader backed by `libproc` and `IOKit.pwr_mgt`.
final class ProcessEnergyReader: ProcessEnergyReadingProvider, @unchecked Sendable {
    private struct BundleMetadata: Sendable {
        let displayName: String?
        let bundleIdentifier: String?
    }

    private static let maxBundleCacheEntries = 512
    /// Matches `PROC_PIDPATHINFO_MAXSIZE` (`4 * MAXPATHLEN`), which is not imported into Swift as a C macro.
    private static let pidPathBufferSize = 4 * Int(MAXPATHLEN)

    private static let trackedSleepAssertionTypes: Set<String> = [
        "PreventUserIdleSystemSleep",
        "PreventUserIdleDisplaySleep",
        "PreventSystemSleep",
        "NoIdleSleepAssertion",
        "NoDisplaySleepAssertion",
    ]

    private static let machTimebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        let status = mach_timebase_info(&info)
        guard status == KERN_SUCCESS, info.denom != 0 else {
            return (1, 1)
        }
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    private let lock = NSLock()
    private var bundleMetadataCache: [String: BundleMetadata] = [:]

    init() {}

    func readProcessSamples() -> [RawProcessEnergySample] {
        let pids = listAllPIDs()
        guard !pids.isEmpty else { return [] }

        let sleepAssertionsByPID = readSleepAssertionsByPID()

        var samples: [RawProcessEnergySample] = []
        samples.reserveCapacity(pids.count)

        var nameBuffer = [UInt8](repeating: 0, count: 256)
        var pathBuffer = [UInt8](repeating: 0, count: Self.pidPathBufferSize)

        for pid in pids {
            guard pid > 0 else { continue }

            var rusage = rusage_info_v6()
            let rusageStatus: Int32 = withUnsafeMutablePointer(to: &rusage) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rusagePtr in
                    proc_pid_rusage(pid, RUSAGE_INFO_V6, rusagePtr)
                }
            }
            if rusageStatus != 0 {
                // Silently skip EPERM / ESRCH and inaccessible processes.
                continue
            }

            var bsdInfo = proc_bsdinfo()
            let bsdInfoSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
            let bsdReadBytes = proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                &bsdInfo,
                bsdInfoSize
            )
            let hasBsdInfo = bsdReadBytes == bsdInfoSize
            let ppid: Int32 = hasBsdInfo ? Int32(bsdInfo.pbi_ppid) : 0

            let executablePath = readExecutablePath(pid: pid, buffer: &pathBuffer)
            let processName = resolveProcessName(
                pid: pid,
                nameBuffer: &nameBuffer,
                bsdInfo: bsdInfo,
                hasBsdInfo: hasBsdInfo,
                executablePath: executablePath
            )

            let appBundlePath = Self.extractOuterAppBundlePath(from: executablePath)
            let bundleMetadata: BundleMetadata?
            if let appBundlePath {
                bundleMetadata = cachedBundleMetadata(for: appBundlePath)
            } else {
                bundleMetadata = nil
            }

            let totalCPUTicks = Self.saturatingAdd(rusage.ri_user_time, rusage.ri_system_time)
            let pCoreCPUTicks = Self.saturatingAdd(rusage.ri_user_ptime, rusage.ri_system_ptime)

            samples.append(
                RawProcessEnergySample(
                    pid: pid,
                    ppid: ppid,
                    startAbsTime: rusage.ri_proc_start_abstime,
                    processName: processName,
                    executablePath: executablePath,
                    appBundlePath: appBundlePath,
                    appDisplayName: bundleMetadata?.displayName,
                    bundleIdentifier: bundleMetadata?.bundleIdentifier,
                    energyNJ: rusage.ri_energy_nj,
                    pCoreEnergyNJ: rusage.ri_penergy_nj,
                    billedEnergyNJ: rusage.ri_billed_energy,
                    cpuTimeNS: Self.machAbsoluteToNanoseconds(totalCPUTicks),
                    pCoreTimeNS: Self.machAbsoluteToNanoseconds(pCoreCPUTicks),
                    idleWakeups: rusage.ri_pkg_idle_wkups,
                    diskReadBytes: rusage.ri_diskio_bytesread,
                    diskWriteBytes: rusage.ri_diskio_byteswritten,
                    physFootprintBytes: rusage.ri_phys_footprint,
                    sleepAssertionTypes: sleepAssertionsByPID[pid] ?? []
                )
            )
        }

        return samples
    }

    /// Returns the outermost `.app` bundle path containing `executablePath`,
    /// correctly attributing nested helper, renderer, and XPC bundles to their host app.
    static func extractOuterAppBundlePath(from executablePath: String) -> String? {
        guard !executablePath.isEmpty else { return nil }
        let components = (executablePath as NSString).pathComponents
        for index in components.indices {
            let component = components[index]
            if component.count > 4 && component.lowercased().hasSuffix(".app") {
                return NSString.path(withComponents: Array(components[0...index]))
            }
        }
        return nil
    }

    // MARK: - Private Darwin / IOKit Helpers

    private func listAllPIDs() -> [Int32] {
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else { return [] }

        var capacity = max(Int(estimatedCount) + 64, 256)
        for _ in 0..<2 {
            var buffer = [Int32](repeating: 0, count: capacity)
            let byteSize = Int32(capacity * MemoryLayout<Int32>.stride)
            let actualCount = buffer.withUnsafeMutableBytes { rawBuffer -> Int32 in
                guard let baseAddress = rawBuffer.baseAddress else { return -1 }
                return proc_listallpids(baseAddress, byteSize)
            }
            guard actualCount > 0 else { return [] }
            let count = Int(actualCount)
            if count < capacity {
                return Array(buffer.prefix(count))
            }
            capacity = max(capacity * 2, count + 128)
        }

        var finalBuffer = [Int32](repeating: 0, count: capacity)
        let finalByteSize = Int32(capacity * MemoryLayout<Int32>.stride)
        let finalCount = finalBuffer.withUnsafeMutableBytes { rawBuffer -> Int32 in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return proc_listallpids(baseAddress, finalByteSize)
        }
        guard finalCount > 0 else { return [] }
        return Array(finalBuffer.prefix(min(Int(finalCount), capacity)))
    }

    private func readExecutablePath(pid: Int32, buffer: inout [UInt8]) -> String {
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return Self.decodeCString(buffer, maxLength: Int(length))
    }

    private func resolveProcessName(
        pid: Int32,
        nameBuffer: inout [UInt8],
        bsdInfo: proc_bsdinfo,
        hasBsdInfo: Bool,
        executablePath: String
    ) -> String {
        let nameLen = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        if nameLen > 0 {
            let candidate = Self.decodeCString(nameBuffer, maxLength: Int(nameLen))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                return candidate
            }
        }

        if hasBsdInfo {
            let pbiName = Self.cStringFromTuple(bsdInfo.pbi_name)
            if !pbiName.isEmpty {
                return pbiName
            }
            let pbiComm = Self.cStringFromTuple(bsdInfo.pbi_comm)
            if !pbiComm.isEmpty {
                return pbiComm
            }
        }

        if !executablePath.isEmpty {
            let basename = (executablePath as NSString).lastPathComponent
            if !basename.isEmpty {
                return basename
            }
        }

        return "pid:\(pid)"
    }

    private func readSleepAssertionsByPID() -> [Int32: [String]] {
        var unmanagedAssertions: Unmanaged<CFDictionary>?
        let status = IOPMCopyAssertionsByProcess(&unmanagedAssertions)
        guard status == kIOReturnSuccess,
              let assertionsDict = unmanagedAssertions?.takeRetainedValue() as? [AnyHashable: Any]
        else {
            return [:]
        }

        var result: [Int32: [String]] = [:]
        result.reserveCapacity(assertionsDict.count)

        for (rawKey, rawValue) in assertionsDict {
            let pid: Int32
            if let number = rawKey as? NSNumber {
                pid = number.int32Value
            } else if let intKey = rawKey as? Int {
                pid = Int32(truncatingIfNeeded: intKey)
            } else if let strKey = rawKey as? String, let parsed = Int32(strKey) {
                pid = parsed
            } else {
                continue
            }

            guard pid > 0, let entries = rawValue as? [[String: Any]] else { continue }

            var matchedTypes: [String] = []
            var seen = Set<String>()
            for entry in entries {
                guard let assertType = entry["AssertType"] as? String,
                      Self.trackedSleepAssertionTypes.contains(assertType),
                      seen.insert(assertType).inserted
                else {
                    continue
                }
                matchedTypes.append(assertType)
            }

            if !matchedTypes.isEmpty {
                result[pid] = matchedTypes.sorted()
            }
        }

        return result
    }

    private func cachedBundleMetadata(for appBundlePath: String) -> BundleMetadata {
        lock.lock()
        if let cached = bundleMetadataCache[appBundlePath] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let bundle = Bundle(path: appBundlePath)
        let info = bundle?.infoDictionary
        let rawDisplayName = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
        let trimmedDisplayName = rawDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = URL(fileURLWithPath: appBundlePath)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let displayName: String?
        if let trimmedDisplayName, !trimmedDisplayName.isEmpty {
            displayName = trimmedDisplayName
        } else if !fallbackName.isEmpty {
            displayName = fallbackName
        } else {
            displayName = nil
        }

        let rawBundleID = bundle?.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleIdentifier = (rawBundleID?.isEmpty == false) ? rawBundleID : nil
        let metadata = BundleMetadata(displayName: displayName, bundleIdentifier: bundleIdentifier)

        lock.lock()
        if bundleMetadataCache.count >= Self.maxBundleCacheEntries {
            bundleMetadataCache.removeAll(keepingCapacity: true)
        }
        bundleMetadataCache[appBundlePath] = metadata
        lock.unlock()

        return metadata
    }

    private static func machAbsoluteToNanoseconds(_ ticks: UInt64) -> UInt64 {
        let tb = machTimebase
        guard tb.numer != tb.denom else { return ticks }
        let quotient = ticks / tb.denom
        let remainder = ticks % tb.denom
        let (qProd, qOverflow) = quotient.multipliedReportingOverflow(by: tb.numer)
        if qOverflow {
            return UInt64.max
        }
        let rProd = (remainder &* tb.numer) / tb.denom
        let (sum, sumOverflow) = qProd.addingReportingOverflow(rProd)
        return sumOverflow ? UInt64.max : sum
    }

    private static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : sum
    }

    private static func decodeCString(_ buffer: [UInt8], maxLength: Int) -> String {
        let limit = min(maxLength, buffer.count)
        var endIndex = limit
        for idx in 0..<limit where buffer[idx] == 0 {
            endIndex = idx
            break
        }
        guard endIndex > 0 else { return "" }
        return String(decoding: buffer[0..<endIndex], as: UTF8.self)
    }

    private static func cStringFromTuple<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { rawBuffer -> String in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var endIndex = bytes.count
            for idx in 0..<bytes.count where bytes[idx] == 0 {
                endIndex = idx
                break
            }
            guard endIndex > 0 else { return "" }
            return String(decoding: bytes[0..<endIndex], as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
