# Buzzel — Android

Background service that connects to the paired macOS app over BLE or local WiFi TCP.

## Project Structure

```
app/src/main/java/com/buzzel/
├── BuzzelApp.kt                 # Application class, connection state listeners
├── ui/
│   ├── MainActivity.kt          # Main UI (power button, status, activity log)
│   ├── AppHeaderView.kt         # Header with logo, title, trailing icon
│   ├── PowerButtonView.kt       # Connection button with state icons
│   ├── OrbitRingsView.kt        # Animated orbit rings around button
│   ├── SVGIconView.kt           # SVG path icon renderer
│   ├── WaveBLogoView.kt         # App logo (wave-b path)
│   ├── AppColors.kt             # Adaptive color system (light/dark)
│   ├── PowerButtonState.kt      # Connection state enum
│   └── LayoutHelpers.kt         # dp conversion, layout param helpers
├── service/
│   ├── BuzzelService.kt         # Foreground service (state machine, ping/pong)
│   └── BootReceiver.kt          # Auto-start on boot
├── transport/
│   ├── BleGattServer.kt         # BLE GATT server (advertise, notify)
│   ├── TcpClient.kt             # WiFi TCP client (length-prefixed framing)
│   ├── FrameCodec.kt            # Frame encode/decode
│   └── TransportManager.kt      # Unified interface over BLE/TCP
├── model/
│   └── LogEntry.kt              # Log event types, direction, status
├── protocol/
│   └── Protocol.kt              # Binary protocol, signals, TLV, QR
├── config/
│   └── ConfigStore.kt           # SharedPreferences for pairing & settings
└── debug/
    └── FileLogger.kt            # File-based debug logger

app/src/test/java/com/buzzel/protocol/
└── ProtocolTest.kt              # Protocol + FrameCodec tests
```

## Requirements

- Min SDK 28 (Android 9)
- Target SDK 35

## Dependencies

- `androidx.core:core-ktx` — Kotlin extensions
- Everything else is native Android APIs
- ProGuard/R8 minification enabled for release builds

## Permissions

- `CAMERA` — QR code scanning
- `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_CONNECTED_DEVICE`
- `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`
- `INTERNET`, `ACCESS_WIFI_STATE`, `ACCESS_NETWORK_STATE`
- `RECEIVE_BOOT_COMPLETED` — auto-start
- `POST_NOTIFICATIONS` — foreground service notification

## Build

```bash
make init      # check dependencies
make format    # format sources (requires ktlint)
make build     # debug APK
make release   # release APK (minified)
make test      # run unit tests
make run       # build, install, and launch
make dist      # show release APK path
make clean     # remove build artifacts
```
