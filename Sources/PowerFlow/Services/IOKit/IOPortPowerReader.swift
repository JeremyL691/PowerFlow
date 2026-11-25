import Foundation
import IOKit

// MARK: - IOPort Topology Entry

struct IOPortTopologyEntry: Sendable, Equatable {
    let portKind: PowerPortKind
    let portNumber: Int
    let portLabel: String
    let connectionActive: Bool
    let isWinningPowerSource: Bool
    let winningMaxPowerMW: Int?
    let winningMaxCurrentMA: Int?
    let standbyMaxPowerMW: Int?
    let sopVendorID: Int?
    let sopProductID: Int?
    let usbProductName: String?
    let usbManufacturer: String?
    let isDisplayPortActive: Bool
    let activeTransports: [String]
    let cableType: String?

    init(
        portKind: PowerPortKind,
        portNumber: Int,
        portLabel: String,
        connectionActive: Bool,
        isWinningPowerSource: Bool,
        winningMaxPowerMW: Int?,
        winningMaxCurrentMA: Int?,
        standbyMaxPowerMW: Int?,
        sopVendorID: Int?,
        sopProductID: Int?,
        usbProductName: String?,
        usbManufacturer: String?,
        isDisplayPortActive: Bool,
        activeTransports: [String] = [],
        cableType: String? = nil
    ) {
        self.portKind = portKind
        self.portNumber = portNumber
        self.portLabel = portLabel
        self.connectionActive = connectionActive
        self.isWinningPowerSource = isWinningPowerSource
        self.winningMaxPowerMW = winningMaxPowerMW
        self.winningMaxCurrentMA = winningMaxCurrentMA
        self.standbyMaxPowerMW = standbyMaxPowerMW
        self.sopVendorID = sopVendorID
        self.sopProductID = sopProductID
        self.usbProductName = usbProductName
        self.usbManufacturer = usbManufacturer
        self.isDisplayPortActive = isDisplayPortActive
        self.activeTransports = activeTransports
        self.cableType = cableType
    }
}

// MARK: - Provider Protocol

protocol IOPortReadingProvider: Sendable {
    func readPortTopology() -> [IOPortTopologyEntry]
}

// MARK: - IOPort Power Reader

final class IOPortPowerReader: IOPortReadingProvider, @unchecked Sendable {
    init() {}

    func readPortTopology() -> [IOPortTopologyEntry] {
        guard let matching = IOServiceMatching("IOPort") else { return [] }
        var iterator: io_iterator_t = IO_OBJECT_NULL
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS, iterator != IO_OBJECT_NULL else { return [] }
        defer { IOObjectRelease(iterator) }

        var entries: [IOPortTopologyEntry] = []
        while true {
            let portService = IOIteratorNext(iterator)
            guard portService != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(portService) }

            let className = IOKitHelpers.copyClassName(entry: portService)
            guard Self.isCandidatePowerPortClass(className) else {
                continue
            }
            guard let portProps = IOKitHelpers.copyRegistryProperties(entry: portService) else {
                continue
            }

            guard Self.resolvePortKind(className: className, properties: portProps) != .unknown else {
                continue
            }

            var children = CollectedChildren()
            Self.collectChildren(of: portService, depth: 0, maxDepth: 3, into: &children)

            if let entry = Self.parsePortEntry(
                portProperties: portProps,
                className: className,
                powerSources: children.powerSources,
                ccStates: children.ccStates,
                sopComponents: children.sopComponents,
                sopPrimeComponents: children.sopPrimeComponents,
                usbStates: children.usbStates,
                displayPortStates: children.displayPortStates
            ) {
                entries.append(entry)
            }
        }

