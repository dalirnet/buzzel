# Buzzel Protocol

Compact binary protocol for device communication over BLE or WiFi.

- Dynamic frame size — adapts to transport
- BLE or WiFi with automatic failover
- QR-based pairing with seed derivation
- Reliable delivery — ack, retry, dedup

```
┌───────────────────────────────┐
│  3. Command                   │  high-level commands
├───────────────────────────────┤
│  2. Session                   │  pairing, state, keepalive
├───────────────────────────────┤
│  1. Link                      │  BLE / WiFi, framing, failover
└───────────────────────────────┘
```

Two roles: **Phone** (smartphone, tablet) and **Computer** (desktop, laptop, notebook).

| Role    | Phone                    | Computer          |
| ------- | ------------------------ | ----------------- |
| BLE     | Peripheral (GATT Server) | Central           |
| WiFi    | TCP Client               | TCP Server        |
| Pairing | Scans QR code            | Generates QR code |

---

# 1. Link

> Raw byte delivery. No awareness of commands or sessions.

## Framing

Every message is wrapped in a length-prefixed frame:

```
┌──────────────┬───────────┐
│ 2 bytes (BE) │ N bytes   │
│ payload size │ payload   │
└──────────────┴───────────┘
```

Frame size is **dynamic** — determined by the transport.

- **BLE**: `max_frame = negotiated_MTU − 3` (3-byte ATT header)
- **WiFi**: `max_frame = 4096` (fixed cap)

Derived limits:

```
max_payload      = max_frame − 2           (frame header)
max_command_data = max_payload − 4         (signal + command.id + sequence)
max_tlv_value    = max_command_data − 2    (tag + length)
```

| MTU  | Max frame | Max command data | Max TLV value |
| ---- | --------- | ---------------- | ------------- |
| 23   | 20        | 14               | 12            |
| 185  | 182       | 176              | 174           |
| 247  | 244       | 238              | 236           |
| 512  | 509       | 503              | 501           |
| WiFi | 4096      | 4090             | 4088          |

Minimum ATT MTU is **23** (BLE default). At this level, session signals (pairing, keepalive, ack) all fit — the protocol works at any MTU. Only command data capacity is reduced on lower MTUs.

## BLE

| UUID                                   | Purpose                          |
| -------------------------------------- | -------------------------------- |
| `0000BF01-0000-1000-8000-00805F9B34FB` | Service                          |
| `0000BF02-0000-1000-8000-00805F9B34FB` | Data characteristic (read/write) |

Phone advertises the GATT service. Computer discovers and connects as central.

On connect, Computer **must** request the highest ATT MTU supported. The negotiated MTU sets the frame limit for the connection (`max_frame = MTU − 3`). All session signals fit at any MTU. Only command data capacity varies.

## WiFi

TCP socket on port **48155** (`0xBC1B`).
Computer listens as server. Phone connects as client using host from QR.

## Failover

Alternates transports until one connects:

```
preferred → fallback → preferred → fallback → …
```

- **10s** timeout per attempt
- Preferred transport from QR `prefer` field

## Link Events

| Event       | Meaning                                 |
| ----------- | --------------------------------------- |
| `link.up`   | BLE connected or TCP socket established |
| `link.down` | BLE disconnected or TCP socket closed   |
| `link.data` | Data received                           |

---

# 2. Session

> Connection lifecycle, pairing, and keepalive.

## Connection States

```
IDLE ──► CONNECTING ──► HANDSHAKING ──► ACTIVE
 ▲            │               │            │
 └────────────┴───────────────┴────────────┘
          timeout / error / link.down
```

| State         | Description                                      |
| ------------- | ------------------------------------------------ |
| `idle`        | No connection. Failover cycle trying transports. |
| `connecting`  | Link being established (BLE scan, TCP connect).  |
| `handshaking` | Link is up. Exchanging pairing or ready.         |
| `active`      | Connected. Commands flow. Keepalive running.     |

## State Transitions

