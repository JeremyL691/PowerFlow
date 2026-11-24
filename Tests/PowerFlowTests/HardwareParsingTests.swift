import Foundation
import XCTest
@testable import PowerFlow

final class HardwareParsingTests: XCTestCase {
    // MARK: - IOKitHelpers UInt64 Two's-Complement & Manufacture Date

    func testExtractIntHandlesUInt64NegativeBitPattern() {
        let negative1500 = UInt64(bitPattern: -1500) // 18446744073709550116
        let negativeDischarge = UInt64(bitPattern: -6950)
        let dict: [String: Any] = [
            "InstantAmperage": NSNumber(value: negative1500),
            "RawUInt64": negativeDischarge,
            "BatteryPower": NSNumber(value: UInt64(bitPattern: -18_420)),
            "Positive": NSNumber(value: 3390),
            "FlagBool": NSNumber(value: true)
        ]

        XCTAssertEqual(IOKitHelpers.extractInt(dict, key: "InstantAmperage"), -1500)
        XCTAssertEqual(IOKitHelpers.extractInt(dict, key: "RawUInt64"), -6950)
        XCTAssertEqual(IOKitHelpers.extractInt(dict, key: "BatteryPower"), -18_420)
        XCTAssertEqual(IOKitHelpers.extractInt(dict, key: "Positive"), 3390)
        XCTAssertNil(IOKitHelpers.extractInt(dict, key: "FlagBool"))
    }

    func testFormatBatteryManufactureDateAppleSiliconAndSMBus() {
        let reference = Date(timeIntervalSince1970: 1_795_488_955) // 2026-11-24 UTC

        // Real Apple Silicon gas gauge value: 0x373039303233 -> LE ASCII "320907" -> 1992+32 = 2024-09-07
        XCTAssertEqual(
            IOKitHelpers.formatBatteryManufactureDate(60_680_257_417_779, relativeTo: reference),
            "2024-09-07"
        )

        // Classic 16-bit SMBus packed date: 2023-05-18 -> ((2023 - 1980) << 9) | (5 << 5) | 18
        let smbus = ((2023 - 1980) << 9) | (5 << 5) | 18
        XCTAssertEqual(
            IOKitHelpers.formatBatteryManufactureDate(smbus, relativeTo: reference),
            "2023-05-18"
        )

        XCTAssertNil(IOKitHelpers.formatBatteryManufactureDate(0, relativeTo: reference))
        XCTAssertNil(IOKitHelpers.formatBatteryManufactureDate(-1, relativeTo: reference))
    }

    // MARK: - SmartBattery Nested BatteryData Fallback (macOS 27)

