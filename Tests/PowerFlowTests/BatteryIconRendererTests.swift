import AppKit
import XCTest
@testable import PowerFlow

final class BatteryIconRendererTests: XCTestCase {
    // MARK: - State & Overlay Rules

    private func snapshot(
        percent: Int = 80,
        isExternalConnected: Bool = false,
        isCharging: Bool = false,
        isLowBatteryWarning: Bool = false,
        isLowPowerModeEnabled: Bool = false,
        phase: PowerConnectionPhase? = nil,
        flowMode: PowerFlowMode? = nil,
        totalSystemLoadW: Double = 0,
        adapterInputPowerW: Double = 0,
        batteryPowerW: Double = 0,
        outboundPorts: [OutboundPortPower] = [],
        totalOutboundPowerW: Double = 0
    ) -> PowerSnapshot {
        let resolvedPhase = phase ?? (isExternalConnected ? .onAC : .onBattery)
        let resolvedFlowMode = flowMode ?? (isExternalConnected ? .adapterBypass : .batteryOnly)
        return PowerSnapshot(
            isDataAvailable: true,
            connectionPhase: resolvedPhase,
            flowMode: resolvedFlowMode,
            batteryPercent: percent,
            isExternalConnected: isExternalConnected,
            isCharging: isCharging,
            isLowBatteryWarning: isLowBatteryWarning,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            batteryPowerW: batteryPowerW,
            totalSystemLoadW: totalSystemLoadW,
            adapterInputPowerW: adapterInputPowerW,
            outboundPorts: outboundPorts,
            totalOutboundPowerW: totalOutboundPowerW
        )
    }

    func testStateFollowsSystemRules() {
        XCTAssertEqual(NativeBatteryIconRenderer.state(for: .empty), .unavailable)
        XCTAssertEqual(NativeBatteryIconRenderer.state(for: snapshot()), .neutral)
        // Red comes from the system warning, not from a fixed percentage.
        XCTAssertEqual(NativeBatteryIconRenderer.state(for: snapshot(percent: 15)), .neutral)
        XCTAssertEqual(
            NativeBatteryIconRenderer.state(for: snapshot(percent: 9, isLowBatteryWarning: true)),
            .critical
        )
        XCTAssertEqual(
            NativeBatteryIconRenderer.state(
                for: snapshot(percent: 9, isExternalConnected: true, isLowBatteryWarning: true)
            ),
            .neutral
        )
        XCTAssertEqual(
            NativeBatteryIconRenderer.state(
                for: snapshot(percent: 9, isLowBatteryWarning: true, isLowPowerModeEnabled: true)
            ),
            .lowPower
        )
    }

    func testOverlayFollowsThePhysicalConnection() {
        XCTAssertEqual(NativeBatteryIconRenderer.overlay(for: .empty), .none)
        XCTAssertEqual(NativeBatteryIconRenderer.overlay(for: snapshot()), .none)
        XCTAssertEqual(
            NativeBatteryIconRenderer.overlay(for: snapshot(isExternalConnected: true, isCharging: true)),
            .chargingBolt
        )
        XCTAssertEqual(
            NativeBatteryIconRenderer.overlay(for: snapshot(isExternalConnected: true)),
            .pluggedInPlug
        )
        // Unplugged but still inside the debounce window: the plug is gone at once.
        XCTAssertEqual(NativeBatteryIconRenderer.overlay(for: snapshot(phase: .onAC)), .none)
    }

    // MARK: - Style & Menu Bar Text

