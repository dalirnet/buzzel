# User Flow

## States

### Android

| State          | When                                                     | Power button          |
| -------------- | -------------------------------------------------------- | --------------------- |
| `Restricted`   | App lacks required OS permission                         | Request permission    |
| `Unpaired`     | Permission granted, no QR scanned (`pairingCode` absent) | Open camera (scan QR) |
| `Connecting`   | QR scanned, service searching, no active link            | Stop service          |
| `Connected`    | Link active                                              | Disconnect            |
| `Disconnected` | Service stopped, device paired but no active link        | Start service         |

### macOS

| State          | When                                                         | Power button       |
| -------------- | ------------------------------------------------------------ | ------------------ |
| `Restricted`   | App lacks Bluetooth permission                               | Request permission |
| `Unpaired`     | Permission granted, no device paired (`pairedDevice` absent) | Open QR            |
| `Connecting`   | Device paired, service searching, no active link             | Stop service       |
| `Connected`    | Link active                                                  | Disconnect         |
| `Disconnected` | Service stopped, device paired but no active link            | Start service      |

---

## Status Line

Shows **system state only** — never last log entry.
Tapping always opens the Activity Log.

| State          | Status line text                                                                     |
| -------------- | ------------------------------------------------------------------------------------ |
| `Restricted`   | Android: "{Permission} access is required" / macOS: "Bluetooth access is required"   |
| `Unpaired`     | "No device paired"                                                                   |
| `Connecting`   | "Searching via WiFi" or "Searching via BLE"                                          |
| `Connected`    | "Connected via WiFi" or "Connected via BLE"                                          |
| `Disconnected` | "Connection lost" (if was connected) or "Ready to connect" (if never connected)      |

> Android scan-mode overrides status while camera is open:
>
> - "Point camera at QR code"

> macOS QR overlay overrides status while QR is open:
>
> - idle → "Scan QR code with Android"
> - Android connecting → "Waiting for device to connect"
> - error → the error message

---

## Android Flow

```
[Restricted]
  status: "{Permission} access is required"
  power button tap → request missing permission (or open Settings if permanently denied)
  granted + no pairingCode → [Unpaired]
  granted + pairingCode exists → [Connecting]

[Unpaired]
  status: "No device paired"
  power button tap → open camera (same as QR icon tap)
  QR scanned → store pairingCode → start service → [Connecting]

[Connecting]
  status: "Searching via WiFi" or "Searching via BLE"
  no notification
  power button tap → stop service → [Disconnected]
  close app → stop service → reopen → [Disconnected]
  connection + handshake succeed → [Connected]

[Connected]
  status: "Connected via WiFi" or "Connected via BLE"
  service in background, notification visible
  power button tap → disconnect → [Disconnected]
  close app → service stays alive, notification stays
  link drops → service retries (up to 2×) → [Disconnected]

[Disconnected]
  status: "Connection lost" (if hasBeenConnected) or "Ready to connect" (if !hasBeenConnected)
  service stopped, no notification
  power button tap → start service → [Connecting]
  close app → nothing (service already stopped)
  reopen app → stays [Disconnected], user must tap power button
```

## macOS Flow

```
[Restricted]
  status: "Bluetooth access is required"
  power button tap → request Bluetooth access
  granted + no pairedDevice → [Unpaired]
  granted + pairedDevice exists → [Connecting]

[Unpaired]
  status: "No device paired"
  power button tap → open QR (same as QR icon tap)
  QR icon tap → generate QR, show it, enter pairing mode
    status: "Scan QR code with Android"
    Android connects → status: "Waiting for device to connect"
    error → status: error message
    pairing succeeds → store pairedDevice → [Connected], close QR

[Connecting]
  status: "Searching via WiFi" or "Searching via BLE"
  no notification
  power button tap → stop → [Disconnected]
  connection succeeds → [Connected]

[Connected]
  status: "Connected via WiFi" or "Connected via BLE"
  no notification (menu bar item is the indicator)
  power button tap → disconnect → [Disconnected]
  link drops → retries (up to 2×) → [Disconnected]

[Disconnected]
  status: "Connection lost" (if hasBeenConnected) or "Ready to connect" (if !hasBeenConnected)
  no notification
  power button tap → start searching → [Connecting]
```

## State Detection Logic

### Android (`PowerButtonState.current`)

```
1. BLUETOOTH_CONNECT permission granted?  no → RESTRICTED
2. configStore.pairingCode != null?       no → UNPAIRED
3. serviceConnectionState == ACTIVE?     yes → CONNECTED
4. service running?                      yes → CONNECTING
                                          no → DISCONNECTED (hasBeenConnected → "Connection lost")
                                                             (!hasBeenConnected → "Ready to connect")
```

### macOS (`PowerButtonState.current`)

```
1. CBCentralManager.authorization ok?    no → RESTRICTED
2. store.pairedDevice != null?           no → UNPAIRED
3. connectionState == .active?          yes → CONNECTED
4. service running?                      yes → CONNECTING
                                          no → DISCONNECTED (hasBeenConnected → "Connection lost")
                                                             (!hasBeenConnected → "Ready to connect")
```
