# Buzzel

**Connect your Android phone to your Mac. Privately.**

Buzzel pairs your Android phone with your Mac over a direct local connection — no cloud, no internet, no middleman. Communication happens entirely over BLE or local WiFi, so nothing ever leaves your devices.

## How It Works

- A lightweight macOS status bar app connects to a silent background service on your Android phone
- Communication happens over **BLE or local WiFi** with automatic failover
- Custom binary protocol — 256-byte frames, QR-based pairing, reliable delivery
- Both apps stay completely out of your way after setup

## Setup

1. Install the macOS app — an icon appears in your status bar
2. Install the Android app and open it once to grant permissions
3. Scan the QR code shown on Mac with your phone
4. Done — devices are paired

## Architecture

| Role    | Android                  | macOS             |
| ------- | ------------------------ | ----------------- |
| BLE     | Peripheral (GATT Server) | Central           |
| WiFi    | TCP Client               | TCP Server        |
| Pairing | Scans QR code            | Generates QR code |

## Privacy

- **Nothing leaves your devices** — no cloud, no internet, no third-party servers
- **Direct connection only** — BLE or local WiFi between your paired devices

## Requirements

- **Mac**: macOS 13.0 or later
- **Android**: Android 9 (API 28) or later
- Both devices need Bluetooth or to be on the same WiFi network

## Development

```
# macOS
cd macos
make init    # install dependencies
make format  # format Swift sources (requires swift-format)
make build   # build app
make test    # run protocol tests
make run     # build and launch

# Android
cd android
make init    # install dependencies
make format  # format Kotlin sources (requires ktlint)
make build   # build debug APK
make test    # run unit tests
make run     # build, install, and launch
```