| From          | To            | Trigger                                                      |
| ------------- | ------------- | ------------------------------------------------------------ |
| `idle`        | `connecting`  | Failover starts transport attempt                            |
| `connecting`  | `handshaking` | `link.up`                                                    |
| `connecting`  | `idle`        | 10s timeout                                                  |
| `handshaking` | `active`      | Received `ready` (reconnect) or `pair.response` (first pair) |
| `handshaking` | `idle`        | 30s timeout or invalid code                                  |
| `active`      | `idle`        | `goodbye`, `unpair`, pong timeout, `link.down`               |

## Signals

Every frame payload is a **signal**. The first byte identifies it.

```
[SSSSSSSS]  ← 8 bits: signal ID (0–255)
```

| ID          | Signal        | Direction        | Payload                                            |
| ----------- | ------------- | ---------------- | -------------------------------------------------- |
| `0x00`      | command       | both             | command.id(1) + sequence(2) + command.payload(0–N) |
| `0x01`      | pair.request  | Phone → Computer | code(6)                                            |
| `0x02`      | pair.response | Computer → Phone | accepted(1) + reason(1)                            |
| `0x03`      | ready         | both             | —                                                  |
| `0x04`      | ping          | both             | —                                                  |
| `0x05`      | pong          | both             | —                                                  |
| `0x06`      | ack           | both             | sequence(2)                                        |
| `0x07`      | goodbye       | both             | —                                                  |
| `0x08`      | unpair        | both             | —                                                  |
| `0x09`      | focus         | both             | —                                                  |
| `0x0A`      | blur          | both             | —                                                  |
| `0x0B–0xFF` | reserved      | —                | —                                                  |

### Payloads

Signals `0x03–0x05`, `0x07–0x0A` have **no payload** — just the 1-byte signal ID.

**pair.request** — 6 bytes:

| Offset | Field | Size | Description                 |
| ------ | ----- | ---- | --------------------------- |
| 0–5    | code  | 6    | Pairing code (ASCII digits) |

**pair.response** — 2 bytes:

| Offset | Field    | Size | Values                                                        |
| ------ | -------- | ---- | ------------------------------------------------------------- |
| 0      | accepted | 1    | `0x00` = no, `0x01` = yes                                     |
| 1      | reason   | 1    | `0x00` = none, `0x01` = invalid_code, `0x02` = already_paired |

**ack** — 2 bytes:

| Offset | Field    | Size | Description                 |
| ------ | -------- | ---- | --------------------------- |
| 0–1    | sequence | 2    | Sequence number being acked |

**command** — 3 + TLV:

| Offset | Field           | Size | Description                      |
| ------ | --------------- | ---- | -------------------------------- |
| 0      | command.id      | 1    | Command identifier               |
| 1–2    | sequence        | 2    | Per-sender sequence number       |
| 3+     | command.payload | 0–N  | TLV pairs (N = max_command_data) |

### Wire Sizes

Total bytes on wire (frame header + signal byte + payload):

| Signal                                                    | Wire bytes            |
| --------------------------------------------------------- | --------------------- |
| ping / pong / ready / goodbye / unpair / focus / blur     | **3**                 |
| pair.response / ack                                       | **5**                 |
| pair.request                                              | **9**                 |
| command                                                   | **6+** (6 + TLV data) |

## Keepalive

Runs only in `active` state.

- Both sides send `ping` every **10s**
- Reply with `pong` immediately
- No `pong` within **5s** → `idle`

```
Phone                                Computer
│                                        │
│  [0x04] ping ───────────────────────►  │
│                  ◄── [0x05] pong       │
│  ✓                                     │
│                                        │
│  [0x04] ping ───────────────────────►  │
│  ... 5s no pong ...                    │
│  → idle                                │
```

## Visibility

Sent when the app comes to or leaves the foreground. The receiving side uses this to bind or unbind visibility-triggered commands.

- App opens / comes to foreground → send `focus`
- App closes / goes to background → send `blur`

Only meaningful in `active` state.

## Pairing

### QR Payload

Generated by Computer. Fixed **24 bytes** (192 bits):

```
[magic 2B][seed 16B][host 4B][prefer 1B][reserved 1B]
```

