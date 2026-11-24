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
        phase: PowerConnectionPhase? = nil
    ) -> PowerSnapshot {
        PowerSnapshot(
            isDataAvailable: true,
            connectionPhase: phase ?? (isExternalConnected ? .onAC : .onBattery),
            batteryPercent: percent,
            isExternalConnected: isExternalConnected,
            isCharging: isCharging,
            isLowBatteryWarning: isLowBatteryWarning,
            isLowPowerModeEnabled: isLowPowerModeEnabled
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

    func testTemplateRenderingIsLimitedToUncoloredStates() {
        for (state, isTemplate) in [
            (BatteryIconState.neutral, true), (.unavailable, true), (.lowPower, false), (.critical, false)
        ] {
            let spec = BatteryIconRenderSpec(percent: 50, state: state, isDarkMenuBar: true, style: .solid)
            XCTAssertEqual(NativeBatteryIconRenderer.render(spec: spec).isTemplate, isTemplate)
        }
    }

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

    func testSolidTrackAndFillOpacity() throws {
        let bitmap = try rasterize(.init(percent: 52, state: .neutral, isDarkMenuBar: true, style: .solid))
        XCTAssertEqual(try alpha(bitmap, x: 4, y: 8), 0.847, accuracy: 0.02)
        XCTAssertEqual(try alpha(bitmap, x: 20, y: 8), 0.549, accuracy: 0.02)
        XCTAssertEqual(try alpha(bitmap, x: 23.5, y: 8), 0, accuracy: 0.02)
        XCTAssertEqual(try alpha(bitmap, x: 24.25, y: 8), 0.6, accuracy: 0.05)
    }

    func testSolidPercentageIsCutOutOfTheShell() throws {
        let plain = try rasterize(.init(percent: 100, state: .neutral, isDarkMenuBar: true, style: .solid))
        let labelled = try rasterize(
            .init(percent: 100, state: .neutral, showsPercent: true, isDarkMenuBar: true, style: .solid)
        )
        XCTAssertGreaterThan(transparentPixels(labelled), transparentPixels(plain) + 60)
    }

    func testOutlinedShellKeepsAGapBetweenOutlineAndFill() throws {
        let bitmap = try rasterize(.init(percent: 100, state: .neutral, isDarkMenuBar: true, style: .outlined))
        XCTAssertEqual(try alpha(bitmap, x: 0.25, y: 8), 0.5, accuracy: 0.03)
        XCTAssertEqual(try alpha(bitmap, x: 1.25, y: 8), 0, accuracy: 0.02)
        XCTAssertEqual(try alpha(bitmap, x: 11.5, y: 8), 1, accuracy: 0.02)
    }

    func testOutlinedChargeStopsAtTheFillWidth() throws {
        let bitmap = try rasterize(.init(percent: 50, state: .neutral, isDarkMenuBar: true, style: .outlined))
        XCTAssertEqual(try alpha(bitmap, x: 10, y: 8), 1, accuracy: 0.02)
        XCTAssertEqual(try alpha(bitmap, x: 14, y: 8), 0, accuracy: 0.02)
    }

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

    func testColoredStatesUseSystemColors() throws {
        let yellow = try color(rasterize(.init(percent: 80, state: .lowPower, isDarkMenuBar: true, style: .solid)))
        XCTAssertGreaterThan(yellow.redComponent, 0.9)
        XCTAssertGreaterThan(yellow.greenComponent, 0.6)
        XCTAssertLessThan(yellow.blueComponent, 0.3)

        let red = try color(rasterize(.init(percent: 80, state: .critical, isDarkMenuBar: true, style: .solid)))
        XCTAssertGreaterThan(red.redComponent, 0.8)
        XCTAssertLessThan(red.greenComponent, 0.45)
    }

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

    // MARK: - Helpers

    private static let scale = 4

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
