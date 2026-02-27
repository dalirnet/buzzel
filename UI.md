# Buzzel UI

Dark and light mode. macOS uses pt, Android uses dp.

Android applies per-type scale factors for visual parity on phone screens:

| Type       | Scale | Applies to                                |
| ---------- | ----- | ----------------------------------------- |
| Layout     | 1.25x | Spacing, padding, margins, element sizing |
| Typography | 1.15x | Font sizes                                |
| Detail     | 1.0x  | Dots, dividers, small decorative elements |

---

## Design Tokens

### Colors

Resolved from platform system colors. macOS uses native color tokens directly. Android uses system theme attributes where reliable, with hardcoded fallbacks for older devices (pre-Android 10).

| Token       | Android                        | macOS                    | Usage                  |
| ----------- | ------------------------------ | ------------------------ | ---------------------- |
| `text`      | `textColorPrimary` / hardcoded | `.labelColor`            | Primary text, logo     |
| `secondary` | `textColorSecondary` / gray    | `.secondaryLabelColor`   | Secondary text, badges |
| `surface`   | hardcoded per theme            | `.windowBackgroundColor` | Window background      |
| `border`    | `text` at 12% opacity          | `.separatorColor`        | Dividers, drag handle  |
| `accent`    | `colorAccent`                  | `.controlAccentColor`    | QR icon, orbit dots    |
| `green`     | system green                   | `.systemGreen`           | Success, orbit dots    |
| `orange`    | system orange                  | `.systemOrange`          | Connecting, orbit dots |
| `yellow`    | system yellow                  | `.systemYellow`          | Device planet idle     |
| `red`       | system red                     | `.systemRed`             | Error, disconnected    |
| `gray`      | system gray                    | `.systemGray`            | Unpaired               |
| `onButton`  | white                          | `.white`                 | Icon on power button   |

Android dark mode: Android 10+ uses `UI_MODE_NIGHT_MASK`. Older devices may use vendor-specific `Settings.Secure` values (`theme_mode`: 1=light, 2=dark).

#### Muted Colors (Power Button Fill)

Soft adaptive fills per theme.

| Token         | Light            | Dark             | State         |
| ------------- | ---------------- | ---------------- | ------------- |
| `mutedGray`   | 0.55, 0.55, 0.58 | 0.45, 0.45, 0.48 | Unpaired      |
| `mutedYellow` | 0.95, 0.78, 0.10 | 0.92, 0.75, 0.08 | No permission |
| `mutedOrange` | 0.95, 0.55, 0.10 | 0.92, 0.50, 0.08 | Connecting    |
| `mutedGreen`  | 0.20, 0.75, 0.38 | 0.18, 0.70, 0.35 | Connected     |
| `mutedRed`    | 0.90, 0.28, 0.25 | 0.85, 0.25, 0.22 | Disconnected  |

### Typography

Sofia Sans (`assets/sofia-sans.ttf`). Variable font, all weights embedded.

| Token        | Size | Weight   | Notes |
| ------------ | ---- | -------- | ----- |
| `title`      | 13   | Semibold |       |
| `body`       | 14   | Regular  |       |
| `statusLine` | 12   | Regular  |       |
| `badge`      | 10   | Regular  |       |
| `logEntry`   | 13   | Regular  |       |
| `logTime`    | 11   | Regular  |       |
| `logDir`     | 9    | Medium   |       |

### Spacing

Base unit: **4**.

| Token | Value |
| ----- | ----- |
| `xs`  | 4     |
| `sm`  | 8     |
| `md`  | 12    |
| `lg`  | 16    |
| `xl`  | 24    |
| `2xl` | 32    |
| `3xl` | 48    |

### Sizing

| Token        | Value | Used for              |
| ------------ | ----- | --------------------- |
| `icon.sm`    | 16    | App logo in header    |
| `icon.md`    | 20    | Header trailing icon  |
| `button.sm`  | 94    | Power button diameter |
| `button.lg`  | 126   | Content frame, QR     |
| `orbit.area` | 294   | Orbit rings container |

### Layout

| Element             | Value         | Notes                     |
| ------------------- | ------------- | ------------------------- |
| Header height       | 48            |                           |
| Header padding      | 16 x 12       | Horizontal x Vertical     |
| Logo ↔ title gap    | 10            |                           |
| Power button        | 94 in 126     | Centered in content frame |
| QR code             | 150           | Circular                  |
| Status line bottom  | 24            | Bottom padding            |
| Status line padding | 16 x 8        | Horizontal x Vertical     |
| Status line bg      | secondary 5%  | Capsule, single line      |
| Badge padding       | 8 x 4         | Horizontal x Vertical     |
| Badge radius        | 4             |                           |
| Badge bg            | secondary 10% |                           |
| Window (macOS)      | 360 x 640     | Fixed size, 9:16          |
| Sheet (Android)     | 320 height    | Bottom sheet              |
| Min touch target    | 44            |                           |

