import Foundation
import IOKit

// MARK: - SMC Value

struct SMCValue: Sendable, Equatable {
    let key: String
    let dataSize: Int
    let dataType: String
    let bytes: [UInt8]

    /// Decodes numeric SMC values across Apple Silicon and Intel data types.
    ///
    /// - `flt ` (trimmed `"flt"`): 32-bit IEEE 754 float in little-endian byte order.
    /// - `flag`: 1-byte boolean (`0.0` or `1.0`).
    /// - `ui8`, `si8`, `ui16`, `si16`, `ui32`, `si32`, `ui64`, `si64`: big-endian integers.
    /// - `fpXY` / `spXY`: 16-bit big-endian unsigned/signed fixed-point with `Y` fractional bits (hex digit).
    /// - `ioft`: 64-bit little-endian signed 48.16 fixed-point.
    func floatValue() -> Double? {
        let trimmedType = dataType.trimmingCharacters(in: .whitespaces)
        guard !bytes.isEmpty else { return nil }

        switch trimmedType {
        case "flt":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil

        case "flag":
            return bytes[0] != 0 ? 1.0 : 0.0

        case "ui8":
            return Double(bytes[0])

        case "si8":
            return Double(Int8(bitPattern: bytes[0]))

        case "ui16":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(raw)

        case "si16":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw))

        case "ui32":
            guard bytes.count >= 4 else { return nil }
            let raw = (UInt32(bytes[0]) << 24)
                | (UInt32(bytes[1]) << 16)
                | (UInt32(bytes[2]) << 8)
                | UInt32(bytes[3])
            return Double(raw)

        case "si32":
            guard bytes.count >= 4 else { return nil }
            let raw = (UInt32(bytes[0]) << 24)
                | (UInt32(bytes[1]) << 16)
                | (UInt32(bytes[2]) << 8)
                | UInt32(bytes[3])
            return Double(Int32(bitPattern: raw))

        case "ui64":
            guard bytes.count >= 8 else { return nil }
            var raw: UInt64 = 0
            for index in 0..<8 {
                raw = (raw << 8) | UInt64(bytes[index])
            }
            return Double(raw)

        case "si64":
            guard bytes.count >= 8 else { return nil }
            var raw: UInt64 = 0
            for index in 0..<8 {
                raw = (raw << 8) | UInt64(bytes[index])
            }
            return Double(Int64(bitPattern: raw))

        case "ioft":
            guard bytes.count >= 8 else { return nil }
            var raw: UInt64 = 0
            for index in 0..<8 {
                raw |= UInt64(bytes[index]) << (UInt64(index) * 8)
            }
            let value = Double(Int64(bitPattern: raw)) / 65536.0
            return value.isFinite ? value : nil

        default:
            return decodeFixedPoint(type: trimmedType)
        }
    }

    func stringValue() -> String? {
        guard !bytes.isEmpty else { return nil }
        let payload = bytes.prefix(while: { $0 != 0 })
        guard !payload.isEmpty,
              let decoded = String(bytes: payload, encoding: .utf8)
        else {
            return nil
        }
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Decodes integer SMC values stored in little-endian byte order (used by Apple Silicon
    /// `B0*` SBS gas-gauge keys such as `B0AV`, `B0AC`, and `B0CT`). Falls back to `floatValue()`
    /// for non-integer types (`flt`, `fp*`, `sp*`, `flag`).
    func littleEndianNumericValue() -> Double? {
        let trimmedType = dataType.trimmingCharacters(in: .whitespaces)
        switch trimmedType {
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            return Double(raw)
        case "si16":
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            return Double(Int16(bitPattern: raw))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            return Double(raw)
        case "si32":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            return Double(Int32(bitPattern: raw))
        default:
            return floatValue()
        }
    }

    private func decodeFixedPoint(type: String) -> Double? {
        guard type.count == 4, bytes.count >= 2 else { return nil }
        let chars = Array(type)
        let isSigned: Bool
        if chars[0] == "s" && chars[1] == "p" {
            isSigned = true
        } else if chars[0] == "f" && chars[1] == "p" {
            isSigned = false
        } else {
            return nil
        }

        guard Self.hexNibble(chars[2]) != nil,
              let fractionalBits = Self.hexNibble(chars[3])
        else {
            return nil
        }

        let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        let scale = Double(1 << fractionalBits)
        let value = isSigned
            ? Double(Int16(bitPattern: raw)) / scale
            : Double(raw) / scale
        return value.isFinite ? value : nil
    }

    private static func hexNibble(_ character: Character) -> Int? {
        guard let ascii = character.asciiValue else { return nil }
        switch ascii {
        case 48...57: return Int(ascii - 48)       // '0'...'9'
        case 65...70: return Int(ascii - 65 + 10)  // 'A'...'F'
        case 97...102: return Int(ascii - 97 + 10) // 'a'...'f'
        default: return nil
        }
    }
}

// MARK: - Key Reading Protocol

protocol SMCKeyReading: Sendable {
    func readKey(_ key: String) -> SMCValue?
}

// MARK: - Kernel ABI Structs (80-byte AppleSMC layout)

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    private var padding0: UInt8 = 0
    private var padding1: UInt8 = 0
    private var padding2: UInt8 = 0
}

typealias SMCBytesTuple = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

struct SMCKeyData {
    var key: UInt32 = 0
    var vers: SMCVersion = SMCVersion()
    var pLimitData: SMCPLimitData = SMCPLimitData()
    var keyInfo: SMCKeyInfoData = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytesTuple = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

// MARK: - AppleSMC Connection

final class SMCConnection: SMCKeyReading, @unchecked Sendable {
    private enum Command {
        static let handleYPCEventSelector: UInt32 = 2
        static let readBytes: UInt8 = 5
        static let readKeyInfo: UInt8 = 9
    }

