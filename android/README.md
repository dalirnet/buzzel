# Buzzel — Android

Silent background service that listens for SMS, applies filters, and forwards matches to the paired macOS app over BLE or local WiFi TCP.

## Project Structure

```
app/src/main/java/com/buzzel/
├── BuzzelApp.kt                # Application class, connection state listeners
├── ui/
│   ├── MainActivity.kt         # Setup UI (permissions, Bluetooth, pairing code)
│   └── LogActivity.kt          # Activity log display
├── service/
│   ├── BuzzelService.kt        # Foreground service (state machine, ping/pong)
│   └── BootReceiver.kt         # Auto-start on boot
├── sms/
│   ├── SmsReceiver.kt          # BroadcastReceiver for incoming SMS
│   ├── SmsFilter.kt            # Wildcard filter engine (sender, content)
│   └── SmsQueue.kt             # Queue SMS while device is offline
├── transport/
│   ├── BleGattServer.kt        # BLE GATT server (low/high power modes)
│   ├── TcpServer.kt            # WiFi TCP server (length-prefixed framing)
│   └── TransportManager.kt     # Unified interface over BLE/TCP
├── model/
│   ├── LogEntry.kt             # Log event types, direction, status
│   ├── SmsData.kt              # SMS data structure
│   ├── FilterRule.kt           # Filter type enum + filter rule
│   └── ConfigData.kt           # Config sync data structure
├── protocol/
│   └── Protocol.kt             # Message types, BLE UUIDs, JSON serialization
└── config/
    └── ConfigStore.kt           # SharedPreferences for filters & settings
```

## Requirements

- Min SDK 28 (Android 9)
- Target SDK 35

## Dependencies

- `androidx.core:core-ktx` — Kotlin extensions (~100 KB)
- Everything else is native Android APIs: `SharedPreferences`, `org.json`, `BluetoothGattServer`
- **No Gson, no DataStore** — keeps APK under 1 MB
- ProGuard/R8 minification enabled for release builds

## Permissions

- `RECEIVE_SMS`, `READ_SMS` — listen for and read incoming SMS
- `READ_CONTACTS` — resolve sender to contact name
- `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_CONNECTED_DEVICE`
- `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`, `BLUETOOTH_SCAN`
- `INTERNET`, `ACCESS_WIFI_STATE`, `ACCESS_NETWORK_STATE`
- `RECEIVE_BOOT_COMPLETED` — auto-start
- `POST_NOTIFICATIONS` — foreground service notification

## Dev Setup

```bash
# Gradle (installs Java/OpenJDK automatically)
brew install gradle

# Android SDK + platform tools
brew install --cask android-commandlinetools
brew install --cask android-platform-tools

# Set up Android SDK path
echo 'export ANDROID_HOME="$HOME/Library/Android/sdk"' >> ~/.zshrc
echo 'export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Accept licenses and install SDK components
yes | sdkmanager --licenses
sdkmanager "platforms;android-35" "build-tools;35.0.0"
```

## Build

```bash
# Debug APK
./gradlew assembleDebug
# → app/build/outputs/apk/debug/app-debug.apk

# Release APK (minified)
./gradlew assembleRelease
# → app/build/outputs/apk/release/app-release.apk

# Install on connected device via USB
./gradlew installDebug
```

## Debug

```bash
adb devices              # list connected devices
adb logcat -s Buzzel     # view app logs
adb install app.apk      # install APK manually
```
