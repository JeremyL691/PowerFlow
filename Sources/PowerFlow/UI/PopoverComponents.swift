import AppKit
import SwiftUI

/// Titled card shared by every popover section.
struct PopoverSection<Trailing: View, Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let tint: Color
    let title: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(PowerFlowTheme.primaryValue(for: colorScheme))
                    .lineLimit(1)
                Spacer(minLength: 4)
                trailing
            }
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PowerFlowTheme.nestedTileFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PowerFlowTheme.hairlineDivider(for: colorScheme), lineWidth: 0.65)
        )
    }
}

struct KeyValueRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String
    let value: String
    var valueColor: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? PowerFlowTheme.primaryValue(for: colorScheme))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct ProgressLine: View {
    @Environment(\.colorScheme) private var colorScheme

    let fraction: Double
    let tint: Color

    var body: some View {
        let clamped = min(1.0, max(0.0, fraction))
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(PowerFlowTheme.hairlineDivider(for: colorScheme))
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(clamped > 0.005 ? 3 : 0, geo.size.width * clamped))
            }
        }
        .frame(height: 3)
    }
}

/// Serial number that copies itself on click.
struct CopyableSerialRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String
    let serial: String
    let isMasked: Bool
    let language: AppLanguage

    @State private var isCopied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(PowerFlowTheme.mutedLabel(for: colorScheme))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Button(action: copy) {
                HStack(spacing: 3) {
                    Text(
                        isCopied
                            ? L10n.tr("Copied", zh: "已复制", language: language)
                            : PowerFormatters.maskSerial(serial, masked: isMasked)
                    )
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 8.5, weight: .medium))
                }
                .foregroundStyle(
                    isCopied
                        ? PowerFlowTheme.chargeGreen(for: colorScheme)
                        : PowerFlowTheme.secondaryValue(for: colorScheme)
                )
            }
            .buttonStyle(.plain)
            .help(L10n.tr("Click to copy serial number", zh: "点击复制序列号", language: language))
        }
        .task(id: isCopied) {
            guard isCopied else { return }
            try? await Task.sleep(for: .seconds(1.5))
            isCopied = false
        }
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(serial, forType: .string)
        isCopied = true
    }
}
