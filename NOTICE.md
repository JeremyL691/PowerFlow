# Third-Party Notices & Attributions

PowerFlow incorporates design ideas, telemetry techniques, and hardware parsing insights adapted from the following open-source MIT-licensed projects:

## PowerTop (`kDolphin/PowerTop`)
- Repository: https://github.com/kDolphin/PowerTop
- License: MIT License
- Attribution: Apple Silicon `IOKit` `AppleSmartBattery` nested `BatteryData` telemetry handling, charge-limit resolution concepts, and macOS menu bar power monitoring architecture.

## powerflow (`davelindo/powerflow`)
- Repository: https://github.com/davelindo/powerflow
- License: MIT License
- Attribution: Apple SMC (`AppleSMC`) telemetry key reading and macOS 26/27 hardened SMC payload status validation patterns, power flow visualization concepts, and battery time estimation heuristics.

## kumiko (`aimuzov/kumiko`)
- Repository: https://github.com/aimuzov/kumiko
- License: MIT License
- Attribution: Approach of composing the menu bar battery from Control Center's own image assets at runtime, and the layout of the outlined battery design. No Apple artwork is bundled with PowerFlow.
