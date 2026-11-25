import Foundation

enum PowerFormatters {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let maxSafeIntDouble = Double(Int.max).nextDown

    private static func normalizeZero(_ value: Double, decimals: Int) -> Double {
        let threshold = pow(10.0, -Double(decimals)) * 0.5
        return abs(value) < threshold ? 0.0 : value
    }

    private static func formatDecimal(_ value: Double, decimals: Int, signed: Bool = false) -> String {
        let clean = normalizeZero(value, decimals: decimals)
        if clean == 0 {
            return "0"
        }
        let format = signed ? "%+.\(decimals)f" : "%.\(decimals)f"
        return String(format: format, locale: posixLocale, clean)
    }

    static func watts(_ value: Double, decimals: Int = 2, signed: Bool = false) -> String {
        guard value.isFinite else { return "—" }
        let clean = normalizeZero(value, decimals: decimals)
        if clean == 0 {
            return "0 W"
        }
        return "\(formatDecimal(clean, decimals: decimals, signed: signed)) W"
    }

    static func compactWatts(_ value: Double) -> String {
        guard value.isFinite else { return "—W" }
        let magnitude = abs(value)
        if magnitude < 0.05 {
            return "0W"
        }
        if magnitude < 10.0 {
            return String(format: "%.1fW", locale: posixLocale, magnitude)
        }
        let clamped = min(magnitude.rounded(), maxSafeIntDouble)
        return "\(Int(clamped))W"
    }

    static func wattHours(_ wh: Double?, decimals: Int = 1) -> String {
        guard let wh, wh.isFinite, wh >= 0 else { return "—" }
        let clean = normalizeZero(wh, decimals: decimals)
        if clean == 0 {
            return "0 Wh"
        }
        return "\(formatDecimal(clean, decimals: decimals)) Wh"
    }

    static func amps(_ value: Double, decimals: Int = 2, signed: Bool = false) -> String {
        guard value.isFinite else { return "—" }
        let clean = normalizeZero(value, decimals: decimals)
        if clean == 0 {
            return "0 A"
        }
        return "\(formatDecimal(clean, decimals: decimals, signed: signed)) A"
    }

    static func volts(_ value: Double, decimals: Int = 2) -> String {
        guard value.isFinite else { return "—" }
        let clean = normalizeZero(value, decimals: decimals)
        if clean == 0 {
            return "0 V"
        }
        return String(format: "%.\(decimals)f V", locale: posixLocale, clean)
    }

    static func rpm(_ rpm: Double) -> String {
        guard rpm.isFinite, rpm >= 0 else { return "—" }
        let clamped = min(rpm.rounded(), maxSafeIntDouble)
        return "\(integerGrouped(Int(clamped))) RPM"
    }

    static func capacityMAh(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "—" }
        return "\(integerGrouped(value)) mAh"
    }

    static func percent(_ value: Int) -> String {
        "\(value)%"
    }

    static func precisePercent(_ value: Double?, decimals: Int = 1) -> String {
        guard let value, value.isFinite else { return "—" }
        let clean = normalizeZero(value, decimals: decimals)
        return String(format: "%.\(decimals)f%%", locale: posixLocale, clean)
    }

    static func temperatureValue(_ celsius: Double, unit: TemperatureUnit) -> Double {
        switch unit {
        case .celsius:
            return celsius
        case .fahrenheit:
            return celsius * 9.0 / 5.0 + 32.0
        }
    }

    static func temperature(_ celsius: Double?, unit: TemperatureUnit) -> String {
        guard let celsius, celsius.isFinite else { return "—" }
        let converted = temperatureValue(celsius, unit: unit)
        let suffix = unit == .celsius ? "°C" : "°F"
        return String(format: "%.1f %@", locale: posixLocale, converted, suffix)
    }

    static func duration(minutes: Int?, language: AppLanguage = .system) -> String {
        guard let minutes, minutes > 0 else { return "—" }
        let hours = minutes / 60
        let mins = minutes % 60
        let resolved = L10n.resolvedLanguage(for: language)

        switch resolved {
        case .simplifiedChinese:
            if hours > 0 && mins > 0 {
                return "\(hours)小时\(mins)分"
            }
            if hours > 0 {
                return "\(hours)小时"
            }
            return "\(mins)分钟"
        case .english, .system:
            if hours > 0 && mins > 0 {
                return "\(hours)h \(mins)m"
            }
            if hours > 0 {
                return "\(hours)h"
            }
            return "\(mins)m"
        }
    }

    static func cycleCount(_ count: Int?, designLimit: Int?) -> String {
        guard let count, count >= 0 else { return "—" }
        if let designLimit, designLimit > 0 {
            return "\(integerGrouped(count)) / \(integerGrouped(designLimit))"
        }
        return integerGrouped(count)
    }

    static func maskSerial(_ serial: String?, masked: Bool) -> String {
        guard let serial else { return "—" }
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        guard masked else { return trimmed }
        if trimmed.count <= 5 {
            return "••••"
        }
        let prefix = trimmed.prefix(3)
        let suffix = trimmed.suffix(2)
        return "\(prefix)••••\(suffix)"
    }

    static func integerGrouped(_ value: Int) -> String {
        let isNegative = value < 0
        let digits = String(value.magnitude)
        var result = ""
        result.reserveCapacity(digits.count + digits.count / 3 + 1)
        for (index, char) in digits.reversed().enumerated() {
            if index > 0 && index % 3 == 0 {
                result.append(",")
            }
            result.append(char)
        }
        let grouped = String(result.reversed())
        return isNegative ? "-\(grouped)" : grouped
    }
}