    func testSmartBatteryNestedBatteryDataFallbackAndTemperature() {
        let topProperties: [String: Any] = [
            "CurrentCapacity": 100,
            "MaxCapacity": 100,
            "ExternalConnected": true,
            "IsCharging": false,
            "FullyCharged": true,
            "AtCriticalLevel": false,
            "Voltage": 13_104,
            "InstantAmperage": 0,
            "CycleCount": 35,
            "DesignCycleCount9C": 1000,
            "TimeRemaining": 65_535,
            "Serial": "BATT0000SAMPLE0001",
            "DeviceName": "bq40z651",
            "ChargerData": [
                "NotChargingReason": 4_194_305,
                "SlowChargingReason": 0
            ],
            "BatteryData": [
                "DesignCapacity": 6249,
                "AppleRawMaxCapacity": 6132,
                "FullChargeCapacity": 6132,
                "NominalChargeCapacity": 6284,
                "AppleRawCurrentCapacity": 5906,
                "RemainingCapacity": 5906
            ],
            "PowerTelemetryData": [
                "SystemPowerIn": 31_920,
                "SystemLoad": 33_190,
                "BatteryPower": 0,
                "SystemVoltageIn": 20_250,
                "SystemCurrentIn": 1590,
                "AdapterEfficiencyLoss": 340
            ]
        ]

        let packProperties: [String: Any] = [
            "BatteryData": [
                "Temperature": 3769, // 37.69 °C in centi-Celsius
                "StateOfCharge": 98,
                "DailyMinSoc": 80,
                "DailyMaxSoc": 100,
                "PermanentFailureStatus": 0,
                "ManufactureDate": 60_680_257_417_779
            ]
        ]

        let reading = SmartBatteryReader.parseSmartBattery(
            properties: topProperties,
            packProperties: packProperties,
            cellTopology: nil,
            iopsCondition: .normal,
            referenceDate: Date(timeIntervalSince1970: 1_795_488_955)
        )

        XCTAssertEqual(reading.designCapacityMAh, 6249)
        XCTAssertEqual(reading.rawMaxCapacityMAh, 6132)
        XCTAssertEqual(reading.nominalCapacityMAh, 6284)
        XCTAssertEqual(reading.currentChargeMAh, 5906)
        XCTAssertEqual(reading.stateOfCharge, 98)
        XCTAssertEqual(reading.dailyMinSoc, 80)
        XCTAssertEqual(reading.dailyMaxSoc, 100)
        XCTAssertNotNil(reading.temperatureC)
        XCTAssertEqual(reading.temperatureC ?? 0, 37.69, accuracy: 0.001)
        XCTAssertEqual(reading.condition, .normal)
        XCTAssertEqual(reading.cycleCount, 35)
        XCTAssertEqual(reading.designCycleCount, 1000)
        XCTAssertNil(reading.timeRemainingMinutes) // 65535 normalized to nil
        XCTAssertEqual(reading.manufactureDate, "2024-09-07")
        XCTAssertEqual(reading.telemetrySystemPowerInMW, 31_920)
        XCTAssertEqual(reading.telemetrySystemLoadMW, 33_190)
        XCTAssertEqual(reading.notChargingReason, 4_194_305)
    }

    func testSmartBatteryCentiKelvinTemperatureConversion() {
        let props: [String: Any] = [
            "Temperature": 31_084, // 310.84 K -> 37.69 °C
            "PermanentFailureStatus": 1
        ]
        let reading = SmartBatteryReader.parseSmartBattery(properties: props)
        XCTAssertEqual(reading.temperatureC ?? 0, 37.69, accuracy: 0.01)
        XCTAssertEqual(reading.condition, .serviceRecommended)
    }

    // MARK: - PowerOutDetails & FedDetails Parsing

    func testPowerOutDetailsAndFedDetailsParsing() {
        let props: [String: Any] = [
            "AdapterDetails": [
                "Name": "70W USB-C Power Adapter ",
                "Manufacturer": "Apple Inc.",
                "SerialString": "ADPT0000SAMPLE0001",
                "Model": "0x701C",
                "Description": "pd charger",
                "Watts": 68,
                "AdapterVoltage": 20_000,
                "Current": 3390,
                "AdapterID": 28_700
            ],
            "AppleRawAdapterDetails": [
                [
                    "Watts": 8,
                    "AdapterVoltage": 5000,
                    "Current": 1500,
                    "AdapterID": 0
                ],
                [
                    "Name": "70W USB-C Power Adapter ",
                    "Manufacturer": "Apple Inc.",
                    "Watts": 68,
                    "AdapterVoltage": 20_000,
                    "Current": 3390,
                    "AdapterID": 28_700
                ]
            ],
            "PowerOutDetails": [
                [
                    "PortIndex": 2,
                    "Watts": 5592,
                    "FilteredPower": 5592,
                    "Current": 1069,
                    "AdapterVoltage": 5228,
                    "ConfiguredVoltage": 5000,
                    "ConfiguredCurrent": 3000,
                    "PDPowermW": 15_000,
                    "VConnCurrent": 13,
                    "VConnPower": 70
                ],
                [
                    "PortIndex": 3,
                    "Watts": 1778,
                    "FilteredPower": 1835,
                    "Current": 340,
                    "AdapterVoltage": 5219,
                    "ConfiguredVoltage": 5000,
                    "ConfiguredCurrent": 3000,
                    "PDPowermW": 15_000,
                    "VConnCurrent": 10,
                    "VConnPower": 57
                ]
            ],
            "FedDetails": [
                [
                    "FedPortPowerRole": 0,
                    "FedVendorID": 3034,
                    "FedProductID": 21_584,
                    "FedExternalConnected": 1
                ],
                [
                    "FedPortPowerRole": 1,
                    "FedVendorID": 1406,
                    "FedProductID": 8195,
                    "FedExternalConnected": 0
                ]
            ]
        ]

        let reading = SmartBatteryReader.parseSmartBattery(properties: props)

        XCTAssertEqual(reading.activeAdapter?.name, "70W USB-C Power Adapter")
        XCTAssertEqual(reading.activeAdapter?.watts, 68)
        XCTAssertEqual(reading.activeAdapter?.voltageMV, 20_000)
        XCTAssertEqual(reading.activeAdapter?.currentMA, 3390)
        XCTAssertEqual(reading.rawAdapters.count, 2)

        XCTAssertEqual(reading.powerOutDetails.count, 2)
        XCTAssertEqual(reading.powerOutDetails[0].portIndex, 2)
        XCTAssertEqual(reading.powerOutDetails[0].wattsMW, 5592)
        XCTAssertEqual(reading.powerOutDetails[0].currentMA, 1069)
        XCTAssertEqual(reading.powerOutDetails[0].voltageMV, 5228)
        XCTAssertEqual(reading.powerOutDetails[0].pdPowerMW, 15_000)
        XCTAssertEqual(reading.powerOutDetails[0].vconnPowerMW, 70)

        XCTAssertEqual(reading.fedDetails.count, 2)
        XCTAssertEqual(reading.fedDetails[0].vendorID, 3034)
        XCTAssertEqual(reading.fedDetails[0].productID, 21_584)
        XCTAssertTrue(reading.fedDetails[0].externalConnected)
        XCTAssertEqual(reading.fedDetails[1].portPowerRole, 1)
        XCTAssertFalse(reading.fedDetails[1].externalConnected)
    }

