# User Flow

## States

### Android

| State          | When                                                     | Power button                                    |
| -------------- | -------------------------------------------------------- | ----------------------------------------------- |
| `Restricted`   | App lacks required OS permission (Camera, BT, Location)  | Request permission (or open Settings if denied) |
| `Unpaired`     | Permission granted, no QR scanned (`pairingCode` absent) | Open camera (scan QR)                           |
| `Connecting`   | QR scanned, service searching, no active link            | Soft disconnect (keep pairing)                  |
| `Connected`    | Link active                                              | Soft disconnect (keep pairing)                  |
| `Disconnected` | Service stopped, device paired but no active link        | Start service                                   |

### macOS

| State          | When                                                         | Power button                   |
| -------------- | ------------------------------------------------------------ | ------------------------------ |
| `Restricted`   | App lacks Bluetooth permission                               | Request permission             |
| `Unpaired`     | Permission granted, no device paired (`pairedDevice` absent) | Open QR                        |
| `Connecting`   | Device paired, service searching, no active link             | Soft disconnect (keep pairing) |
| `Connected`    | Link active                                                  | Soft disconnect (keep pairing) |
| `Disconnected` | Service stopped, device paired but no active link            | Start service                  |

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

- **Android auto-detect**: checks WiFi via `ConnectivityManager`; if WiFi available → WiFi first, otherwise → BLE first.
- **macOS auto-detect**: checks WiFi availability at runtime via `NWPathMonitor`; if WiFi is available → WiFi first, otherwise → BLE first.
- **Failover** (both): on connection failure (10s timeout), automatically tries the other transport (e.g. WiFi fails → try BLE, then cycles).

---

## Connection Flow

### Pairing (first time)

```
Android                                              macOS
────────                                             ─────
User scans QR code                        User shows QR code
     │                                         │
     ▼                                         ▼
Derive pairing code                   startPairingMode(id, code)
Start service                                  │
     │                                         ▼
     ▼                                Start BOTH transports
startFailover()                       (BLE scan + TCP listen)
     │                                         │
     ▼                                         │
┌──────────┐     BLE or WiFi      ┌────────────┘
│CONNECTING│◄────────────────────►│CONNECTING
└────┬─────┘                      └────┬───────
     │ transport connects              │ transport connects
     ▼                                 ▼
HANDSHAKING                       HANDSHAKING
     │                                 │
     │  ──── PAIR_REQUEST ────►        │
     │       (6-digit code)            │  verify code
     │                                 │
     │  ◄─── PAIR_RESPONSE ────        │
     │       (accepted/rejected)       │
     │                                 │
     ▼                                 ▼
  ACTIVE ◄────────────────────────► ACTIVE
```

### Reconnection (already paired)

```
Android                                              macOS
────────                                             ─────
startFailover()                             startFailover()
     │                                           │
     ▼                                           ▼
Try preferred transport                 Try preferred transport
(auto/wifi/ble)                         (auto/wifi/ble)
     │                                           │
     ├─ wifi? → TcpClient.connect()              ├─ wifi? → TcpServer.start()
     │          to macOS:48155                    │
     ├─ ble?  → GattServer.start()               ├─ ble?  → BleCentral.start()
     │          + advertise                       │           scan
     │                                           │
     │◄─── 10s timeout? advance ───►             │
     │     to other transport                    │
     │                                           │
     ▼ connected                                 ▼ connected
HANDSHAKING                                 HANDSHAKING
     │                                           │
     │  ──── READY ─────────────────────►        │
     │  ◄─── READY ─────────────────────         │
     │                                           │
     ▼                                           ▼
  ACTIVE ◄──────────────────────────────►     ACTIVE
```

### Keepalive (while ACTIVE)

```
Every 10s:  ──── PING ────►
            ◄─── PONG ────

No PONG within 5s? → handleDisconnect()
                     retry up to 2× then stop
```

### BLE data flow (Android = GATT server, macOS = central)

