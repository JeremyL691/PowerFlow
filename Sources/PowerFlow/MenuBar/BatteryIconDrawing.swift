import AppKit
import SwiftUI

/// Draws both battery designs in a shared `26 × 16 pt` canvas with a `23 × 12 pt` shell.
struct BatteryIconDrawing {
    static let canvasSize = NSSize(width: 26, height: 16)

    private static let shell = CGRect(x: 0, y: 2, width: 23, height: 12)
    private static let capOrigin = CGPoint(x: 24, y: 2)
    private static let capSize = CGSize(width: 2, height: 12)

    // Solid
    private static let solidCornerRadius: CGFloat = 3.85
    private static let solidFillAlpha: CGFloat = 0.847
    private static let solidTrackAlpha: CGFloat = 0.549
    private static let solidTintedTrackAlpha: CGFloat = 0.5
    private static let minimumFillWidth: CGFloat = 2

    // Outlined
    private static let outlineAlpha: CGFloat = 0.5
    private static let outlineRadius: CGFloat = 2.85
    private static let outlinedFillInset: CGFloat = 2
    private static let outlinedFillRadius: CGFloat = 2.05

    private static let capAlpha: CGFloat = 0.6

    let spec: BatteryIconRenderSpec
    let artwork: SystemBatteryArtwork

