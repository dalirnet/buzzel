# Buzzel — macOS

Status bar app that connects to the Android Buzzel service, configures SMS filters, and shows forwarded messages as native macOS notifications with smart copy actions.

## Project Structure

```
Sources/
├── App/
│   └── BuzzelApp.swift          # App entry, AppDelegate, status bar menu (MenuBarExtra)
├── Models/
│   ├── DeviceInfo.swift         # Paired device info
│   ├── DiscoveredDevice.swift   # BLE discovered device
│   ├── FilterRule.swift         # Filter rule model + presets
│   └── LogEntry.swift           # Log event types, direction, status
├── Services/
│   ├── Protocol.swift           # Message types, BLE UUIDs, JSON encode/decode
│   ├── BleCentral.swift         # CoreBluetooth central (scan, connect, subscribe)
│   ├── TcpClient.swift          # Network.framework TCP client
│   ├── TransportManager.swift   # Unified BLE/TCP, state machine, ping/pong
│   ├── NotificationManager.swift # macOS notifications + smart copy detection
│   └── AppStore.swift           # UserDefaults persistence
└── Views/
    ├── PairingView.swift        # Device discovery + 6-digit code entry
    ├── SettingsView.swift       # TabView container (General, Filters, Device)
    ├── FiltersView.swift        # Filter list + add/delete + presets
    ├── DeviceView.swift         # Paired device info + unpair
    ├── ActivityLogView.swift    # Activity log display
    └── ViewLayout.swift         # Reusable layout with header/content/footer
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
- `Network` — TCP client (NWConnection)
- `UserNotifications` — native notifications
- `SwiftUI` — UI framework
- `AppKit` — menu bar integration

## Permissions (Entitlements + Info.plist)

- Bluetooth (`NSBluetoothAlwaysUsageDescription`)
- Local Network (`NSLocalNetworkUsageDescription`)
- Notifications (UNUserNotificationCenter)
- App Sandbox with network client + server enabled

## Build

```bash
# Debug build (current arch)
make build
# → build/Buzzel.app

# Release build (universal binary: arm64 + x86_64)
make release
# → build/Buzzel.app

# Build and run
make run

# Package for distribution
make dist
# → build/Buzzel.zip

# Clean
make clean
```

## Smart Copy

Notifications include a Copy button for the first detected actionable content:

| Priority | Pattern  | Example                    | Copies           |
| -------- | -------- | -------------------------- | ---------------- |
| 1        | OTP/code | "Your code is **482107**"  | `482107`         |
| 2        | URL      | "Click **https://a.co/x**" | `https://a.co/x` |
| 3        | Phone    | "Call **+1-555-1234**"     | `+15551234`      |
| 4        | @mention | "From **@john_doe**"       | `@john_doe`      |
| 5        | #hashtag | "Use **#SAVE20**"          | `#SAVE20`        |