### Animation

| Animation      | Duration | Curve                     | Notes                                               |
| -------------- | -------- | ------------------------- | --------------------------------------------------- |
| Halo pulse     | 2000ms   | easeInOut                 | Scale 1.15→1.30, opacity 5%→10%, repeat, all states |
| Button pulse   | 900ms    | easeInOut                 | Scale 1.0→0.88, repeat, connecting state only       |
| State color    | 300ms    | easeInOut                 | Smooth color interpolation                          |
| Tap press      | spring   | response 0.3, damping 0.5 | Scale to 0.85, ripple ring to 1.3x at 30% opacity   |
| Tap release    | 200ms    |                           | Returns to normal                                   |
| Content switch | 250ms    | easeIn then spring        | Scale to 0, swap at 120ms, spring back to 1.0       |
| Typewriter     | 35ms/ch  |                           | Delete chars then type new chars                    |
| Status flip    | 250ms    | easeInOut then spring     | 3D rotation on X-axis                               |
| Orbit fade-in  | 800ms    | easeIn                    | Opacity 0→1 on appear                               |
| Orbit rotation | 12–25s   | linear                    | Starts after 1s delay, synced to display refresh    |
| Menu bar blink | 1000ms   | toggle                    | macOS only                                          |

---

## Views

Three view states, navigated in-window (no separate windows):

| View         | Title          | Badge       | Trailing Icon | Trailing Action |
| ------------ | -------------- | ----------- | ------------- | --------------- |
| Main         | "Buzzel"       | Device name | `settings`    | Open settings   |
| Quick Setup  | "Quick Setup"  | —           | `zap`         | Back to Main    |
| Activity Log | "Activity Log" | Entry count | `zap`         | Back to Main    |

### Header

Persistent across views, content updates in place.

- **Left**: App logo (`icon.sm`) + title with typewriter animation + contextual badge
- **Right**: Trailing icon button (`icon.md`)
- Main view: settings icon (gear). Sub-views (Quick Setup, Activity Log): zap icon
- Badge: `secondary` text on `secondary` 10% background, radius 4

### Orbit Rings

Three concentric rings with orbiting dots around the center content area. Fades in (800ms easeIn), rotation starts after 1s delay. Pauses when window loses focus, resumes on regain.

- Container: 294 x 294
- Ring stroke: 1pt, `secondary` at 8% opacity

| Ring   | Radius | Duration | Direction         | Dots                       |
| ------ | ------ | -------- | ----------------- | -------------------------- |
| Inner  | 84     | 12s      | Clockwise         | 6pt `accent`, 4pt `green`  |
| Middle | 110    | 18s      | Counter-clockwise | 5pt `orange`, 3pt `accent` |
| Outer  | 136    | 25s      | Clockwise         | 4pt `red`, 3pt `green`     |

Each dot: 60% opacity fill with a glow circle behind it (40% opacity, 1.8x dot diameter).

**Device planet**: When paired, the device name orbits on the middle ring as a capsule label (8pt font). Color reflects connection state: `red` disconnected, `green` remote focused, `yellow` idle.

### Power Button

Circular button at `button.sm` (94), centered in the orbit area.

**Layers (inner to outer):**

1. State icon — 45% of button diameter, `onButton` color, filled
2. Solid circle — `mutedColor` fill, pulses when connecting
3. Ripple ring — state color stroke, appears on tap only
4. Halo — state color, continuous pulse animation

| State                | Color         | Icon           | Notes              |
| -------------------- | ------------- | -------------- | ------------------ |
| Restricted           | `mutedYellow` | `fingerAccess` | Request permission |
| Unpaired             | `mutedGray`   | `zap`          |                    |
| Connecting           | `mutedOrange` | `loading`      | Spins continuously |
| Connected            | `mutedGreen`  | `zap`          |                    |
| Disconnected (ready) | `mutedRed`    | `play`         | Never connected    |
| Disconnected (lost)  | `mutedRed`    | `unlink`       | Was connected      |

### Circular QR Code

120pt circular clip with dot-style modules. Center logo cutout at 28% radius with `BuzzelLogoView` at 45% of cutout size (0.28 × 0.45). Uses "H" error correction (30%).

### Status Line

Pinned to the bottom of the main view. Capsule shape, single line, truncated with ellipsis.

| State        | Text                                                                               |
| ------------ | ---------------------------------------------------------------------------------- |
| Restricted   | Android: "{Permission} access is required" / macOS: "Bluetooth access is required" |
| Unpaired     | "No device paired"                                                                 |
| Connecting   | "Searching via WiFi" or "Searching via BLE" (fallback: "Searching for device")     |
| Connected    | "Connected via WiFi" or "Connected via BLE" (fallback: "Connected")                |
| Disconnected | "Connection lost" (if was connected) or "Ready to connect" (if never connected)    |

Text changes animate with a 3D flip on X-axis. Tapping always opens the Activity Log.

### Activity Log