    private enum CachedKeyInfo {
        case available(SMCKeyInfoData)
        case unavailable
    }

    /// Outcome of a single call into AppleSMC.
    private enum CallOutcome {
        case success(SMCKeyData)
        /// The SMC reported kSMCKeyNotFound (0x84) in the payload.
        case keyNotFound
        /// Any other failure. Nothing about the key should be cached.
        case transientFailure
        /// The user client is no longer usable and must be reopened.
        case connectionLost
    }

    private static let smcKeyNotFound: UInt8 = 0x84

    /// IOKit and Mach errors meaning the user client went away (sleep, device reset, etc.).
    private static let connectionLostCodes: Set<kern_return_t> = [
        kern_return_t(truncatingIfNeeded: kIOReturnNotOpen),
        kern_return_t(truncatingIfNeeded: kIOReturnNoDevice),
        kern_return_t(truncatingIfNeeded: kIOReturnNotAttached),
        kern_return_t(truncatingIfNeeded: MACH_SEND_INVALID_DEST)
    ]

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    private var keyInfoCache: [UInt32: CachedKeyInfo] = [:]

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connection != 0
    }

    init() {
        openLocked()
    }

    deinit {
        close()
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        closeLocked()
    }

    func readKey(_ key: String) -> SMCValue? {
        guard let fourCC = Self.fourCC(key) else { return nil }

        lock.lock()
        defer { lock.unlock() }

        if connection == 0 {
            openLocked()
        }
        guard connection != 0 else { return nil }

        guard let cachedInfo = lookupKeyInfoLocked(fourCC: fourCC),
              case .available(let keyInfo) = cachedInfo,
              keyInfo.dataSize > 0,
              keyInfo.dataSize <= 32
        else {
            return nil
        }

        var input = SMCKeyData()
        input.key = fourCC
        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = Command.readBytes

        switch callSMCLocked(input: input) {
        case .success(let output):
            let size = Int(keyInfo.dataSize)
            let extractedBytes = Self.extractBytes(from: output.bytes, count: size)
            return SMCValue(
                key: key,
                dataSize: size,
                dataType: Self.fourCCString(keyInfo.dataType),
                bytes: extractedBytes
            )
        case .keyNotFound, .transientFailure:
            return nil
        case .connectionLost:
            closeLocked()
            return nil
        }
    }

    // MARK: - Private Helpers (must hold lock)

    private func openLocked() {
        guard connection == 0 else { return }
        guard let matching = IOServiceMatching("AppleSMC") else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(service) }

        var newConnection: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &newConnection)
        if kr == KERN_SUCCESS {
            connection = newConnection
        }
    }

    /// Returns the cached key info, or performs a lookup. Only definitive answers
    /// (key found, or key reported missing) are cached. Transient failures return nil
    /// and leave the cache untouched so the next call retries.
    private func lookupKeyInfoLocked(fourCC: UInt32) -> CachedKeyInfo? {
        if let cached = keyInfoCache[fourCC] {
            return cached
        }

        var input = SMCKeyData()
        input.key = fourCC
        input.data8 = Command.readKeyInfo

        switch callSMCLocked(input: input) {
        case .success(let output):
            let cached: CachedKeyInfo = output.keyInfo.dataSize > 0
                ? .available(output.keyInfo)
                : .unavailable
            keyInfoCache[fourCC] = cached
            return cached
        case .keyNotFound:
            keyInfoCache[fourCC] = .unavailable
            return .unavailable
        case .transientFailure:
            return nil
        case .connectionLost:
            closeLocked()
            return nil
        }
    }

    private func closeLocked() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
        keyInfoCache.removeAll()
    }

    private func callSMCLocked(input: SMCKeyData) -> CallOutcome {
        guard connection != 0 else { return .connectionLost }
        var inputStruct = input
        var outputStruct = SMCKeyData()
        var outputSize = MemoryLayout<SMCKeyData>.stride

        let result = IOConnectCallStructMethod(
            connection,
            Command.handleYPCEventSelector,
            &inputStruct,
            MemoryLayout<SMCKeyData>.stride,
            &outputStruct,
            &outputSize
        )

        guard result == KERN_SUCCESS else {
            return Self.connectionLostCodes.contains(result) ? .connectionLost : .transientFailure
        }

        // macOS 26/27 hardened validation: kernel may return KERN_SUCCESS while reporting
        // key/permission errors inside the SMC payload's `result` or `status` bytes.
        if outputStruct.result == Self.smcKeyNotFound {
            return .keyNotFound
        }
        guard outputStruct.result == 0, outputStruct.status == 0 else {
            return .transientFailure
        }

        return .success(outputStruct)
    }

    // MARK: - FourCC Utilities

    static func fourCC(_ key: String) -> UInt32? {
        let utf8 = Array(key.utf8)
        guard utf8.count == 4 else { return nil }
        return (UInt32(utf8[0]) << 24)
            | (UInt32(utf8[1]) << 16)
            | (UInt32(utf8[2]) << 8)
            | UInt32(utf8[3])
    }

    static func fourCCString(_ value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "    "
    }

    private static func extractBytes(from tuple: SMCBytesTuple, count: Int) -> [UInt8] {
        let clamped = max(0, min(count, 32))
        return withUnsafeBytes(of: tuple) { rawBuffer in
            Array(rawBuffer.prefix(clamped))
        }
    }
}