    func testOutlinedIsTheDefaultStyleAndSolidIsSelectable() throws {
        XCTAssertEqual(PowerSettings.default.batteryIconStyle, .outlined)

        let saved = try JSONEncoder().encode(PowerSettings(batteryIconStyle: .solid))
        XCTAssertEqual(try JSONDecoder().decode(PowerSettings.self, from: saved).batteryIconStyle, .solid)

        // Settings written before the style existed keep working.
        let legacy = Data(#"{"menuBarDisplayMode":"iconOnly"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(PowerSettings.self, from: legacy).batteryIconStyle, .outlined)
    }

    @MainActor
    func testPercentageSitsInsideTheSolidIconAndBesideTheOutlinedOne() {
        let snap = snapshot(percent: 64)
        func title(_ mode: MenuBarDisplayMode, _ style: BatteryIconStyle) -> String {
            StatusItemController.makeMenuBarTitle(snapshot: snap, mode: mode, style: style)
        }
        XCTAssertEqual(title(.iconOnly, .solid), "")
        XCTAssertEqual(title(.iconAndPercentage, .solid), "")
        XCTAssertEqual(title(.iconAndPercentage, .outlined), "64%")
        XCTAssertEqual(title(.iconAndWatts, .solid), "0W")
        XCTAssertEqual(title(.iconPercentageAndWatts, .solid), "0W")
        XCTAssertEqual(title(.iconPercentageAndWatts, .outlined), "64% · 0W")

        let highWattAC = snapshot(percent: 80, isExternalConnected: true, adapterInputPowerW: 24.3)
        XCTAssertEqual(
            StatusItemController.makeMenuBarTitle(snapshot: highWattAC, mode: .iconPercentageAndWatts, style: .outlined),
            "80% · 24W"
        )
        let lowWattAC = snapshot(percent: 80, isExternalConnected: true, adapterInputPowerW: 8.4)
        XCTAssertEqual(
            StatusItemController.makeMenuBarTitle(snapshot: lowWattAC, mode: .iconAndWatts, style: .solid),
            "8.4W"
        )
        XCTAssertEqual(
            StatusItemController.makeMenuBarTitle(snapshot: .empty, mode: .iconPercentageAndWatts, style: .outlined),
            "--% · --W"
        )
    }

    @MainActor
    func testTooltipPrecisionSuppressesSubWattJitterAboveTenWatts() {
        let englishSettings = PowerSettings(appLanguage: .english)

        let acLow = snapshot(percent: 80, isExternalConnected: true, adapterInputPowerW: 24.1)
        let acHigh = snapshot(percent: 80, isExternalConnected: true, adapterInputPowerW: 24.4)
        let acLowTooltip = StatusItemController.makeTooltip(snapshot: acLow, settings: englishSettings)
        let acHighTooltip = StatusItemController.makeTooltip(snapshot: acHigh, settings: englishSettings)
        XCTAssertEqual(acLowTooltip, acHighTooltip)
        XCTAssertEqual(acLowTooltip, "PowerFlow · 80% · Power Adapter (24W)")

        let battLow = snapshot(percent: 62, totalSystemLoadW: 18.1)
        let battHigh = snapshot(percent: 62, totalSystemLoadW: 18.4)
        XCTAssertEqual(
            StatusItemController.makeTooltip(snapshot: battLow, settings: englishSettings),
            StatusItemController.makeTooltip(snapshot: battHigh, settings: englishSettings)
        )
        XCTAssertEqual(
            StatusItemController.makeTooltip(snapshot: battLow, settings: englishSettings),
            "PowerFlow · 62% · Battery (18W)"
        )

        let outboundPort = OutboundPortPower(
            id: "port-1",
            portIndex: 1,
            portLabel: "USB-C 1",
            currentA: 2.4,
            voltageV: 5.0,
            powerW: 12.1
        )
        let outLow = snapshot(
            percent: 80,
            isExternalConnected: true,
            adapterInputPowerW: 36.1,
            outboundPorts: [outboundPort],
            totalOutboundPowerW: 12.1
        )
        let outHigh = snapshot(
            percent: 80,
            isExternalConnected: true,
            adapterInputPowerW: 36.4,
            outboundPorts: [outboundPort],
            totalOutboundPowerW: 12.4
        )
        XCTAssertEqual(
            StatusItemController.makeTooltip(snapshot: outLow, settings: englishSettings),
            StatusItemController.makeTooltip(snapshot: outHigh, settings: englishSettings)
        )
        XCTAssertTrue(
            StatusItemController.makeTooltip(snapshot: outLow, settings: englishSettings).contains("Out: 12W")
        )

        // Sub-10W retains 0.1W compact precision, matching compactWatts.
        let subTenA = snapshot(percent: 80, isExternalConnected: true, adapterInputPowerW: 8.2)
        let subTenB = snapshot(percent: 80, isExternalConnected: true, adapterInputPowerW: 8.3)
        XCTAssertEqual(
            StatusItemController.makeTooltip(snapshot: subTenA, settings: englishSettings),
            "PowerFlow · 80% · Power Adapter (8.2W)"
        )
        XCTAssertEqual(
            StatusItemController.makeTooltip(snapshot: subTenB, settings: englishSettings),
            "PowerFlow · 80% · Power Adapter (8.3W)"
        )
    }

    @MainActor
    func testContextMenuRoutingDoesNotHijackVoiceOverSpace() {
        XCTAssertTrue(StatusItemController.shouldOpenContextMenu(eventType: .rightMouseDown, modifierFlags: []))
        XCTAssertTrue(StatusItemController.shouldOpenContextMenu(eventType: .rightMouseUp, modifierFlags: []))
        XCTAssertTrue(StatusItemController.shouldOpenContextMenu(eventType: .leftMouseDown, modifierFlags: [.control]))
        XCTAssertTrue(StatusItemController.shouldOpenContextMenu(eventType: .leftMouseUp, modifierFlags: [.control]))
        XCTAssertFalse(StatusItemController.shouldOpenContextMenu(eventType: .leftMouseDown, modifierFlags: []))
        XCTAssertFalse(StatusItemController.shouldOpenContextMenu(eventType: .leftMouseUp, modifierFlags: []))
        // VoiceOver VO+Space arrives as a key event with Control+Option modifiers.
        XCTAssertFalse(
            StatusItemController.shouldOpenContextMenu(eventType: .keyDown, modifierFlags: [.control, .option])
        )
        XCTAssertFalse(
            StatusItemController.shouldOpenContextMenu(eventType: .keyUp, modifierFlags: [.control, .option])
        )
    }

    // MARK: - Rendering

    func testFillWidthRoundsToWholePoints() {
        let expected: [(Int, CGFloat)] = [(0, 2), (10, 2), (11, 3), (50, 12), (52, 12), (55, 13), (97, 22), (98, 23), (100, 23)]
        for (percent, width) in expected {
            XCTAssertEqual(BatteryIconDrawing.fillWidth(percent: percent, available: 23), width, "\(percent)%")
        }
        XCTAssertEqual(BatteryIconDrawing.fillWidth(percent: 51, available: 19), 10)
        XCTAssertEqual(BatteryIconDrawing.fillWidth(percent: 150, available: 19), 19)
    }

    @MainActor
    func testTemplateRenderingIsLimitedToUncoloredStates() {
        for (state, isTemplate) in [
            (BatteryIconState.neutral, true), (.unavailable, true), (.lowPower, false), (.critical, false)
        ] {
            let spec = BatteryIconRenderSpec(percent: 50, state: state, isDarkMenuBar: true, style: .solid)
            XCTAssertEqual(NativeBatteryIconRenderer.render(spec: spec).isTemplate, isTemplate)
        }
    }

    @MainActor
    func testRenderCachesEquivalentSpecs() {
        func render(_ percent: Int, dark: Bool, showsPercent: Bool = false, style: BatteryIconStyle = .solid) -> NSImage {
            NativeBatteryIconRenderer.render(
                spec: BatteryIconRenderSpec(
                    percent: percent,
                    state: .neutral,
                    showsPercent: showsPercent,
                    isDarkMenuBar: dark,
                    style: style
                )
            )
        }
        XCTAssertTrue(render(120, dark: true) === render(100, dark: false))
        XCTAssertFalse(render(60, dark: true) === render(60, dark: true, showsPercent: true))
        XCTAssertTrue(
            render(60, dark: true, style: .outlined) === render(60, dark: true, showsPercent: true, style: .outlined)
        )
    }

    @MainActor
    func testSolidTrackAndFillOpacity() throws {
        let bitmap = try rasterize(.init(percent: 52, state: .neutral, isDarkMenuBar: true, style: .solid))
        XCTAssertEqual(try alpha(bitmap, x: 4, y: 8), 0.847, accuracy: 0.02)
        XCTAssertEqual(try alpha(bitmap, x: 20, y: 8), 0.549, accuracy: 0.02)
        XCTAssertEqual(try alpha(bitmap, x: 23.5, y: 8), 0, accuracy: 0.02)
        XCTAssertEqual(try alpha(bitmap, x: 24.25, y: 8), 0.6, accuracy: 0.05)
    }

    @MainActor
    func testSolidPercentageIsCutOutOfTheShell() throws {
        let plain = try rasterize(.init(percent: 100, state: .neutral, isDarkMenuBar: true, style: .solid))
        let labelled = try rasterize(
            .init(percent: 100, state: .neutral, showsPercent: true, isDarkMenuBar: true, style: .solid)
        )
        XCTAssertGreaterThan(transparentPixels(labelled), transparentPixels(plain) + 60)
    }

    @MainActor
    func testOutlinedShellKeepsAGapBetweenOutlineAndFill() throws {
        let bitmap = try rasterize(.init(percent: 100, state: .neutral, isDarkMenuBar: true, style: .outlined))
        XCTAssertEqual(try alpha(bitmap, x: 0.25, y: 8), 0.5, accuracy: 0.03)
        XCTAssertEqual(try alpha(bitmap, x: 1.25, y: 8), 0, accuracy: 0.02)
        XCTAssertEqual(try alpha(bitmap, x: 11.5, y: 8), 1, accuracy: 0.02)
    }

    @MainActor
    func testOutlinedChargeStopsAtTheFillWidth() throws {
        let bitmap = try rasterize(.init(percent: 50, state: .neutral, isDarkMenuBar: true, style: .outlined))
        XCTAssertEqual(try alpha(bitmap, x: 10, y: 8), 1, accuracy: 0.02)
        XCTAssertEqual(try alpha(bitmap, x: 14, y: 8), 0, accuracy: 0.02)
    }

    @MainActor
    func testOutlinedOverlayIsSeparatedFromTheChargeByAGap() throws {
        for overlay in [BatteryOverlay.chargingBolt, .pluggedInPlug] {
            let marked = try rasterize(.init(percent: 100, state: .neutral, overlay: overlay, isDarkMenuBar: true, style: .outlined))
            XCTAssertEqual(try alpha(marked, x: 11.5, y: 8), 1, accuracy: 0.02)
            // The cut-out leaves a fully transparent pixel between charge and mark on the centre line.
            let centreLine = try (6..<17).flatMap { column in
                try stride(from: 0.0, to: 1.0, by: 0.25).map { try alpha(marked, x: Double(column) + $0, y: 8) }
            }
            XCTAssertTrue(centreLine.contains { $0 < 0.05 })
        }
    }

    @MainActor
    func testColoredStatesUseSystemColors() throws {
        let yellow = try color(rasterize(.init(percent: 80, state: .lowPower, isDarkMenuBar: true, style: .solid)))
        XCTAssertGreaterThan(yellow.redComponent, 0.9)
        XCTAssertGreaterThan(yellow.greenComponent, 0.6)
        XCTAssertLessThan(yellow.blueComponent, 0.3)

        let red = try color(rasterize(.init(percent: 80, state: .critical, isDarkMenuBar: true, style: .solid)))
        XCTAssertGreaterThan(red.redComponent, 0.8)
        XCTAssertLessThan(red.greenComponent, 0.45)
    }

    @MainActor
    func testEveryStateRendersWithoutSystemArtwork() throws {
        for style in [BatteryIconStyle.solid, .outlined] {
            for overlay in [BatteryOverlay.none, .chargingBolt, .pluggedInPlug] {
                for state in [BatteryIconState.neutral, .lowPower, .critical, .unavailable] {
                    let spec = BatteryIconRenderSpec(
                        percent: 40,
                        state: state,
                        overlay: overlay,
                        showsPercent: style == .solid,
                        isDarkMenuBar: false,
                        style: style
                    )
                    let bitmap = try rasterize(spec, artwork: .unavailable)
                    XCTAssertLessThan(transparentPixels(bitmap), bitmap.pixelsWide * bitmap.pixelsHigh)
                }
            }
        }
    }

    @MainActor
    func testDrawingBindsGraphicsContextWhenCurrentContextIsNil() throws {
        let width = Int(BatteryIconDrawing.canvasSize.width) * Self.scale
        let height = Int(BatteryIconDrawing.canvasSize.height) * Self.scale
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        )
        ctx.scaleBy(x: CGFloat(Self.scale), y: CGFloat(Self.scale))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nil
        defer { NSGraphicsContext.restoreGraphicsState() }

        let spec = BatteryIconRenderSpec(
            percent: 75,
            state: .neutral,
            overlay: .chargingBolt,
            showsPercent: true,
            isDarkMenuBar: true,
            style: .solid
        )
        BatteryIconDrawing(spec: spec, artwork: .unavailable).draw(in: ctx)

        let cgImage = try XCTUnwrap(ctx.makeImage())
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        XCTAssertLessThan(transparentPixels(bitmap), bitmap.pixelsWide * bitmap.pixelsHigh)
    }

    // MARK: - Helpers

    private static let scale = 4

    @MainActor
    private func rasterize(
        _ spec: BatteryIconRenderSpec,
        artwork: SystemBatteryArtwork = .system
    ) throws -> NSBitmapImageRep {
        let image = NativeBatteryIconRenderer.makeImage(spec: spec, artwork: artwork)
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(image.size.width) * Self.scale,
                pixelsHigh: Int(image.size.height) * Self.scale,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func alpha(_ bitmap: NSBitmapImageRep, x: Double, y: Double) throws -> Double {
        let color = try XCTUnwrap(bitmap.colorAt(x: Int(x * Double(Self.scale)), y: Int(y * Double(Self.scale))))
        return Double(color.alphaComponent)
    }

    private func color(_ bitmap: NSBitmapImageRep) throws -> NSColor {
        try XCTUnwrap(bitmap.colorAt(x: 5 * Self.scale, y: 8 * Self.scale)?.usingColorSpace(.sRGB))
    }

    private func transparentPixels(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) < 0.05 {
                count += 1
            }
        }
        return count
    }
}
