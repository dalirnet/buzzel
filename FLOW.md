# User Flow

## States

### Android

| State          | When                                                     | Power button                                    |
| -------------- | -------------------------------------------------------- | ----------------------------------------------- |
| `Restricted`   | App lacks required OS permission (Camera, BT, Location)  | Request permission (or open Settings if denied) |
| `Unpaired`     | Permission granted, no QR scanned (`pairingCode` absent) | Open camera (scan QR)                           |
| `Connecting`   | QR scanned, service searching, no active link            | Stop service                                    |
| `Connected`    | Link active                                              | Disconnect                                      |
| `Disconnected` | Service stopped, device paired but no active link        | Start service                                   |

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

| State          | Status line text                                                                   |
| -------------- | ---------------------------------------------------------------------------------- |
| `Restricted`   | Android: "{Permission} access is required" / macOS: "Bluetooth access is required" |
| `Unpaired`     | "No device paired"                                                                 |
| `Connecting`   | "Searching via WiFi" or "Searching via BLE" (fallback: "Searching for device")     |
| `Connected`    | "Connected via WiFi" or "Connected via BLE" (fallback: "Connected")                |
| `Disconnected` | "Connection lost" (if was connected) or "Ready to connect" (if never connected)    |

> Android: `{Permission}` resolves to the first missing permission label: "Camera", "Bluetooth", "Location", or "Notification".

> Android scan-mode overrides status while camera is open:
>
> - "Point camera at QR code"

> macOS QR overlay overrides status while QR is open:
>
> - idle → "Scan QR code with Android"
> - Android connecting → "Waiting for device to connect"
> - error → the error message

---

## Transport Preference

Both platforms store a `transportMethod` setting: `"auto"` (default), `"wifi"`, or `"ble"`.

- **macOS auto-detect**: checks WiFi availability at runtime via `NWPathMonitor`; if WiFi is available → WiFi first, otherwise → BLE first.
- **Failover** (macOS): on connection failure, automatically tries the other transport (e.g. WiFi fails → try BLE).

---

## Android Flow

```
[Restricted]
  status: "{Permission} access is required"
  power button tap → request missing permissions (or open Settings if permanently denied)
  granted + no pairingCode → [Unpaired]
  granted + pairingCode exists → [Connecting]

[Unpaired]
  status: "No device paired"
  power button tap → open camera
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
  power button tap → open QR, generate code, enter pairing mode
    status: "Scan QR code with Android"
    Android connects → status: "Waiting for device to connect"
    error → status: error message
    pairing succeeds → store pairedDevice → [Connected], close QR

[Connecting]
  status: "Searching via WiFi" or "Searching via BLE"
  power button tap → stop → [Disconnected]
  failover: if primary transport fails → try secondary
  connection succeeds → [Connected]

[Connected]
  status: "Connected via WiFi" or "Connected via BLE"
  no notification (menu bar item is the indicator)
  power button tap → disconnect → [Disconnected]
  link drops → retries (up to 2×) → [Disconnected]

[Disconnected]
  status: "Connection lost" (if hasBeenConnected) or "Ready to connect" (if !hasBeenConnected)
  power button tap → start searching → [Connecting]
```

## State Detection Logic

### Android (`MainActivity.computeState`)

```
hasAllPermissions()?
│  CAMERA, BLUETOOTH_CONNECT*, BLUETOOTH_ADVERTISE*, BLUETOOTH_SCAN*
│  (* API 31+; on older: ACCESS_FINE_LOCATION instead)
│
├─ no ──► RESTRICTED
│
└─ yes ──► pairingCode != null?
            │
            ├─ no ──► UNPAIRED
            │
            └─ yes ──► connectionState == ACTIVE?
                        │
                        ├─ yes ──► CONNECTED
                        │
                        └─ no ──► service running?
                                   │
                                   ├─ yes ──► CONNECTING
                                   │
                                   └─ no ──► DISCONNECTED
                                              ├─ hasBeenConnected    → "Connection lost"
                                              └─ !hasBeenConnected   → "Ready to connect"
```

### macOS (`PowerButtonState.current`)

```
CBCentralManager.authorization ok?
│
├─ no ──► RESTRICTED
│
└─ yes ──► pairedDevice != null?
            │
            ├─ no ──► UNPAIRED
            │
            └─ yes ──► connectionState == .active?
                        │
                        ├─ yes ──► CONNECTED
                        │
                        └─ no ──► service running?
                                   │
                                   ├─ yes ──► CONNECTING
                                   │
                                   └─ no ──► DISCONNECTED
                                              ├─ hasBeenConnected    → "Connection lost"
                                              └─ !hasBeenConnected   → "Ready to connect"
```
