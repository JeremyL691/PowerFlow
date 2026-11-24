import Foundation
import IOKit

enum IOKitHelpers {
    // MARK: - Safe Dictionary Extraction

    /// Extracts an `Int`, safely preserving IOKit two's-complement negative values
    /// serialized as unsigned 64-bit `CFNumber` (`UInt64` > `Int64.max`).
    static func extractInt(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if type(of: value) == Bool.self {
            return nil
        }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return nil
        }

        if let uint64Val = value as? UInt64 {
            return Int(Int64(bitPattern: uint64Val))
        }
        if let intVal = value as? Int {
            return intVal
        }
        if let int64Val = value as? Int64 {
            return Int(int64Val)
        }
        if let uintVal = value as? UInt {
            return Int(Int64(bitPattern: UInt64(uintVal)))
        }
        if let int32Val = value as? Int32 {
            return Int(int32Val)
        }
        if let uint32Val = value as? UInt32 {
            return Int(uint32Val)
        }
        if let int16Val = value as? Int16 {
            return Int(int16Val)
        }
        if let uint16Val = value as? UInt16 {
            return Int(uint16Val)
        }
        if let int8Val = value as? Int8 {
            return Int(int8Val)
        }
        if let uint8Val = value as? UInt8 {
            return Int(uint8Val)
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return nil
            }
            let objCType = String(cString: number.objCType)
            if objCType == "Q" || number.uint64Value > UInt64(Int64.max) {
                return Int(Int64(bitPattern: number.uint64Value))
            }
            return Int(number.int64Value)
        }
        return nil
    }

    static func extractInt(_ dict: [String: Any], key: String) -> Int? {
        extractInt(dict[key])
    }

    static func extractBool(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        if let boolVal = value as? Bool {
            return boolVal
        }
        if let number = value as? NSNumber {
            return number.int64Value != 0
        }
        if let intVal = extractInt(value) {
            return intVal != 0
        }
        return nil
    }

    static func extractBool(_ dict: [String: Any], key: String) -> Bool? {
        extractBool(dict[key])
    }

    static func extractString(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func extractString(_ dict: [String: Any], key: String) -> String? {
        extractString(dict[key])
    }

    static func extractDict(_ dict: [String: Any], key: String) -> [String: Any]? {
        dict[key] as? [String: Any]
    }

    static func extractDictArray(_ dict: [String: Any], key: String) -> [[String: Any]]? {
        if let array = dict[key] as? [[String: Any]] {
            return array
        }
        // IOKit properties such as IOPortFeaturePowerSource.PowerSourceOptions are bridged as CFSet/NSSet.
        if let set = dict[key] as? NSSet {
            let dicts = set.allObjects.compactMap { $0 as? [String: Any] }
            return dicts.isEmpty && set.count > 0 ? nil : dicts
        }
        return nil
    }

    static func extractIntArray(_ dict: [String: Any], key: String) -> [Int]? {
        guard let rawArray = dict[key] as? [Any] else { return nil }
        let values = rawArray.compactMap { extractInt($0) }
        return values.isEmpty && !rawArray.isEmpty ? nil : values
    }

    // MARK: - IORegistry Property Copying

    static func copyIOServiceProperties(className: String) -> [String: Any]? {
        guard let matching = IOServiceMatching(className) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        return copyRegistryProperties(entry: service)
    }

    static func copyAllIOServiceProperties(className: String) -> [[String: Any]] {
        guard let matching = IOServiceMatching(className) else { return [] }
        var iterator: io_iterator_t = IO_OBJECT_NULL
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS, iterator != IO_OBJECT_NULL else { return [] }
        defer { IOObjectRelease(iterator) }

        var results: [[String: Any]] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(service) }
            if let props = copyRegistryProperties(entry: service) {
                results.append(props)
            }
        }
        return results
    }

    static func copyRegistryProperties(entry: io_registry_entry_t) -> [String: Any]? {
        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(
            entry,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard kr == KERN_SUCCESS,
              let properties = unmanagedProperties?.takeRetainedValue() as? [String: Any]
        else {
            return nil
        }
        return properties
    }

    static func copyClassName(entry: io_registry_entry_t) -> String? {
        IOObjectCopyClass(entry)?.takeRetainedValue() as String?
    }

    // MARK: - Battery Manufacture Date Formatting

    /// Decodes macOS battery manufacture date from either:
    /// 1. Classic 16-bit SMBus bitfield (`year = 1980 + ((raw >> 9) & 0x7F)`, `month = (raw >> 5) & 0x0F`, `day = raw & 0x1F`)
    /// 2. Apple Silicon 6-byte little-endian ASCII `YYMMDD` where `year = 1992 + YY`
    ///    (e.g. `60680257417779` = `0x373039303233` -> `"320907"` -> `"2024-09-07"`).
    /// 3. 8-byte little-endian ASCII `YYYYMMDD` fallback.
    static func formatBatteryManufactureDate(
        _ raw: Int,
        relativeTo referenceDate: Date = Date()
    ) -> String? {
        guard raw > 0 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let maxYear = calendar.component(.year, from: referenceDate) + 1

        // Case 1: 16-bit SMBus packed bitfield
        if raw <= 0xFFFF {
            let day = raw & 0x1F
            let month = (raw >> 5) & 0x0F
            let year = 1980 + ((raw >> 9) & 0x7F)
            return validatedISODate(
                year: year,
                month: month,
                day: day,
                minYear: 1980,
                maxYear: maxYear,
                calendar: calendar
            )
        }

        let bits = UInt64(bitPattern: Int64(raw))
        let allBytes = (0..<8).map { shift in
            UInt8((bits >> (UInt64(shift) * 8)) & 0xFF)
        }

        // Case 2: 6-byte little-endian ASCII YYMMDD (Apple Silicon gas gauge, epoch 1992)
        let sixBytes = Array(allBytes.prefix(6))
        if allBytes[6] == 0, allBytes[7] == 0,
           let digits = asciiDigits(sixBytes)
        {
            let yy = digits[0] * 10 + digits[1]
            let mm = digits[2] * 10 + digits[3]
            let dd = digits[4] * 10 + digits[5]
            let year = 1992 + yy
            if let formatted = validatedISODate(
                year: year,
                month: mm,
                day: dd,
                minYear: 2000,
                maxYear: maxYear,
                calendar: calendar
            ) {
                return formatted
            }
        }

        // Case 3: 8-byte little-endian ASCII YYYYMMDD
        if let digits = asciiDigits(allBytes) {
            let year = digits[0] * 1000 + digits[1] * 100 + digits[2] * 10 + digits[3]
            let mm = digits[4] * 10 + digits[5]
            let dd = digits[6] * 10 + digits[7]
            if let formatted = validatedISODate(
                year: year,
                month: mm,
                day: dd,
                minYear: 2000,
                maxYear: maxYear,
                calendar: calendar
            ) {
                return formatted
            }
        }

        return nil
    }

    private static func asciiDigits(_ bytes: [UInt8]) -> [Int]? {
        var result: [Int] = []
        result.reserveCapacity(bytes.count)
        for byte in bytes {
            guard byte >= 48 && byte <= 57 else { return nil }
            result.append(Int(byte - 48))
        }
        return result
    }

    private static func validatedISODate(
        year: Int,
        month: Int,
        day: Int,
        minYear: Int,
        maxYear: Int,
        calendar: Calendar
    ) -> String? {
        guard year >= minYear, year <= maxYear,
              (1...12).contains(month),
              (1...31).contains(day)
        else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day
        else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