| Field    | Size | Description                 |
| -------- | ---- | --------------------------- |
| Magic    | 2    | `0xBC1B`                    |
| Seed     | 16   | Random bytes                |
| Host     | 4    | IPv4 address (4 octets)     |
| Prefer   | 1    | `0x00` = wifi, `0x01` = ble |
| Reserved | 1    | `0x00`                      |

### Seed Derivation

Both sides derive from `seed`:

| Value        | Derivation                                                                                        |
| ------------ | ------------------------------------------------------------------------------------------------- |
| Session ID   | First 16 bytes of `SHA256(seed)` as UUID                                                          |
| Pairing code | `SHA256(seed + "code")` → first 4 bytes as big-endian uint32 → `% 1000000` → zero-pad to 6 digits |
| Port         | Fixed `48155`                                                                                     |

### Pairing Flow

```
Computer                                          Phone
 │                                                    │
 │  generate seed                                     │
 │  derive session ID + code                          │
 │  display QR                                        │
 │                                                    │
 │                    ◄──── scan QR ────              │
 │                                                    │
 │                          derive ID + code          │
 │                          connect                   │
 │                                                    │
 │              ◄── pair.request [code] ───────────   │
 │                                                    │
 │  validate code                                     │
 │                                                    │
 │  pair.response [ok] ───────────────────────────►   │
 │                                                    │
 │  both → active                                     │
```

### Reconnection

Already-paired devices skip pairing. Both sides send `ready` on `link.up` — no ordering, no waiting. First `ready` received → `active`. Sequence numbers are **not** reset.

```
Computer                                          Phone
 │                                                    │
 │                    ◄──── link.up ────              │
 │                                                    │
 │  ready ────────────────────────────────────────►   │
 │                    ◄──── ready ─────────────────   │
 │                                                    │
 │  both → active                                     │
```

### Failover During Active

If the link drops while `active`, session goes to `idle` and failover restarts. On reconnect, both sides exchange `ready`. Sequence numbers continue from where they left off.

---

# 3. Command

> High-level commands carried as signal `0x00`.

Commands are not triggered by the user. They run automatically in response to system events (clipboard change, SMS received, battery update, etc.).

## Structure

```
Frame: [size 2B][0x00][command.id 1B][sequence 2B][command.payload 0–NB]
        frame    signal ─────────────────── command ───────────────────
```

- **command.id** — command identifier (`0x00–0xFF`, all reserved until assigned)
- **command.payload** — zero or more TLV fields
- **sequence** — per-sender sequence number, starts at 0, wraps at 65535

The command layer only deals with **command.id** and **command.payload**. Sequence numbers, ACK, and retry are transparent.

## TLV Data

```
[Tag 1B][Length 1B][Value 0–NB]  ...repeated
```

- **Tag** — Field identifier from a global registry (1 byte)
- **Length** — Value size in bytes (1 byte, max 255)
- **Value** — Raw bytes (UTF-8 for strings, big-endian for integers)

Single TLV value max is **255 bytes** (1-byte Length field). A command can carry multiple TLV pairs — total command data is limited by the transport, not by a single entry.

Same tag means the same thing across all commands.

## Reliable Delivery

Every command gets an `ack`.

```
Sender                                            Receiver
  │                                                    │
  │  [0x00] command.id=0x01 sequence=4 ─────────────►  │
  │                          ◄── [0x06] ack 4          │
  │  ✓                                                 │
```

- **Retry**: 5s timeout → resend same `sequence` → 3 failures → `idle`
- **Dedup**: Receiver tracks last `sequence`. Same `sequence` → skip, re-ack

## Request / Response

Some commands come in pairs:

```
Phone                                              Computer
│                                                      │
│  command.id=0x30 sequence=5 ──────────────────────►  │
│                        ◄── ack [sequence:5]          │  delivery confirmed
│                                                      │
│                                                      │  process...
│                                                      │
│              ◄── command.id=0x31 sequence=8          │  response
│  ack [sequence:8] ────────────────────────────────►  │
│                                                      │
```

Not every command needs a response. Some are one-way — ack confirms delivery, no response expected.

## Trigger