    func draw(in ctx: CGContext) {
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        switch spec.style {
        case .solid:
            drawSolid(in: ctx)
        case .outlined:
            drawOutlined(in: ctx)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Charge width in whole points, rounded the way the system rounds it.
    static func fillWidth(percent: Int, available: CGFloat) -> CGFloat {
        let clamped = CGFloat(min(max(percent, 0), 100))
        return max(minimumFillWidth, (available * clamped / 100).rounded())
    }

    // MARK: - Solid

    private func drawSolid(in ctx: CGContext) {
        let shell = Self.shell
        let path = NSBezierPath(
            roundedRect: shell,
            xRadius: Self.solidCornerRadius,
            yRadius: Self.solidCornerRadius
        )

        ctx.saveGState()
        path.addClip()
        if spec.state == .unavailable {
            fill(shell, color: primary.withAlphaComponent(Self.solidTrackAlpha), in: ctx)
        } else {
            let width = Self.fillWidth(percent: spec.percent, available: shell.width)
            let trackAlpha = spec.usesTemplateRendering ? Self.solidTrackAlpha : Self.solidTintedTrackAlpha
            let fillColor = tint ?? primary.withAlphaComponent(Self.solidFillAlpha)
            let (charged, track) = shell.divided(atDistance: width, from: .minXEdge)
            fill(charged, color: fillColor, in: ctx)
            fill(track, color: primary.withAlphaComponent(trackAlpha), in: ctx)
        }
        ctx.restoreGState()

        drawCap(in: ctx)

        if spec.state == .unavailable {
            drawGlyph(artwork.image(.missing), symbol: "xmark", size: CGSize(width: 11, height: 12), in: ctx)
        } else if spec.showsPercent {
            punchPercent(in: ctx)
        } else {
            drawOverlay(
                size: CGSize(width: 13, height: 16),
                bolt: (.boltLarge, .boltMaskLarge),
                plug: (.plugLarge, .plugMaskLarge),
                in: ctx
            )
        }
    }

    /// Cuts the charge, followed by a small bolt or plug while on power, out of the shell.
    private func punchPercent(in ctx: CGContext) {
        let isFull = spec.percent >= 100
        let text = NSAttributedString(
            string: "\(min(max(spec.percent, 0), 100))",
            attributes: [
                .font: NSFont.systemFont(ofSize: isFull ? 9 : 10, weight: .regular),
                .foregroundColor: NSColor.black,
            ]
        )
        let textSize = text.size()
        let center = CGPoint(x: Self.shell.midX, y: Self.shell.midY)

        var glyph: (image: NSImage, size: CGSize)?
        if let image = compactGlyph, image.size.height > 0 {
            let height: CGFloat = isFull ? 7 : 9
            glyph = (image, CGSize(width: height * image.size.width / image.size.height, height: height))
        }
        let glyphGap: CGFloat = -1
        let totalWidth = textSize.width + (glyph.map { $0.size.width + glyphGap } ?? 0)
        let textX = center.x - totalWidth / 2

        ctx.saveGState()
        ctx.setBlendMode(.destinationOut)
        text.draw(at: CGPoint(x: textX, y: center.y - textSize.height / 2))
        ctx.restoreGState()

        if let glyph {
            let rect = CGRect(
                x: textX + textSize.width + glyphGap,
                y: center.y - glyph.size.height / 2,
                width: glyph.size.width,
                height: glyph.size.height
            )
            glyph.image.draw(in: rect, from: .zero, operation: .destinationOut, fraction: 1)
        }
    }

    private var compactGlyph: NSImage? {
        switch spec.overlay {
        case .none:
            return nil
        case .chargingBolt:
            return artwork.image(.bolt) ?? Self.symbol("bolt.fill", pointSize: 9)
        case .pluggedInPlug:
            return artwork.image(.plug) ?? Self.symbol("powerplug.portrait.fill", pointSize: 9)
        }
    }

    // MARK: - Outlined

    private func drawOutlined(in ctx: CGContext) {
        let shell = Self.shell
        let outline = RoundedRectangle(cornerRadius: Self.outlineRadius, style: .continuous)
            .path(in: shell.insetBy(dx: 0.5, dy: 0.5))
            .cgPath
        ctx.saveGState()
        ctx.setStrokeColor(primary.withAlphaComponent(Self.outlineAlpha).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(outline)
        ctx.strokePath()
        ctx.restoreGState()

        drawCap(in: ctx)

        guard spec.state != .unavailable else {
            drawGlyph(artwork.image(.missing), symbol: "xmark", size: CGSize(width: 11, height: 12), in: ctx)
            return
        }

        if spec.percent > 0 {
            let cavity = shell.insetBy(dx: Self.outlinedFillInset, dy: Self.outlinedFillInset)
            let charged = CGRect(
                x: cavity.minX,
                y: cavity.minY,
                width: Self.fillWidth(percent: spec.percent, available: cavity.width),
                height: cavity.height
            )
            let radius = min(Self.outlinedFillRadius, charged.width / 2)
            (tint ?? primary).setFill()
            NSBezierPath(roundedRect: charged, xRadius: radius, yRadius: radius).fill()
        }

        drawOverlay(
            size: CGSize(width: 11, height: 14),
            bolt: (.bolt, .boltMask),
            plug: (.plug, .plugMask),
            in: ctx
        )
    }

    // MARK: - Shared Pieces

    private func drawCap(in ctx: CGContext) {
        let rect = CGRect(origin: Self.capOrigin, size: Self.capSize)
        if let cap = artwork.image(.cap) {
            drawTinted(cap, in: rect, color: primary, ctx: ctx)
            return
        }
        let dome = CGRect(x: rect.minX - 1.5, y: rect.midY - 2.25, width: 3, height: 4.5)
        ctx.saveGState()
        ctx.clip(to: rect)
        primary.withAlphaComponent(Self.capAlpha).setFill()
        NSBezierPath(ovalIn: dome).fill()
        ctx.restoreGState()
    }

    private func drawOverlay(
        size: CGSize,
        bolt: (glyph: SystemBatteryArtwork.Piece, mask: SystemBatteryArtwork.Piece),
        plug: (glyph: SystemBatteryArtwork.Piece, mask: SystemBatteryArtwork.Piece),
        in ctx: CGContext
    ) {
        let pieces: (glyph: SystemBatteryArtwork.Piece, mask: SystemBatteryArtwork.Piece)
        let symbol: String
        switch spec.overlay {
        case .none:
            return
        case .chargingBolt:
            (pieces, symbol) = (bolt, "bolt.fill")
        case .pluggedInPlug:
            (pieces, symbol) = (plug, "powerplug.portrait.fill")
        }

        if let mask = artwork.image(pieces.mask), artwork.image(pieces.glyph) != nil {
            mask.draw(in: centered(size), from: .zero, operation: .destinationOut, fraction: 1)
        } else if let fallback = Self.symbol(symbol, pointSize: size.height * 0.8) {
            punchHalo(of: fallback, in: centered(fallback.size))
        }
        drawGlyph(artwork.image(pieces.glyph), symbol: symbol, size: size, in: ctx)
    }

    private func drawGlyph(_ image: NSImage?, symbol: String, size: CGSize, in ctx: CGContext) {
        if let image {
            drawTinted(image, in: centered(size), color: primary, ctx: ctx)
        } else if let fallback = Self.symbol(symbol, pointSize: size.height * 0.8) {
            drawTinted(fallback, in: centered(fallback.size), color: primary, ctx: ctx)
        }
    }

    private func punchHalo(of image: NSImage, in rect: CGRect) {
        let radius: CGFloat = 1.25
        for step in 0..<16 {
            let angle = CGFloat(step) / 16 * 2 * .pi
            image.draw(
                in: rect.offsetBy(dx: cos(angle) * radius, dy: sin(angle) * radius),
                from: .zero,
                operation: .destinationOut,
                fraction: 1
            )
        }
    }

    private func centered(_ size: CGSize) -> CGRect {
        CGRect(
            x: Self.shell.midX - size.width / 2,
            y: Self.shell.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func drawTinted(_ image: NSImage, in rect: CGRect, color: NSColor, ctx: CGContext) {
        let bounds = rect.insetBy(dx: -1, dy: -1)
        ctx.saveGState()
        ctx.beginTransparencyLayer(in: bounds, auxiliaryInfo: nil)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(color.cgColor)
        ctx.fill(bounds)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    private func fill(_ rect: CGRect, color: NSColor, in ctx: CGContext) {
        guard !rect.isEmpty else { return }
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect)
    }

    private static func symbol(_ name: String, pointSize: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
    }

    // MARK: - Colors

    /// Template images are drawn in black and tinted by the menu bar.
    private var primary: NSColor {
        if spec.usesTemplateRendering {
            return .black
        }
        return spec.isDarkMenuBar ? .white : .black
    }

    private var tint: NSColor? {
        switch spec.state {
        case .lowPower:
            return resolved(.systemYellow)
        case .critical:
            return resolved(.systemRed)
        case .neutral, .unavailable:
            return nil
        }
    }

    private func resolved(_ color: NSColor) -> NSColor {
        guard let appearance = NSAppearance(named: spec.isDarkMenuBar ? .darkAqua : .aqua) else {
            return color
        }
        var result = color
        appearance.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB) ?? color
        }
        return result
    }
}
