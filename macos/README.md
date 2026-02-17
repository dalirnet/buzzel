# Buzzel — macOS

Status bar app that connects to the Android Buzzel service over BLE or local WiFi.

## Project Structure

```
Sources/
├── App/
│   ├── BuzzelApp.swift          # App entry, AppDelegate, MenuBarExtra
│   └── StatusBarController.swift # Status bar icon and popover
├── Models/
│   ├── DesignColor.swift        # Adaptive color system (light/dark)
│   ├── DeviceInfo.swift         # Paired device info
│   ├── DiscoveredDevice.swift   # BLE discovered device
│   ├── LogEntry.swift           # Log event types, direction, status
│   └── PowerButtonState.swift   # Connection state enum
├── Services/
│   ├── Protocol.swift           # Binary protocol, signals, TLV, QR
│   ├── FrameCodec.swift         # Length-prefixed frame encode/decode
│   ├── BleCentral.swift         # CoreBluetooth central (scan, connect, subscribe)
│   ├── TcpServer.swift          # Network.framework TCP server
│   ├── TransportManager.swift   # Unified BLE/TCP, state machine, ping/pong
│   ├── QRGenerator.swift        # QR code generation for pairing
│   ├── SVGPathParser.swift      # SVG path data parser (arcs, curves)
│   └── AppStore.swift           # UserDefaults persistence
└── Views/
    ├── MainView.swift           # Root view with state-driven content
    ├── PowerButtonView.swift    # Connection button with shield icons
    ├── OrbitRingsView.swift     # Animated orbit rings around button
    ├── AnimatedSwitcher.swift   # Scale transition between views
    ├── CircularQRView.swift     # QR code display for pairing
    ├── ActivityLogView.swift    # Activity log sheet
    └── AppComponents.swift      # Shared UI components (header, icons)
Tests/
└── ProtocolTests.swift          # Protocol + FrameCodec tests
Resources/
├── Info.plist                   # App config (LSUIElement=true, no dock icon)
└── Buzzel.entitlements          # Sandbox, network, bluetooth
```

## Requirements

- macOS 13.0+
- Xcode command line tools (`xcode-select --install`)

## Dependencies

All native macOS frameworks, no external packages:

- `CoreBluetooth` — BLE central manager
- `Network` — TCP server (NWListener)
- `SwiftUI` — UI framework
- `AppKit` — menu bar integration

## Build

```bash
make init      # check dependencies
make format    # format sources (requires swift-format)
make build     # debug build
make release   # universal binary (arm64 + x86_64)
make test      # run protocol tests
make run       # build and launch
make dist      # package build/Buzzel.zip
make clean     # remove build artifacts
```