Each command declares when it should be bound/unbound:

| Trigger        | Bind on            | Unbind on          |
| -------------- | ------------------ | ------------------ |
| `connection`   | session `active`   | session `idle`     |
| `visibility`   | remote `focus`     | remote `blur`      |

## Shared Definition

Each command has its own definition file in `commands/`. One file per command, kebab-case name. This is the authoritative spec — both platforms hardcode matching constants in their native code.

```json
{
    "id": "0x01",
    "name": "clipboard-sync",
    "description": "Share clipboard text",
    "trigger": "visibility",
    "payload": [{ "tag": "0x01", "name": "text", "type": "string" }]
}
```

**Rules:**

- Command IDs: sequential (`0x01`, `0x02`, …), range `0x00–0xFF`
- TLV tags: globally unique across all commands, range `0x00–0xFF`
- Reuse tags when the meaning matches across commands
- No direction — each platform decides which side it plays

## BuzzelCommand

Abstract base class. Every command subclasses it.

```
class BuzzelCommand {
  var id: UInt8 { 0 }                              // override with command ID
  var trigger: Trigger { .connection }             // override: .connection or .visibility
  var output: ((UInt8, Data) -> Void)?              // injected on register

  func bind() { }                                  // set up system observers
  func unbind() { }                                // tear down system observers
  func handle(fields: [TlvField]) { }             // process incoming command
}
```

- **`id`** — command ID, overridden by each subclass
- **`trigger`** — `connection` or `visibility`. Determines when `bind`/`unbind` are called.
- **`output`** — closure injected by `CommandHandler` on register. Sends outgoing data to transport layer.
- **`bind`** — set up system observers. When an observer fires, build TLV payload and call `output?(id, payload)`.
- **`unbind`** — tear down observers, clean up.
- **`handle`** — process incoming command. Parse fields, execute the action.

### Outgoing vs Incoming

| Direction | Method            | Trigger          | What it does                                             |
| --------- | ----------------- | ---------------- | -------------------------------------------------------- |
| Outgoing  | `bind()`          | System event     | Set up observer → build payload → `output?(id, payload)` |
| Incoming  | `handle(fields:)` | Received command | Parse fields → execute system action                     |

A platform implements `bind` (outgoing), `handle` (incoming), or both.

## CommandHandler

Registry and dispatcher, decoupled from transport layer via closure.

```
class CommandHandler {
  private var commands: [UInt8: BuzzelCommand]
  private let output: (UInt8, Data) -> Void

  init(output: (UInt8, Data) -> Void)

  func register(_ command: BuzzelCommand)            // store command, inject output
  func dispatch(_ command: Command)                  // decode TLV, call command.handle

  func bindAll(trigger: Trigger)                     // bind commands matching trigger
  func unbindAll(trigger: Trigger)                   // unbind commands matching trigger
}
```

- **Init** — takes an `output` closure that bridges to transport layer
- **Register** — stores command by ID and injects `output` closure into it
- **Dispatch** — finds command by ID, decodes TLV fields, calls `command.handle(fields:)`
- **Bind/Unbind** — filters by trigger, propagates to matching commands
- Unknown command IDs are logged and ignored

## Command Flow

```
System event (e.g. clipboard change)
  │
  ▼
bind() observer fires
  │ build TLV payload
  ▼
output?(id, payload)
  │
  ▼
transport layer (session → link → wire)
  │
  ═══ wire ═══
  │
  ▼
CommandHandler.dispatch(command)
  │ decode TLV fields
  ▼
command.handle(fields:)
  │ execute action
  ▼
System action (e.g. write to clipboard)
```

## File Structure

```
commands/
  clipboard-sync.json                ← shared definition

macos/Sources/Commands/
  CommandHandler.swift               ← BuzzelCommand base + dispatcher
  ClipboardSync.swift                ← 0x01

android/.../commands/
  CommandHandler.kt                  ← BuzzelCommand base + dispatcher
  ClipboardSync.kt                   ← 0x01
```

## Adding a Command

