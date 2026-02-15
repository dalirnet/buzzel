# Buzzel

**Your Android SMS, on your Mac. Privately.**

Buzzel bridges SMS from your Android phone to your Mac over a direct local connection — no cloud, no internet, no middleman. OTPs, verification codes, and important messages appear as native macOS notifications the moment they arrive, so you never have to reach for your phone while working.

Think of it as Apple's Continuity SMS, rebuilt for Android users who care about privacy.

## How It Works

- A lightweight macOS status bar app connects to a silent background service on your Android phone
- Communication happens entirely over **BLE or local WiFi** — your messages never leave your devices
- The Android app is **tiny** — under 1 MB, no bloat
- Set it up once, then forget about it — both apps stay completely out of your way

## Setup

1. Install the macOS app — an icon appears in your status bar
2. Install the Android app on your phone and open it once to grant permissions
3. A 6-digit pairing code appears on your phone
4. On your Mac, click the status bar icon, choose **Pair Device**, and enter the code
5. Done — you're connected

## Daily Use

Both apps stay completely out of your way:

- **macOS** — a small icon in your status bar, nothing else. No dock icon, no windows, no interruptions
- **Android** — a single quiet notification saying the service is running. That's it
- When an SMS arrives on your phone, a **macOS notification** pops up instantly
- Zero interaction required after setup

## Smart Copy

Buzzel scans each message and adds a **Copy** button to the notification when it detects actionable content:

| Detects                 | Example                    | Copies           |
| ----------------------- | -------------------------- | ---------------- |
| OTP / verification code | "Your code is **482107**"  | `482107`         |
| URL                     | "Click **https://a.co/x**" | `https://a.co/x` |
| Phone number            | "Call **+1-555-1234**"     | `+15551234`      |
| @mention                | "From **@john_doe**"       | `@john_doe`      |
| #hashtag                | "Use **#SAVE20**"          | `#SAVE20`        |

One button, first match, one click to copy. If nothing is detected, you just get the notification.

## Filters

Control which SMS get forwarded from the Mac settings:

- **No filters** = forward everything (default)
- **Add filters** to only forward what matters — by sender or message content
- Simple wildcard matching: `*OTP*`, `+98*`, `*Bank*`
- Quick presets for common patterns (OTP/verification, banking)

## Privacy

- **Nothing leaves your devices** — no cloud, no internet, no third-party servers
- **Direct connection only** — BLE or local WiFi between your paired devices
- **Messages are not stored** on the Mac — they arrive as notifications and that's it

## Requirements

- **Mac**: macOS 13.0 or later
- **Android**: Android 9 (API 28) or later
- Both devices need Bluetooth or to be on the same WiFi network