```
Android (GATT Server)                   macOS (Central)
─────────────────────                   ──────────────
Advertise service UUID                  Scan for UUID
     │                                       │
     ◄──────── Central connects ─────────────┘
     │
     ◄──────── Discover service + characteristic
     │
     ◄──────── Subscribe to CCCD (enable notifications)
     │
★ NOW isConnected = true
★ onConnectionChanged(true) fires
     │
Send: frame → chunks by MTU → notify each chunk
      wait for onNotificationSent on EVERY chunk

Recv: onCharacteristicWrite → recvBuffer → extractFrames
```

### Failover state machine

```
      ┌──────┐
      │ IDLE │◄──────── handleDisconnect()
      └──┬───┘          (retry ≤ 2×, then stop)
         │
   startFailover()
         │
         ▼
   ┌────────────┐ ──10s timeout──► try other transport ──┐
   │ CONNECTING │◄───────────────────────────────────────┘
   └─────┬──────┘
         │ transport connected
         ▼
   ┌──────────────┐ ──30s timeout──► handleDisconnect()
   │ HANDSHAKING  │
   └──────┬───────┘
          │ READY / PAIR_RESPONSE(ok)
          ▼
   ┌────────┐
   │ ACTIVE │ ── pong timeout / goodbye / unpair ──► IDLE
   └────────┘
```

### Key rules

- **BLE "connected" = physical link + CCCD subscribed** — data never sent before central is ready.
- **Stale callbacks ignored** — both connect and disconnect checked against failover generation (Android).
- **Single reconnect owner** — only TransportManager handles retry; BleCentral/GattServer never reconnect independently.
- **Pairing rejection = clean stop** — pairing state cleared immediately, no futile retry loop.
- **Goodbye delivery guaranteed** — Android uses `CountDownLatch`, macOS polls BLE write queue up to 2s.
- **TCP disconnect only fires if connected** — failed connect attempts don't trigger spurious disconnect handling.

### Disconnect vs Unpair

Two distinct ways to end a connection:

| Action                             | Signal         | Pairing data | Other side                    | Use case                             |
| ---------------------------------- | -------------- | ------------ | ----------------------------- | ------------------------------------ |
| **Soft disconnect** (power button) | GOODBYE (0x07) | Kept         | Starts searching (CONNECTING) | Temporary — can reconnect without QR |
| **Unpair** (settings menu)         | UNPAIR (0x08)  | Cleared      | Clears pairing, stops         | Permanent — requires new QR scan     |

**Orbit device name colors:**

- **Green** background — device is connected
- **Red** background — device is paired but disconnected (soft disconnect or connection lost)
- **Hidden** — no device paired

**On receiving GOODBYE:** The other side keeps pairing data and starts failover to reconnect automatically.

**On receiving UNPAIR:** The other side clears all pairing data and goes to UNPAIRED state.

**App quit/task removed:** Treated as soft disconnect — pairing data persists across app launches.

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
  power button tap → soft disconnect (send GOODBYE, keep pairing) → [Disconnected]
  close app → stop service (keep pairing) → reopen → [Disconnected]
  connection + handshake succeed → [Connected]

[Connected]
  status: "Connected via WiFi" or "Connected via BLE"
  service in background, notification visible
  power button tap → soft disconnect (send GOODBYE, keep pairing) → [Disconnected]
  settings "Unpair Device" → send UNPAIR, clear pairing → [Unpaired]
  close app → service stays alive, notification stays
  link drops → service retries (up to 2×) → [Disconnected]

[Disconnected]
  status: "Connection lost" (if hasBeenConnected) or "Ready to connect" (if !hasBeenConnected)
  service stopped, pairing data preserved
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
  power button tap → soft disconnect (send GOODBYE, keep pairing) → [Disconnected]
  failover: if primary transport fails → try secondary
  connection succeeds → [Connected]

[Connected]
  status: "Connected via WiFi" or "Connected via BLE"
  no notification (menu bar item is the indicator)
  power button tap → soft disconnect (send GOODBYE, keep pairing) → [Disconnected]
  settings "Unpair Device" → send UNPAIR, clear pairing → [Unpaired]
  link drops → retries (up to 2×) → [Disconnected]

[Disconnected]
  status: "Connection lost" (if hasBeenConnected) or "Ready to connect" (if !hasBeenConnected)
  pairing data preserved
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