1. Create `commands/<name>.json` — assign next command ID, define TLV tags
2. If the command needs a paired response, assign a separate response command ID
3. Create `<Name>.swift` — subclass `BuzzelCommand`, implement `bind`/`unbind`/`handle`
4. Create `<Name>.kt` — subclass `BuzzelCommand`, implement `bind`/`unbind`/`handle`
5. Register in `CommandHandler` on both platforms
6. Add protocol tests for payload round-trip

## clipboard-sync (`0x01`)

Both sides can share clipboard text with each other. Triggered automatically when the system clipboard changes.

**Definition** (`commands/clipboard-sync.json`):

```json
{
    "id": "0x01",
    "name": "clipboard-sync",
    "description": "Share clipboard text",
    "trigger": "visibility",
    "payload": [{ "tag": "0x01", "name": "text", "type": "string" }]
}
```

**Sample** (`ClipboardSync`):

```swift
class ClipboardSync: BuzzelCommand {
  override var id: UInt8 { 0x01 }
  override var trigger: Trigger { .visibility }

  override func bind() {
    // observe system clipboard changes
    // when changed → skip if text == lastWrittenText (echo guard)
    //              → output?(id, tlvEncodeString(tag: 0x01, value: text))
  }

  override func unbind() {
    // stop observing
  }

  override func handle(fields: [TlvField]) {
    // extract text from tag 0x01
    // lastWrittenText = text (echo guard)
    // write to system clipboard
  }
}
```

---

# Message Flow

## Send

```
App Logic
  │
  ▼
Command ── build [0x00][command.id][sequence][command.payload]
  │
  ▼
Session ── track sequence, start retry timer
  │
  ▼
Link ────── frame [size][payload] → BLE / TCP
  │
  ═══ wire ═══
```

## Receive

```
  ═══ wire ═══
  │
Link ────── decode frame → payload
  │
  ▼
Session ── read signal ID (byte 0)
        ── 0x01–0x0A: handle session signal
        ──   ping → pong
        ──   pong → reset timer
        ──   ack → mark delivered
        ──   focus → bindAll(.visibility)
        ──   blur → unbindAll(.visibility)
        ──   pair / ready / goodbye / unpair
        ── 0x00: command
        ──   dedup by sequence
        ──   send ack, pass to Command
  │
  ▼
Command ── dispatch by command.id → App Logic
```

---

# Example — Full Session

```
Phone                                                    Computer
  │                                                          │
  │  (scan QR, derive code)                                  │
  │                                                          │
  │  ── link.up ──────────────────────────────────────────►  │
  │                                                          │
  │  [0x01] pair.request [code] ──────────────────────────►  │
  │                                                          │  validate
  │                    ◄── [0x02] pair.response [ok]          │
  │                                                          │
  │  (both → active)                                         │
  │                                                          │
  │  [0x09] focus ────────────────────────────────────────►  │
  │                    ◄── [0x09] focus                       │
  │                                                          │
  │  [0x04] ping ─────────────────────────────────────────►  │
  │                    ◄── [0x05] pong                        │
  │                                                          │
  │  [0x00] command.id=0x01 sequence=0 [TLV] ─────────────►  │
  │                    ◄── [0x06] ack [sequence:0]            │
  │  ✓                                                       │
  │                                                          │
  │  [0x0A] blur ─────────────────────────────────────────►  │
  │                                                          │
  │                    ◄── [0x07] goodbye                     │
  │                                                          │
  │  (→ idle)                                                │
```

---

# Designed For

- Small, infrequent commands over local network or BLE
- Trusted environments — no encryption, no security guarantees
- Simple QR pairing — no accounts, no cloud

# Known Limitations

- No encryption or authentication beyond pairing
- No fragmentation — command data limited by transport
- No pipelining — one command in-flight per sender
- No error reporting — malformed data silently dropped
- No versioning — both sides must match
- IPv4 only — no IPv6, no mDNS
- Single connection — one phone, one computer

# Notes

- All integer fields are big-endian
- Signal IDs `0x0B–0xFF` reserved for future use
- Command IDs `0x00–0xFF` reserved until assigned per feature
- TLV tags are globally unique — not scoped per command