    // MARK: - Bank Cell Topology Parsing

    func testBankCellTopologyParsing() {
        let banks: [[String: Any]] = [
            ["BankID": 2, "BatteryData": ["CellVoltage": 4369, "Qmax": 6440]],
            ["BankID": 0, "BatteryData": ["CellVoltage": 4368, "Qmax": 6461]],
            ["BankID": 1, "BatteryData": ["CellVoltage": 4368, "Qmax": 6426]]
        ]
        let cells: [[String: Any]] = [
            ["BankID": 0, "CellID": 0], ["BankID": 0, "CellID": 1],
            ["BankID": 1, "CellID": 0], ["BankID": 1, "CellID": 1],
            ["BankID": 2, "CellID": 0], ["BankID": 2, "CellID": 1]
        ]

        let topology = SmartBatteryReader.parseBankCellTopology(
            bankProperties: banks,
            cellProperties: cells
        )

        XCTAssertEqual(topology?.seriesCount, 3)
        XCTAssertEqual(topology?.parallelCount, 2)
        XCTAssertEqual(topology?.label, "3S2P")
        XCTAssertEqual(topology?.voltagesMV, [4368, 4368, 4369])
        XCTAssertEqual(topology?.qmaxMAh, [6461, 6426, 6440])
        XCTAssertEqual(topology?.voltageSpreadMV, 1)
    }

    // MARK: - SMCValue Decoding & SMCReader Sanitization

