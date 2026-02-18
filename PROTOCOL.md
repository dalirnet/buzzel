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
max_payload  = max_frame − 2          (frame header)
max_cmd_data = max_payload − 4        (signal + cmd + seq)
max_tlv_val  = max_cmd_data − 2       (tag + len)
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

| ID          | Signal        | Direction        | Payload                    |
| ----------- | ------------- | ---------------- | -------------------------- |
| `0x00`      | command       | both             | cmd(1) + seq(2) + TLV(0–N) |
| `0x01`      | pair.request  | Phone → Computer | code(6)                    |
| `0x02`      | pair.response | Computer → Phone | accepted(1) + reason(1)    |
| `0x03`      | ready         | both             | —                          |
| `0x04`      | ping          | both             | —                          |
| `0x05`      | pong          | both             | —                          |
| `0x06`      | ack           | both             | seq(2)                     |
| `0x07`      | goodbye       | both             | —                          |
| `0x08`      | unpair        | both             | —                          |
| `0x09–0xFF` | reserved      | —                | —                          |

### Payloads

Signals `0x03–0x05`, `0x07–0x08` have **no payload** — just the 1-byte signal ID.

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

| Offset | Field | Size | Description                 |
| ------ | ----- | ---- | --------------------------- |
| 0–1    | seq   | 2    | Sequence number being acked |

**command** — 3 + TLV:

| Offset | Field | Size | Description                  |
| ------ | ----- | ---- | ---------------------------- |
| 0      | cmd   | 1    | Command ID                   |
| 1–2    | seq   | 2    | Per-sender sequence number   |
| 3+     | data  | 0–N  | TLV pairs (N = max_cmd_data) |

### Wire Sizes

Total bytes on wire (frame header + signal byte + payload):

| Signal                                 | Wire bytes            |
| -------------------------------------- | --------------------- |
| ping / pong / ready / goodbye / unpair | **3**                 |
| pair.response / ack                    | **5**                 |
| pair.request                           | **9**                 |
| command                                | **6+** (6 + TLV data) |

## Keepalive

Runs only in `active` state.

- Both sides send `ping` every **30s**
- Reply with `pong` immediately
- No `pong` within **10s** → `idle`

```
Phone                          Computer
│                              │
│  [0x04] ping            ──►  │
│                         ◄──  │  [0x05] pong
│  ✓                           │
│                              │
│  [0x04] ping            ──►  │
│  ... 10s ...                 │
│  → idle                      │
```

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
Computer                               Phone
 │                                        │
 │  generate seed                         │
 │  derive session ID + code              │
 │  display QR                            │
 │                                        │
 │              ◄──── scan QR ────        │
 │                                        │
 │                    derive ID + code    │
 │                    connect             │
 │                                        │
 │   ◄── pair.request [code] ────────     │
 │                                        │
 │  validate code                         │
 │                                        │
 │   ──── pair.response [ok] ────────►    │
 │                                        │
 │  both → active                         │
```

### Reconnection

Already-paired devices skip pairing. Both sides send `ready` on `link.up` — no ordering, no waiting. First `ready` received → `active`. Seq numbers are **not** reset.

```
Computer                               Phone
 │                                        │
 │              ◄──── link.up ────        │
 │                                        │
 │   ──── ready ──────────────────────►   │
 │   ◄──── ready ─────────────────────    │
 │                                        │
 │  both → active                         │
```

### Failover During Active

If the link drops while `active`, session goes to `idle` and failover restarts. On reconnect, both sides exchange `ready`. Seq numbers continue from where they left off.

---

# 3. Command

> High-level commands carried as signal `0x00`.

## Structure

```
Frame:   [size 2B][0x00][cmd 1B][seq 2B][TLV data 0–NB]
          frame    sig   ──── command payload ────────────
```

- **cmd** — Command ID (`0x00–0xFF`, all reserved until assigned)
- **seq** — Per-sender sequence number, starts at 0, wraps at 65535

## TLV Data

```
[Tag 1B][Len 1B][Value 0–NB]  ...repeated
```

- **Tag** — Field identifier from a global registry (1 byte)
- **Len** — Value size in bytes (1 byte, max 255)
- **Value** — Raw bytes (UTF-8 for strings, big-endian for integers)

Single TLV value max is **255 bytes** (1-byte Len field). A command can carry multiple TLV pairs — total command data is limited by the transport, not by a single entry.

Same tag means the same thing across all commands.

## Reliable Delivery

Every command gets an `ack`.

```
Sender                              Receiver
  │                                    │
  │  [0x00] cmd seq=4 ──────────►      │
  │                  ◄── [0x06] ack 4  │
  │  ✓                                 │
```

- **Retry**: 5s timeout → resend same `seq` → 3 failures → `idle`
- **Dedup**: Receiver tracks last `seq`. Same `seq` → skip, re-ack

## Request / Response

Some commands come in pairs:

```
Phone                            Computer
│                                │
│  cmd=0x30 seq=5 ──────────►    │
│              ◄── ack [seq:5]   │  delivery confirmed
│                                │
│                                │  process...
│                                │
│              ◄── cmd=0x31 seq=8│  response
│  ack [seq:8] ──────────►       │
│                                │
```

Not every command needs a response. Some are one-way — ack confirms delivery, no response expected.

## Command IDs

All `0x00–0xFF` reserved. Assigned per feature as implemented.

## TLV Tag Registry

Tags are globally unique across all commands. Range `0x00–0xFF`.

| Tag | Name | Type | Description                         |
| --- | ---- | ---- | ----------------------------------- |
| —   | —    | —    | Assigned per feature as implemented |

## Adding a Command

1. Assign next available command ID
2. Define TLV tags from the global registry
3. If it needs a response, assign a paired response ID
4. Reliable delivery is automatic

---

# Message Flow

## Send

```
App Logic
  │
  ▼
Command ── build [0x00][cmd][seq][TLV]
  │
  ▼
Session ── track seq, start retry timer
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
        ── 0x01–0xFF: handle session signal
        ──   ping → pong
        ──   pong → reset timer
        ──   ack → mark delivered
        ──   pair / ready / goodbye / unpair
        ── 0x00: command
        ──   dedup by seq
        ──   send ack, pass to Command
  │
  ▼
Command ── dispatch by cmd ID → App Logic
```

---

# Example — Full Session

```
Phone                                                Computer
  │                                                    │
  │  (scan QR, derive code)                            │
  │                                                    │
  │  ── link.up ──────────────────────────────────►    │
  │                                                    │
  │  [0x01] pair.request [code]                  ──►   │
  │                                                    │  validate
  │                                              ◄──   │  [0x02] pair.response [ok]
  │                                                    │
  │  (both → active)                                   │
  │                                                    │
  │  [0x04] ping                                 ──►   │
  │                                              ◄──   │  [0x05] pong
  │                                                    │
  │  [0x00] cmd=0x30 seq=5 [TLV]                 ──►   │
  │                                              ◄──   │  [0x06] ack [seq:5]
  │  ✓                                                 │
  │                                                    │
  │                                              ◄──   │  [0x07] goodbye
  │                                                    │
  │  (→ idle)                                          │
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
- Signal IDs `0x09–0xFF` reserved for future use
- Command IDs `0x00–0xFF` reserved until assigned per feature
- TLV tags are globally unique — not scoped per command