Scrollable list, newest entries first. Maximum 100 entries retained.

Each row:

- Status dot: 8pt circle, `green` for success, `red` for failure
- Message: `logEntry` size, `text` color, 2 lines max
- Error detail (optional): `logTime` size, `red` color, 1 line max
- Timestamp: `logTime` size, `secondary` color, right-aligned
- Direction (optional): `logDir` size, `secondary` color — "IN" or "OUT"
- Divider between rows, indented 28pt past the dot

Empty state: "No activity yet" centered in `secondary` color.

---

## Platform Differences

### Android (Phone)

- Portrait only, bottom sheet (320 height)
- No splash screen (loads directly into main activity)
- Foreground service notification when connected
- QR: inline camera scanning with tap-to-focus
- Permissions: Camera, Bluetooth, Location, Notifications

### macOS (Computer)

- Fixed window: 360 x 640 (9:16), hides on close (stays in Dock + status bar)
- No splash screen (loads directly into main view)
- QR: inline via AnimatedSwitcher, replacing the power button
- Permissions: Bluetooth only
- App icon in Dock (`LSUIElement` false)
- Status bar icon: Buzzel logo as template image

| Status Bar State | Appearance                 |
| ---------------- | -------------------------- |
| Disconnected     | Dimmed                     |
| Connecting       | Blinking (dimmed ↔ active) |
| Connected        | Active                     |

Right-click menu: connection status, Open App, Quit.

---

## Assets

Shared assets in `assets/` use **kebab-case**. Generated files: **snake_case** (Android), **PascalCase** (macOS).

| File                    | Purpose                   |
| ----------------------- | ------------------------- |
| `assets/logo.svg`       | App logo (512x512, fill)  |
| `assets/mesh.svg`       | Mesh gradient (1080x1920) |
| `assets/sofia-sans.ttf` | Sofia Sans variable font  |

### Logo

B-shaped mark composed of curved paths (viewbox 512). No stroke. Color applied by context: `text` for header, `#1A1A1A` for app icon, template for status bar.

Path data loaded at runtime from `brand.json` (`Brand.json` on macOS) via the `Brand` singleton.

### Brand Config

Generated by each platform's `prepare.sh`. Logo data extracted from `logo.svg`. Not manually maintained.

| Platform | Generated file                   |
| -------- | -------------------------------- |
| Android  | `app/src/main/assets/brand.json` |
| macOS    | `Resources/Brand.json`           |

| Field          | Source     | Description           |
| -------------- | ---------- | --------------------- |
| `logo.path`    | `logo.svg` | SVG path d attribute  |
| `logo.viewbox` | `logo.svg` | Viewbox size (square) |

### Asset Generation

Run via Makefile: `cd <platform> && make assets`. No arguments needed.

Android requires: `rsvg-convert`, `magick`.
macOS requires: `rsvg-convert`, `magick`, `iconutil`.

App icon: `#1A1A1A` logo on grayscale mesh gradient background. Padding: 450 (Android), 225 (macOS).

Adaptive icon XML descriptors generated for Android API 26+:

- `res/mipmap-anydpi-v26/ic_launcher.xml`
- `res/mipmap-anydpi-v26/ic_launcher_round.xml`

**Android:**

| Generated file                                | Source            |
| --------------------------------------------- | ----------------- |
| `app/src/main/assets/brand.json`              | `logo.svg`        |
| `app/src/main/assets/sofia-sans.ttf`          | `sofia-sans.ttf`  |
| `res/mipmap-*/ic_launcher.png`                | Both (composited) |
| `res/mipmap-*/ic_launcher_background.png`     | `mesh.svg`        |
| `res/mipmap-*/ic_launcher_foreground.png`     | `logo.svg`        |
| `res/mipmap-anydpi-v26/ic_launcher.xml`       | Generated         |
| `res/mipmap-anydpi-v26/ic_launcher_round.xml` | Generated         |

**macOS:**

| Generated file            | Source            |
| ------------------------- | ----------------- |
| `Resources/Brand.json`    | `logo.svg`        |
| `Resources/SofiaSans.ttf` | `sofia-sans.ttf`  |
| `Resources/AppIcon.icns`  | Both (composited) |

---

## Icons

24x24 viewbox. SVG path data embedded in source code. Parser must support arc commands (A/a).

### Header Icons

| Icon       | Style | Description           |
| ---------- | ----- | --------------------- |
| `settings` | Fill  | Gear (hexagonal)      |
| `zap`      | Fill  | Lightning bolt (back) |

### Power Button Icons

| Icon           | Style | Description                    |
| -------------- | ----- | ------------------------------ |
| `fingerAccess` | Fill  | Fingerprint / access           |
| `zap`          | Fill  | Lightning bolt                 |
| `loading`      | Fill  | Circular spinner (rotates)     |
| `unlink`       | Fill  | Broken link / disconnect       |
| `play`         | Fill  | Play triangle (drawn as paths) |
