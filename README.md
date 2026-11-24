# PowerFlow

A native macOS menu bar utility for real-time Apple Silicon power flow, battery health, adapter diagnostics, and outbound USB-C power telemetry.

## Highlights

- **Zero-Root, Zero-Subprocess Telemetry**: Reads directly from `AppleSMC`, `AppleSmartBattery` (IOKit), and `IOPort` in-process with zero helper daemons or shell invocations.
- **Low-Overhead Architecture**: Animations run in the render server. Runs purely event-driven (`IOPSNotification`, Low Power Mode, sleep/wake notifications) with **no background polling timer** when the popover is closed in icon-only or percentage menu bar modes.
- **Native macOS Battery Icon**: Reproduces Apple's menu bar battery in the outlined or the solid macOS 27 design (selectable in Settings), using the system's own glyphs and rules for the charging bolt, plug, Low Power Mode yellow and low-battery red.
- **Live Power Flow Diagram**: Charger, battery, Mac and USB-C devices as connected nodes with animated links whose thickness and speed follow the power — hybrid supply, charging, battery-only, bypass and draining to a charge limit while plugged in.
- **Real-Time USB-C Output and System Charge Limit**: Per-port outbound power refreshed every second, and the charge limit macOS itself enforces.
- **Bilingual UI**: Full English and Simplified Chinese (`简体中文`) localization with live runtime switching.

## Requirements

- macOS 15.0+ (Apple Silicon recommended for full SMC + `IOPort` telemetry)
- Xcode 26+ / Swift 6.0 (the app icon is an Icon Composer document)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Building & Testing

```bash
xcodegen generate
xcodebuild -project PowerFlow.xcodeproj -scheme PowerFlow -destination "platform=macOS" test
xcodebuild -project PowerFlow.xcodeproj -scheme PowerFlow -configuration Release -destination "platform=macOS" build
```

### CLI Diagnostic Modes

```bash
# Verify clean menu-bar-only launch with no leaked startup window
PowerFlow.app/Contents/MacOS/PowerFlow --smoke-launch

# Capture and print a single live hardware telemetry snapshot
PowerFlow.app/Contents/MacOS/PowerFlow --dump-snapshot
```

## License

MIT License. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