    func testSMCKeyDataLayoutSizeIs80Bytes() {
        XCTAssertEqual(MemoryLayout<SMCKeyData>.size, 80)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.stride, 80)
    }

    func testSMCValueDecodingAllSupportedTypes() {
        // flt (little-endian IEEE 754 float: 31.92)
        let fltBits = Float(31.92).bitPattern
        let fltBytes: [UInt8] = [
            UInt8(fltBits & 0xFF),
            UInt8((fltBits >> 8) & 0xFF),
            UInt8((fltBits >> 16) & 0xFF),
            UInt8((fltBits >> 24) & 0xFF)
        ]
        let fltValue = SMCValue(key: "PDTR", dataSize: 4, dataType: "flt ", bytes: fltBytes)
        XCTAssertEqual(fltValue.floatValue() ?? 0, 31.92, accuracy: 0.001)

        // si16 big-endian (-1850)
        let negBits = UInt16(bitPattern: Int16(-1850))
        let si16Value = SMCValue(
            key: "B0AC",
            dataSize: 2,
            dataType: "si16",
            bytes: [UInt8(negBits >> 8), UInt8(negBits & 0xFF)]
        )
        XCTAssertEqual(si16Value.floatValue(), -1850.0)

        // ui16 big-endian (13104)
        let ui16Value = SMCValue(
            key: "B0AV",
            dataSize: 2,
            dataType: "ui16",
            bytes: [UInt8(13_104 >> 8), UInt8(13_104 & 0xFF)]
        )
        XCTAssertEqual(ui16Value.floatValue(), 13_104.0)

        // sp78 signed fixed-point (-12.5 -> -3200 / 256)
        let sp78Raw = UInt16(bitPattern: Int16(-3200))
        let sp78Value = SMCValue(
            key: "TB0T",
            dataSize: 2,
            dataType: "sp78",
            bytes: [UInt8(sp78Raw >> 8), UInt8(sp78Raw & 0xFF)]
        )
        XCTAssertEqual(sp78Value.floatValue() ?? 0, -12.5, accuracy: 0.0001)

        // fp88 unsigned fixed-point (37.5 -> 9600 / 256)
        let fp88Raw = UInt16(9600)
        let fp88Value = SMCValue(
            key: "TB0T",
            dataSize: 2,
            dataType: "fp88",
            bytes: [UInt8(fp88Raw >> 8), UInt8(fp88Raw & 0xFF)]
        )
        XCTAssertEqual(fp88Value.floatValue() ?? 0, 37.5, accuracy: 0.0001)

        // fpe2 unsigned fixed-point (2500.25 -> 10001 / 4)
        let fpe2Raw = UInt16(10_001)
        let fpe2Value = SMCValue(
            key: "F0Ac",
            dataSize: 2,
            dataType: "fpe2",
            bytes: [UInt8(fpe2Raw >> 8), UInt8(fpe2Raw & 0xFF)]
        )
        XCTAssertEqual(fpe2Value.floatValue() ?? 0, 2500.25, accuracy: 0.0001)

        // flag
        XCTAssertEqual(SMCValue(key: "TEST", dataSize: 1, dataType: "flag", bytes: [1]).floatValue(), 1.0)
        XCTAssertEqual(SMCValue(key: "TEST", dataSize: 1, dataType: "flag", bytes: [0]).floatValue(), 0.0)

        // stringValue
        let strVal = SMCValue(key: "REV ", dataSize: 6, dataType: "ch8*", bytes: Array("Apple\0".utf8))
        XCTAssertEqual(strVal.stringValue(), "Apple")

        // NaN rejected
        let nanBits = Float.nan.bitPattern
        let nanValue = SMCValue(
            key: "PDTR",
            dataSize: 4,
            dataType: "flt ",
            bytes: [
                UInt8(nanBits & 0xFF),
                UInt8((nanBits >> 8) & 0xFF),
                UInt8((nanBits >> 16) & 0xFF),
                UInt8((nanBits >> 24) & 0xFF)
            ]
        )
        XCTAssertNil(nanValue.floatValue())
    }

    func testSMCReaderSanitizesOutOfRangeAndConvertsMilliUnits() {
        let mock = MockSMCKeyReader(values: [
            "PDTR": makeFloatSMCValue(key: "PDTR", value: 31.92),
            "PSTR": makeFloatSMCValue(key: "PSTR", value: 999.0), // out of range (> 400W)
            "PPBR": makeFloatSMCValue(key: "PPBR", value: -14.5),
            "VD0R": makeFloatSMCValue(key: "VD0R", value: 20.25),
            "ID0R": makeFloatSMCValue(key: "ID0R", value: 1.59),
            "B0AV": SMCValue(
                key: "B0AV",
                dataSize: 2,
                dataType: "ui16",
                bytes: [UInt8(13_104 >> 8), UInt8(13_104 & 0xFF)]
            ),
            "B0AC": {
                let raw = UInt16(bitPattern: Int16(-1250))
                return SMCValue(key: "B0AC", dataSize: 2, dataType: "si16", bytes: [UInt8(raw >> 8), UInt8(raw & 0xFF)])
            }(),
            "TB0T": makeFloatSMCValue(key: "TB0T", value: 37.6),
            "B0CT": SMCValue(key: "B0CT", dataSize: 2, dataType: "ui16", bytes: [0, 35])
        ])

        let reader = SMCReader(keyReader: mock)
        let sample = reader.readSample(full: true)

        XCTAssertEqual(sample.deliveryRateW ?? 0, 31.92, accuracy: 0.01)
        XCTAssertNil(sample.systemTotalW)
        XCTAssertEqual(sample.batteryRateW ?? 0, -14.5, accuracy: 0.01)
        XCTAssertEqual(sample.adapterInputVoltageV ?? 0, 20.25, accuracy: 0.01)
        XCTAssertEqual(sample.adapterInputCurrentA ?? 0, 1.59, accuracy: 0.01)
        XCTAssertEqual(sample.batteryVoltageV ?? 0, 13.104, accuracy: 0.001)
        XCTAssertEqual(sample.batteryCurrentA ?? 0, -1.25, accuracy: 0.001)
        XCTAssertEqual(sample.batteryTemperatureC ?? 0, 37.6, accuracy: 0.01)
        XCTAssertEqual(sample.cycleCount, 35)

        // Apple Silicon little-endian SBS battery keys (real hardware layout: [0x30, 0x33] = 13104 mV, [35, 0] = 35 cycles)
        let appleSiliconMock = MockSMCKeyReader(values: [
            "B0AV": SMCValue(key: "B0AV", dataSize: 2, dataType: "ui16", bytes: [0x30, 0x33]),
            "B0AC": {
                let raw = UInt16(bitPattern: Int16(-1500))
                return SMCValue(key: "B0AC", dataSize: 2, dataType: "si16", bytes: [UInt8(raw & 0xFF), UInt8(raw >> 8)])
            }(),
            "B0CT": SMCValue(key: "B0CT", dataSize: 2, dataType: "ui16", bytes: [35, 0])
        ])
        let appleSiliconReader = SMCReader(keyReader: appleSiliconMock, useLittleEndianBatteryKeys: true)
        let armSample = appleSiliconReader.readSample(full: true)
        XCTAssertEqual(armSample.batteryVoltageV ?? 0, 13.104, accuracy: 0.001)
        XCTAssertEqual(armSample.batteryCurrentA ?? 0, -1.5, accuracy: 0.001)
        XCTAssertEqual(armSample.cycleCount, 35)
    }

    // MARK: - IOPort Winning Source & Standby Parsing

    func testIOPortWinningMagSafeAndStandbyUSBCDisplayParsing() {
        let magSafe = IOPortPowerReader.parsePortEntry(
            portProperties: [
                "IOClass": "AppleHPMInterfaceType11",
                "PortTypeDescription": "MagSafe 3",
                "PortType": 17,
                "PortNumber": 1,
                "ConnectionActive": true
            ],
            powerSources: [
                [
                    "PowerSourceName": "USB-PD",
                    "WinningPowerSourceOption": [
                        "Max Power (mW)": 67_800,
                        "Max Current (mA)": 3390,
                        "Voltage (mV)": 20_000
                    ],
                    "PowerSourceOptions": NSSet(array: [
                        ["Max Power (mW)": 67_800, "Max Current (mA)": 3390]
                    ])
                ]
            ],
            ccStates: [
                ["Vendor ID (SOP1)": 1452, "Product ID (SOP1)": 30_720]
            ]
        )

        XCTAssertEqual(magSafe?.portKind, .magSafe)
        XCTAssertEqual(magSafe?.portLabel, "MagSafe 3")
        XCTAssertEqual(magSafe?.connectionActive, true)
        XCTAssertEqual(magSafe?.isWinningPowerSource, true)
        XCTAssertEqual(magSafe?.winningMaxPowerMW, 67_800)
        XCTAssertEqual(magSafe?.winningMaxCurrentMA, 3390)
        XCTAssertNil(magSafe?.standbyMaxPowerMW)
        XCTAssertEqual(magSafe?.sopVendorID, 1452)

        let usbc1 = IOPortPowerReader.parsePortEntry(
            portProperties: [
                "IOClass": "AppleHPMInterfaceType10",
                "PortTypeDescription": "USB-C",
                "PortType": 2,
                "PortNumber": 1,
                "ConnectionActive": true
            ],
            powerSources: [
                [
                    "PowerSourceName": "USB-PD",
                    "PowerSourceOptions": NSSet(array: [
                        ["Max Power (mW)": 15_000, "Max Current (mA)": 3000]
                    ])
                ]
            ],
            ccStates: [
                ["Vendor ID (SOP)": 3034, "Product ID (SOP)": 21_584]
            ],
            usbStates: [
                [
                    "Active": true,
                    "Generation": 1,
                    "Product": "Demo Display Hub",
                    "Manufacturer": "Demo Display Maker"
                ]
            ],
            displayPortStates: [
                [
                    "Active": true,
                    "ProductName": "XG27ACG"
                ]
            ]
        )

        XCTAssertEqual(usbc1?.portKind, .usbC)
        XCTAssertEqual(usbc1?.portNumber, 1)
        XCTAssertEqual(usbc1?.portLabel, "USB-C 1")
        XCTAssertEqual(usbc1?.isWinningPowerSource, false)
        XCTAssertNil(usbc1?.winningMaxPowerMW)
        XCTAssertEqual(usbc1?.standbyMaxPowerMW, 15_000)
        XCTAssertEqual(usbc1?.sopVendorID, 3034)
        XCTAssertEqual(usbc1?.sopProductID, 21_584)
        XCTAssertEqual(usbc1?.usbProductName, "Demo Display Hub")
        XCTAssertEqual(usbc1?.usbManufacturer, "Demo Display Maker")
        XCTAssertEqual(usbc1?.isDisplayPortActive, true)

        // HDMI port should be ignored
        let hdmi = IOPortPowerReader.parsePortEntry(
            portProperties: [
                "IOClass": "AppleHDMIPortController",
                "PortTypeDescription": "HDMI",
                "PortType": 6,
                "PortNumber": 1,
                "ConnectionActive": false
            ]
        )
        XCTAssertNil(hdmi)
    }

    // MARK: - Round 3 Rich Hardware Parsing Tests

    func testUsbHvcMenuPDOsAndAdapterVersionsAndFedRevision() {
        let props: [String: Any] = [
            "AdapterDetails": [
                "Name": "70W USB-C Power Adapter ",
                "Manufacturer": "Apple Inc.",
                "Model": "0x701C",
                "FwVersion": "01030030",
                "HwVersion": "1.0",
                "Watts": 68,
                "AdapterVoltage": 20_000,
                "Current": 3390,
                "AdapterID": 28_700,
                "UsbHvcHvcIndex": 3,
                "UsbHvcMenu": [
                    ["Index": 0, "MaxVoltage": 5000, "MaxCurrent": 2960],
                    ["Index": 1, "MaxVoltage": 9000, "MaxCurrent": 2970],
                    ["Index": 2, "MaxVoltage": 15_000, "MaxCurrent": 2980],
                    ["Index": 3, "MaxVoltage": 20_000, "MaxCurrent": 3390]
                ]
            ],
            "FedDetails": [
                [
                    "FedPortPowerRole": 1,
                    "FedVendorID": 1406,
                    "FedProductID": 8195,
                    "FedExternalConnected": 0,
                    "FedPdSpecRevision": 2
                ]
            ]
        ]

        let reading = SmartBatteryReader.parseSmartBattery(properties: props)
        let adapter = reading.activeAdapter
        XCTAssertEqual(adapter?.firmwareVersion, "01030030")
        XCTAssertEqual(adapter?.hardwareVersion, "1.0")
        XCTAssertEqual(adapter?.activeHvcIndex, 3)
        XCTAssertEqual(adapter?.pdProfiles.count, 4)

        XCTAssertEqual(adapter?.pdProfiles[0].maxVoltageV ?? 0, 5.0, accuracy: 0.001)
        XCTAssertEqual(adapter?.pdProfiles[0].maxCurrentA ?? 0, 2.96, accuracy: 0.001)
        XCTAssertEqual(adapter?.pdProfiles[0].maxWatts ?? 0, 14.8, accuracy: 0.01)
        XCTAssertEqual(adapter?.pdProfiles[0].isActive, false)

        XCTAssertEqual(adapter?.pdProfiles[3].maxVoltageV ?? 0, 20.0, accuracy: 0.001)
        XCTAssertEqual(adapter?.pdProfiles[3].maxCurrentA ?? 0, 3.39, accuracy: 0.001)
        XCTAssertEqual(adapter?.pdProfiles[3].maxWatts ?? 0, 67.8, accuracy: 0.01)
        XCTAssertEqual(adapter?.pdProfiles[3].isActive, true)

        XCTAssertEqual(reading.fedDetails.first?.pdSpecRevision, 2)
    }

    func testLifetimeDataParsingWithSignedUInt64DischargeAndTenthsTemp() {
        let negativeDischarge = UInt64(bitPattern: -6950) // 18446744073709544666
        let topProperties: [String: Any] = [
            "PowerTelemetryData": [
                "WallEnergyEstimate": 5877,
                "SystemPowerIn": 19_730
            ]
        ]
        let packProperties: [String: Any] = [
            "BatteryData": [
                "LifetimeData": [
                    "TotalOperatingTime": 19_148,
                    "MinimumTemperature": 7,
                    "AverageTemperature": 225,
                    "MaximumTemperature": 40,
                    "MinimumPackVoltage": 10_694,
                    "MaximumPackVoltage": 13_300,
                    "MaximumChargeCurrent": 6680,
                    "MaximumDischargeCurrent": NSNumber(value: negativeDischarge)
                ]
            ]
        ]

        let reading = SmartBatteryReader.parseSmartBattery(
            properties: topProperties,
            packProperties: packProperties
        )

        XCTAssertEqual(reading.telemetryWallEnergyEstimateMW, 5877)
        let lifetime = reading.lifetimeStats
        XCTAssertNotNil(lifetime)
        XCTAssertEqual(lifetime?.operatingHours, 19_148)
        XCTAssertEqual(lifetime?.minTempC ?? 0, 7.0, accuracy: 0.001)
        XCTAssertEqual(lifetime?.avgTempC ?? 0, 22.5, accuracy: 0.001)
        XCTAssertEqual(lifetime?.maxTempC ?? 0, 40.0, accuracy: 0.001)
        XCTAssertEqual(lifetime?.minPackVoltageV ?? 0, 10.694, accuracy: 0.001)
        XCTAssertEqual(lifetime?.maxPackVoltageV ?? 0, 13.300, accuracy: 0.001)
        XCTAssertEqual(lifetime?.maxChargeCurrentA ?? 0, 6.68, accuracy: 0.001)
        XCTAssertEqual(lifetime?.maxDischargeCurrentA ?? 0, 6.95, accuracy: 0.001)
    }

    func testSMCReaderPackageDisplayThermalAndFansWithCachingAndFastModeSkip() {
        let mock = CountingSMCKeyReader(values: [
            "PDTR": makeFloatSMCValue(key: "PDTR", value: 24.5),
            "PSTR": makeFloatSMCValue(key: "PSTR", value: 21.0),
            "PPBR": makeFloatSMCValue(key: "PPBR", value: 0.0),
            "PHPC": makeFloatSMCValue(key: "PHPC", value: 5.17),
            "PDBR": makeFloatSMCValue(key: "PDBR", value: 2.34),
            "Tp05": makeFloatSMCValue(key: "Tp05", value: 55.2),
            "Tp0D": makeFloatSMCValue(key: "Tp0D", value: 58.6),
            "Tg05": makeFloatSMCValue(key: "Tg05", value: 47.1),
            "Tg0D": makeFloatSMCValue(key: "Tg0D", value: 49.5),
            "FNum": SMCValue(key: "FNum", dataSize: 1, dataType: "ui8 ", bytes: [2]),
            "F0Ac": makeFloatSMCValue(key: "F0Ac", value: 0.0),
            "F0Mx": makeFloatSMCValue(key: "F0Mx", value: 6800.0),
            "F1Ac": makeFloatSMCValue(key: "F1Ac", value: 1850.0),
            "F1Mx": makeFloatSMCValue(key: "F1Mx", value: 6800.0)
        ])

        let reader = SMCReader(keyReader: mock)

        // Fast mode must skip extra package/display/thermal/fan keys
        let fastSample = reader.readSample(full: false)
        XCTAssertEqual(fastSample.deliveryRateW ?? 0, 24.5, accuracy: 0.01)
        XCTAssertNil(fastSample.packagePowerW)
        XCTAssertNil(fastSample.displayPowerW)
        XCTAssertNil(fastSample.cpuTemperatureC)
        XCTAssertNil(fastSample.gpuTemperatureC)
        XCTAssertTrue(fastSample.fans.isEmpty)
        XCTAssertEqual(mock.callCount(for: "PHPC"), 0)
        XCTAssertEqual(mock.callCount(for: "FNum"), 0)

        // First full scan discovers and caches keys
        let fullSample1 = reader.readSample(full: true)
        XCTAssertEqual(fullSample1.packagePowerW ?? 0, 5.17, accuracy: 0.01)
        XCTAssertEqual(fullSample1.displayPowerW ?? 0, 2.34, accuracy: 0.01)
        XCTAssertEqual(fullSample1.cpuTemperatureC ?? 0, 58.6, accuracy: 0.01)
        XCTAssertEqual(fullSample1.gpuTemperatureC ?? 0, 49.5, accuracy: 0.01)
        XCTAssertEqual(fullSample1.fans.count, 2)
        XCTAssertEqual(fullSample1.fans[0].rpm, 0.0, accuracy: 0.01)
        XCTAssertEqual(fullSample1.fans[0].maxRpm ?? 0, 6800.0, accuracy: 0.01)
        XCTAssertEqual(fullSample1.fans[1].rpm, 1850.0, accuracy: 0.01)
        XCTAssertEqual(fullSample1.fans[1].maxRpm ?? 0, 6800.0, accuracy: 0.01)

        // Second full scan reuses cached discovery (FNum, F0Mx, PHPC); die temperature candidates are probed every sample
        _ = reader.readSample(full: true)
        XCTAssertEqual(mock.callCount(for: "FNum"), 1)
        XCTAssertEqual(mock.callCount(for: "F0Mx"), 1)
        XCTAssertEqual(mock.callCount(for: "F0Ac"), 2)
        XCTAssertEqual(mock.callCount(for: "Tp09"), 2)
        XCTAssertEqual(mock.callCount(for: "Tp0D"), 2)
        XCTAssertEqual(mock.callCount(for: "PHPC"), 2)
    }

    func testIOPortActiveTransportsAndSOPPrimeCableType() {
        let entry = IOPortPowerReader.parsePortEntry(
            portProperties: [
                "IOClass": "AppleHPMInterfaceType10",
                "PortTypeDescription": "USB-C",
                "PortType": 2,
                "PortNumber": 1,
                "ConnectionActive": true,
                "TransportsActive": ["CC", "USB2", "DisplayPort"]
            ],
            sopPrimeComponents: [
                [
                    "ComponentName": "SOP'",
                    "Product Type Description": "Passive Cable"
                ]
            ]
        )

        XCTAssertEqual(entry?.activeTransports, ["CC", "USB2", "DisplayPort"])
        XCTAssertEqual(entry?.cableType, "Passive Cable")
    }

    // MARK: - Helpers

    private func makeFloatSMCValue(key: String, value: Float) -> SMCValue {
        let bits = value.bitPattern
        let bytes: [UInt8] = [
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF)
        ]
        return SMCValue(key: key, dataSize: 4, dataType: "flt ", bytes: bytes)
    }
}

private struct MockSMCKeyReader: SMCKeyReading {
    let values: [String: SMCValue]

    func readKey(_ key: String) -> SMCValue? {
        values[key]
    }
}

private final class CountingSMCKeyReader: SMCKeyReading, @unchecked Sendable {
    private let values: [String: SMCValue]
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    init(values: [String: SMCValue]) {
        self.values = values
    }

    func readKey(_ key: String) -> SMCValue? {
        lock.lock()
        counts[key, default: 0] += 1
        lock.unlock()
        return values[key]
    }

    func callCount(for key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[key, default: 0]
    }
}
