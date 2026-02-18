# User Flow

Step-by-step experience from install to daily use.

---

## 1. Install

- **macOS** — Open `Buzzel.app`. A status bar icon appears in the menu bar.
- **Android** — Install the APK. Open Buzzel from the launcher.

---

## 2. Grant Permissions

On first launch each platform requests the minimum permissions it needs.

| Platform | Permission    | Why                                      |
| -------- | ------------- | ---------------------------------------- |
| macOS    | Bluetooth     | Discover and connect to phone            |
| Android  | Bluetooth     | Advertise and accept connections         |
| Android  | Location      | Required by Android 11 and below for BLE |
| Android  | Camera        | Scan QR code                             |
| Android  | Notifications | Foreground service indicator             |

The power button shows a yellow shield with a warning icon until all permissions are granted. The status line reads "Tap to grant {permission} access". Tapping the button opens the system permission prompt.

---

## 3. Pair Devices

Pairing happens once. Both devices must be on the same local network (WiFi) or within Bluetooth range.

### On macOS

1. Tap the QR icon in the header.
2. A circular QR code replaces the power button area.
3. The QR encodes a random seed, the Mac's local IP, and transport preference.

### On Android

1. Tap the QR icon in the header.
2. A full-screen camera view opens.
3. Point the camera at the macOS QR code.
4. The app reads the seed, derives a session ID and pairing code, and stores them.

### Handshake

After the QR scan both apps begin searching for each other over BLE and WiFi. Once a transport connects:

1. Android sends the derived pairing code to macOS.
2. macOS verifies the code against the same seed.
3. If valid, macOS accepts the pairing.
4. Both devices save the pairing and transition to connected.

The power button turns green with a checkmark shield. The status line reads "Connected and ready".

---

## 4. Daily Use

Once paired the devices reconnect automatically. No repeated scanning.

### Connect

- **Android** — Open the app and tap the power button. A foreground service starts and the app begins searching. On device reboot, the service restarts automatically if previously paired.
- **macOS** — The app starts searching automatically when launched. It also lives in the status bar so it can stay running.

During connection the power button pulses orange with an upward shield. The status line reads "Looking for your device". The app tries BLE first (or WiFi, depending on preference), and falls back to the other transport if the first one times out after 10 seconds.

### Connected

- Power button: solid green, checkmark shield.
- Status bar icon (macOS): active.
- Notification (Android): foreground service indicator.
- Status line: shows the last activity entry and its timestamp, or "Connected and ready" if there is no activity yet.

A ping is exchanged every 30 seconds to confirm the link is alive.

### Disconnect

Tap the green power button to disconnect gracefully. Both sides return to idle.

- Power button: red, cross shield.
- Status bar icon (macOS): dimmed.
- Status line: shows the last activity, or "Tap to reconnect" if there is none.

### Reconnect

Tap the red power button to start searching again. The flow returns to the Connect step above.

### Connection Lost

If the link drops unexpectedly (out of range, WiFi change, etc.) the app detects it via keepalive timeout (no response within 10 seconds) and returns to disconnected state. Tap the power button to reconnect.

---

## 5. Activity Log

Tap the status line (when connected or disconnected) to open the activity log. It shows recent events (up to 200 on Android, 100 on macOS), newest first.

Each entry displays:

- Green or red dot (success / failure)
- Message (up to 2 lines)
- Optional error detail
- Timestamp
- Optional direction (IN / OUT)

Tap the back arrow in the header to return to the main view.

---

## 6. Unpair

Unpair is handled via the protocol. When one device sends an unpair signal, both sides clear all stored pairing data (session ID, pairing code, device info). After unpairing the power button returns to gray with a keyhole shield and the status line reads "No device paired yet".

To use Buzzel again, repeat the pairing flow from step 3.

---

## State Summary

| State         | Button Color | Shield Icon | Status Line                            |
| ------------- | ------------ | ----------- | -------------------------------------- |
| No permission | Yellow       | Warning     | Tap to grant {permission} access       |
| Unpaired      | Gray         | Keyhole     | No device paired yet                   |
| Connecting    | Orange       | Chevrons up | Looking for your device                |
| Connected     | Green        | Checkmark   | {last activity} or Connected and ready |
| Disconnected  | Red          | Cross       | {last activity} or Tap to reconnect    |