        return entries.sorted { lhs, rhs in
            if lhs.portKind != rhs.portKind {
                return Self.sortOrder(for: lhs.portKind) < Self.sortOrder(for: rhs.portKind)
            }
            return lhs.portNumber < rhs.portNumber
        }
    }

    // MARK: - Pure Parsers (Unit Testable)

    static func parsePortEntry(
        portProperties: [String: Any],
        className: String? = nil,
        powerSources: [[String: Any]] = [],
        ccStates: [[String: Any]] = [],
        sopComponents: [[String: Any]] = [],
        sopPrimeComponents: [[String: Any]] = [],
        usbStates: [[String: Any]] = [],
        displayPortStates: [[String: Any]] = []
    ) -> IOPortTopologyEntry? {
        let effectiveClass = className ?? IOKitHelpers.extractString(portProperties, key: "IOClass")
        let portKind = resolvePortKind(className: effectiveClass, properties: portProperties)
        guard portKind != .unknown else { return nil }

        let portNumber = IOKitHelpers.extractInt(portProperties, key: "PortNumber") ?? 1
        let connectionActive = IOKitHelpers.extractBool(portProperties, key: "ConnectionActive") ?? false
        let portLabel = makePortLabel(kind: portKind, number: portNumber)

        // Power Source Analysis (Winning vs Standby)
        var isWinningPowerSource = false
        var winningMaxPowerMW: Int?
        var winningMaxCurrentMA: Int?
        var maxStandbyPowerMW: Int?

        for source in powerSources {
            if let winning = IOKitHelpers.extractDict(source, key: "WinningPowerSourceOption") {
                isWinningPowerSource = true
                if let powerMW = IOKitHelpers.extractInt(winning, key: "Max Power (mW)"), powerMW > 0 {
                    winningMaxPowerMW = max(winningMaxPowerMW ?? 0, powerMW)
                }
                if let currentMA = IOKitHelpers.extractInt(winning, key: "Max Current (mA)"), currentMA > 0 {
                    winningMaxCurrentMA = max(winningMaxCurrentMA ?? 0, currentMA)
                }
            }

            if let options = IOKitHelpers.extractDictArray(source, key: "PowerSourceOptions") {
                for option in options {
                    if let powerMW = IOKitHelpers.extractInt(option, key: "Max Power (mW)"), powerMW > 0 {
                        maxStandbyPowerMW = max(maxStandbyPowerMW ?? 0, powerMW)
                    }
                }
            }
        }

        let standbyMaxPowerMW: Int? = isWinningPowerSource ? nil : maxStandbyPowerMW

        // CC / SOP VID & PID
        let (sopVendorID, sopProductID) = parseSOPIdentifiers(
            ccStates: ccStates,
            sopComponents: sopComponents
        )

        // DisplayPort Status, Product Name & Manufacturer Fallback (prefer Active == true nodes)
        let (isDisplayPortActive, displayProductName, displayManufacturer) = parseDisplayPortIdentity(
            displayPortStates: displayPortStates
        )

        // USB4 / Thunderbolt / USB3 / USB2 Product & Manufacturer
        let (rawUSBProduct, rawUSBManufacturer) = parseUSBIdentity(usbStates: usbStates)
        let usbProductName = rawUSBProduct ?? (isDisplayPortActive ? displayProductName : nil)
        let usbManufacturer = rawUSBManufacturer ?? (isDisplayPortActive ? displayManufacturer : nil)

        // Active Transports & Cable Type (SOP')
        let activeTransports = parseActiveTransports(portProperties: portProperties)
        let cableType = parseCableType(sopPrimeComponents: sopPrimeComponents)

        return IOPortTopologyEntry(
            portKind: portKind,
            portNumber: portNumber,
            portLabel: portLabel,
            connectionActive: connectionActive,
            isWinningPowerSource: isWinningPowerSource,
            winningMaxPowerMW: winningMaxPowerMW,
            winningMaxCurrentMA: winningMaxCurrentMA,
            standbyMaxPowerMW: standbyMaxPowerMW,
            sopVendorID: sopVendorID,
            sopProductID: sopProductID,
            usbProductName: usbProductName,
            usbManufacturer: usbManufacturer,
            isDisplayPortActive: isDisplayPortActive,
            activeTransports: activeTransports,
            cableType: cableType
        )
    }

    /// Pre-filters IORegistry `IOPort` subclasses before copying full property dictionaries so
    /// non-power ports (e.g. `AppleHDMIPortController`, `AppleSDXCSlot`) are skipped cheaply.
    static func isCandidatePowerPortClass(_ className: String?) -> Bool {
        guard let className else { return true }
        if className == "AppleHPMInterfaceType10" || className == "AppleHPMInterfaceType11" {
            return true
        }
        if className == "IOPort" || className.hasPrefix("AppleHPM") {
            return true
        }
        let lowered = className.lowercased()
        return lowered.contains("usbc")
            || lowered.contains("usb-c")
            || lowered.contains("typec")
            || lowered.contains("magsafe")
    }

    static func resolvePortKind(className: String?, properties: [String: Any]) -> PowerPortKind {
        if let className {
            if className == "AppleHPMInterfaceType11" {
                return .magSafe
            }
            if className == "AppleHPMInterfaceType10" {
                return .usbC
            }
        }

        if let description = IOKitHelpers.extractString(properties, key: "PortTypeDescription")?.lowercased() {
            if description.contains("magsafe") {
                return .magSafe
            }
            if description.contains("usb-c") || description.contains("usbc") {
                return .usbC
            }
        }

        if let portType = IOKitHelpers.extractInt(properties, key: "PortType") {
            if portType == 17 {
                return .magSafe
            }
            if portType == 2 {
                return .usbC
            }
        }

        return .unknown
    }

    static func makePortLabel(kind: PowerPortKind, number: Int) -> String {
        switch kind {
        case .magSafe:
            return "MagSafe 3"
        case .usbC:
            return "USB-C \(number)"
        case .unknown:
            return "Port \(number)"
        }
    }

    // MARK: - Child Extraction Helpers

    private struct CollectedChildren {
        var powerSources: [[String: Any]] = []
        var ccStates: [[String: Any]] = []
        var sopComponents: [[String: Any]] = []
        var sopPrimeComponents: [[String: Any]] = []
        var usbStates: [[String: Any]] = []
        var displayPortStates: [[String: Any]] = []
    }

    private static func collectChildren(
        of parent: io_registry_entry_t,
        depth: Int,
        maxDepth: Int,
        into collection: inout CollectedChildren
    ) {
        guard depth < maxDepth else { return }

        var childIterator: io_iterator_t = IO_OBJECT_NULL
        let kr = IORegistryEntryGetChildIterator(parent, kIOServicePlane, &childIterator)
        guard kr == KERN_SUCCESS, childIterator != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(childIterator) }

        while true {
            let child = IOIteratorNext(childIterator)
            guard child != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(child) }

            let childClass = IOKitHelpers.copyClassName(entry: child) ?? ""

            switch childClass {
            case "IOPortFeaturePowerSource":
                if let props = IOKitHelpers.copyRegistryProperties(entry: child) {
                    collection.powerSources.append(props)
                }
            case "IOPortTransportStateCC":
                if let props = IOKitHelpers.copyRegistryProperties(entry: child) {
                    collection.ccStates.append(props)
                }
                collectChildren(of: child, depth: depth + 1, maxDepth: maxDepth, into: &collection)
            case "IOPortTransportComponentCCUSBPDSOP":
                if let props = IOKitHelpers.copyRegistryProperties(entry: child) {
                    collection.sopComponents.append(props)
                }
            case "IOPortTransportComponentCCUSBPDSOPp":
                if let props = IOKitHelpers.copyRegistryProperties(entry: child) {
                    collection.sopPrimeComponents.append(props)
                }
            case "IOPortTransportStateUSB4", "IOPortTransportStateThunderbolt",
                 "IOPortTransportStateUSB3", "IOPortTransportStateUSB2":
                if let props = IOKitHelpers.copyRegistryProperties(entry: child) {
                    collection.usbStates.append(props)
                }
            case "IOPortTransportStateDisplayPort":
                if let props = IOKitHelpers.copyRegistryProperties(entry: child) {
                    collection.displayPortStates.append(props)
                }
            case "IOPortFeaturePowerIn":
                collectChildren(of: child, depth: depth + 1, maxDepth: maxDepth, into: &collection)
            default:
                break
            }
        }
    }

    private static func parseActiveTransports(portProperties: [String: Any]) -> [String] {
        if let strings = portProperties["TransportsActive"] as? [String] {
            return strings.compactMap { IOKitHelpers.extractString($0) }
        }
        if let array = portProperties["TransportsActive"] as? [Any] {
            return array.compactMap { IOKitHelpers.extractString($0) }
        }
        if let set = portProperties["TransportsActive"] as? NSSet {
            return set.allObjects.compactMap { IOKitHelpers.extractString($0) }.sorted()
        }
        return []
    }

    private static func parseCableType(sopPrimeComponents: [[String: Any]]) -> String? {
        for sopPrime in sopPrimeComponents {
            let meta = IOKitHelpers.extractDict(sopPrime, key: "Metadata")
            if let description = IOKitHelpers.extractString(sopPrime, key: "Product Type Description")
                ?? meta.flatMap({ IOKitHelpers.extractString($0, key: "Product Type Description") })
            {
                return description
            }
        }
        return nil
    }

    private static func parseSOPIdentifiers(
        ccStates: [[String: Any]],
        sopComponents: [[String: Any]]
    ) -> (vendorID: Int?, productID: Int?) {
        var vendorID: Int?
        var productID: Int?

        for cc in ccStates {
            let meta = IOKitHelpers.extractDict(cc, key: "Metadata")
            if vendorID == nil {
                vendorID = IOKitHelpers.extractInt(cc, key: "Vendor ID (SOP)")
                    ?? meta.flatMap { IOKitHelpers.extractInt($0, key: "Vendor ID (SOP)") }
                    ?? IOKitHelpers.extractInt(cc, key: "Vendor ID (SOP1)")
                    ?? meta.flatMap { IOKitHelpers.extractInt($0, key: "Vendor ID (SOP1)") }
            }
            if productID == nil {
                productID = IOKitHelpers.extractInt(cc, key: "Product ID (SOP)")
                    ?? meta.flatMap { IOKitHelpers.extractInt($0, key: "Product ID (SOP)") }
                    ?? IOKitHelpers.extractInt(cc, key: "Product ID (SOP1)")
                    ?? meta.flatMap { IOKitHelpers.extractInt($0, key: "Product ID (SOP1)") }
            }
        }

        for sop in sopComponents {
            let meta = IOKitHelpers.extractDict(sop, key: "Metadata")
            if vendorID == nil {
                vendorID = IOKitHelpers.extractInt(sop, key: "Vendor ID")
                    ?? meta.flatMap { IOKitHelpers.extractInt($0, key: "Vendor ID") }
            }
            if productID == nil {
                productID = IOKitHelpers.extractInt(sop, key: "Product ID")
                    ?? meta.flatMap { IOKitHelpers.extractInt($0, key: "Product ID") }
            }
        }

        if let v = vendorID, v <= 0 { vendorID = nil }
        if let p = productID, p <= 0 { productID = nil }
        return (vendorID, productID)
    }

    private static func parseDisplayPortIdentity(
        displayPortStates: [[String: Any]]
    ) -> (isActive: Bool, productName: String?, manufacturer: String?) {
        let activeStates = displayPortStates.filter {
            IOKitHelpers.extractBool($0, key: "Active") == true
        }
        let isActive = !activeStates.isEmpty
        let ordered = activeStates + displayPortStates.filter {
            IOKitHelpers.extractBool($0, key: "Active") != true
        }

        var productName: String?
        var manufacturer: String?
        for dp in ordered {
            let meta = IOKitHelpers.extractDict(dp, key: "Metadata")
            if productName == nil {
                productName = IOKitHelpers.extractString(dp, key: "ProductName")
                    ?? IOKitHelpers.extractString(dp, key: "Product")
                    ?? meta.flatMap { IOKitHelpers.extractString($0, key: "ProductName") }
                    ?? meta.flatMap { IOKitHelpers.extractString($0, key: "Product") }
            }
            if manufacturer == nil {
                manufacturer = IOKitHelpers.extractString(dp, key: "ManufacturerName")
                    ?? IOKitHelpers.extractString(dp, key: "Manufacturer")
                    ?? meta.flatMap { IOKitHelpers.extractString($0, key: "ManufacturerName") }
                    ?? meta.flatMap { IOKitHelpers.extractString($0, key: "Manufacturer") }
            }
            if productName != nil && manufacturer != nil {
                break
            }
        }
        return (isActive, productName, manufacturer)
    }

    private static func parseUSBIdentity(
        usbStates: [[String: Any]]
    ) -> (product: String?, manufacturer: String?) {
        // Prioritize active USB states first (e.g. USB4/Thunderbolt/USB3 active over inactive USB2).
        let ordered = usbStates.sorted { lhs, rhs in
            let lhsActive = IOKitHelpers.extractBool(lhs, key: "Active") ?? false
            let rhsActive = IOKitHelpers.extractBool(rhs, key: "Active") ?? false
            if lhsActive != rhsActive { return lhsActive }
            let lhsGen = IOKitHelpers.extractInt(lhs, key: "Generation") ?? 0
            let rhsGen = IOKitHelpers.extractInt(rhs, key: "Generation") ?? 0
            return lhsGen > rhsGen
        }

        var product: String?
        var manufacturer: String?

        for usb in ordered {
            let meta = IOKitHelpers.extractDict(usb, key: "Metadata")
            if product == nil {
                product = IOKitHelpers.extractString(usb, key: "Product")
                    ?? IOKitHelpers.extractString(usb, key: "ProductName")
                    ?? meta.flatMap { IOKitHelpers.extractString($0, key: "Product") }
                    ?? meta.flatMap { IOKitHelpers.extractString($0, key: "ProductName") }
            }
            if manufacturer == nil {
                manufacturer = IOKitHelpers.extractString(usb, key: "Manufacturer")
                    ?? IOKitHelpers.extractString(usb, key: "ManufacturerName")
                    ?? meta.flatMap { IOKitHelpers.extractString($0, key: "Manufacturer") }
                    ?? meta.flatMap { IOKitHelpers.extractString($0, key: "ManufacturerName") }
            }
            if product != nil && manufacturer != nil {
                break
            }
        }

        return (product, manufacturer)
    }

    private static func sortOrder(for kind: PowerPortKind) -> Int {
        switch kind {
        case .magSafe: return 0
        case .usbC: return 1
        case .unknown: return 2
        }
    }
}
