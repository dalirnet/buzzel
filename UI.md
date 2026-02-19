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
| QR code             | 120           | Circular                  |
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
| Orbit rotation | 12–25s   | linear                    | Continuous, synced to display refresh               |
| Menu bar blink | 1000ms   | toggle                    | macOS only                                          |

---

## Splash Screen

Mesh gradient background with Z-draw logo animation on both platforms.

### Background

macOS-style mesh gradient with 9 overlapping radial gradients and heavy blur (120px) for organic color blending. Rendered to PNG by `assets.sh`.

| Position     | Color     | Radius | Opacity | Notes       |
| ------------ | --------- | ------ | ------- | ----------- |
| Top-left     | `#00A86B` | 1200   | 0.9     | Green       |
| Top-right    | `#0099DD` | 1100   | 0.85    | Blue        |
| Bottom-right | `#FFB800` | 1400   | 0.85    | Yellow/Gold |
| Bottom-left  | `#FF9500` | 1300   | 0.8     | Orange      |
| Center-top   | `#00C9A7` | 950    | 0.7     | Teal        |
| Center-left  | `#0099DD` | 1100   | 0.65    | Blue        |
| Center-right | `#FFCC00` | 900    | 0.7     | Yellow      |
| Upper-left   | `#007B9E` | 850    | 0.6     | Dark teal   |
| Center       | `#00A86B` | 800    | 0.55    | Green       |

Gradient parameters: positioned organically (some extend beyond canvas edges), solid color to 40% offset, then fade to transparent by 100%. Gaussian blur filter applied for smooth blending. Base fill: `#007B6E`.

### Logo Animation

Z-shaped logo (3 filled parallelogram bars) revealed with a clip-rect draw animation. Each bar is revealed sequentially in a Z pattern: left→right, right→left, left→right. Android uses `ValueAnimator` + `Canvas.clipPath()`, macOS uses `CVDisplayLink` + `CGContext.clip()`.

| Property    | Value                       |
| ----------- | --------------------------- |
| Scale       | 35% of `min(width, height)` |
| Style       | Filled paths (no stroke)    |
| Color light | `#FFFFFF`                   |
| Color dark  | `#1A1A1A`                   |

### Animation Sequence

| Bar   | Duration | Begin | Direction  | Easing                             |
| ----- | -------- | ----- | ---------- | ---------------------------------- |
| Bar 1 | 250ms    | 0ms   | Left→right | `cubic-bezier(0.25, 0.1, 0.25, 1)` |
| Bar 2 | 200ms    | 200ms | Right→left | `cubic-bezier(0.42, 0, 0.58, 1)`   |
| Bar 3 | 250ms    | 350ms | Left→right | `cubic-bezier(0.25, 0.1, 0.6, 1)`  |
| Wait  | —        | 500ms | —          | —                                  |

No delay before animation starts. No undraw phase. Transition: splash slides down. On Android via `overridePendingTransition`, on macOS via SwiftUI if/else swap with `.move(edge: .bottom)`.

---

## Views

Three view states, navigated in-window (no separate windows):

| View         | Title          | Badge       | Trailing Icon | Trailing Action |
| ------------ | -------------- | ----------- | ------------- | --------------- |
| Main         | "Buzzel"       | Device name | `qr-code`     | Open QR         |
| QR Code      | "QR Code"      | —           | `undo-left`   | Back to Main    |
| Activity Log | "Activity Log" | Entry count | `undo-left`   | Back to Main    |

### Header

Persistent across views, content updates in place.

- **Left**: App logo (`icon.sm`) + title with typewriter animation + contextual badge
- **Right**: Trailing icon button (`icon.md`)
- QR icon at 30% opacity and disabled when connected or missing permissions
- Badge: `secondary` text on `secondary` 10% background, radius 4

### Orbit Rings

Three concentric rings with orbiting dots around the center content area.

- Container: 294 x 294
- Ring stroke: 1pt, `secondary` at 8% opacity

| Ring   | Radius | Duration | Direction         | Dots                       |
| ------ | ------ | -------- | ----------------- | -------------------------- |
| Inner  | 84     | 12s      | Clockwise         | 6pt `accent`, 4pt `green`  |
| Middle | 110    | 18s      | Counter-clockwise | 5pt `orange`, 3pt `accent` |
| Outer  | 136    | 25s      | Clockwise         | 4pt `red`, 3pt `green`     |

Each dot: 60% opacity fill with a glow circle behind it (40% opacity, 1.8x dot diameter).

### Power Button

Circular button at `button.sm` (94), centered in the orbit area.

**Layers (inner to outer):**

1. Shield icon — 45% of button diameter, `onButton` color
2. Solid circle — `mutedColor` fill, pulses when connecting
3. Ripple ring — state color stroke, appears on tap only
4. Halo — state color, continuous pulse animation

| State         | Color         | Icon             | Tap Action         |
| ------------- | ------------- | ---------------- | ------------------ |
| No permission | `mutedYellow` | `shield-warning` | Request permission |
| Unpaired      | `mutedGray`   | `shield-keyhole` | —                  |
| Connecting    | `mutedOrange` | `shield-up`      | —                  |
| Connected     | `mutedGreen`  | `shield-check`   | Disconnect         |
| Disconnected  | `mutedRed`    | `shield-cross`   | Reconnect          |

### Circular QR Code

120pt circular clip with dot-style modules. Center logo cutout at 28% radius with `WaveBLogoView` at 45% of cutout size (0.28 × 0.45). Uses "H" error correction (30%).

### Status Line

Pinned to the bottom of the main view. Capsule shape, single line, truncated with ellipsis.

| State                       | Text                               |
| --------------------------- | ---------------------------------- |
| No permission               | `Tap to grant {permission} access` |
| Unpaired                    | `No device paired yet`             |
| Connecting                  | `Looking for your device`          |
| Connected (has activity)    | `{last entry} · {time}`            |
| Connected (no activity)     | `Connected and ready`              |
| Disconnected (has activity) | `{last entry} · {time}`            |
| Disconnected (no activity)  | `Tap to reconnect`                 |

Text changes animate with a 3D flip. Tap opens the Activity Log when connected.

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
- Splash screen with mesh gradient + Z-draw logo animation
- Foreground service notification when connected
- QR: full-screen camera activity
- Permissions: Camera, Bluetooth, Location, Notifications

### macOS (Computer)

- Fixed window: 360 x 640 (9:16), hides on close (stays in Dock + status bar)
- Splash screen with mesh gradient + Z-draw logo animation, same timing as Android
- QR: inline via AnimatedSwitcher, replacing the power button
- Permissions: Bluetooth only
- App icon in Dock (`LSUIElement` false)
- Status bar icon: Z logo as template image

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

Z-shaped mark composed of three filled parallelogram paths (viewbox 512). No stroke. Color applied by context: `text` for header, white/dark for splash, template for status bar.

Path data loaded at runtime from `brand.json` (`Brand.json` on macOS) via the `Brand` singleton. Splash config (scale, colors) hardcoded in platform `Brand` singletons.

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

App icon foreground: white logo on mesh gradient background. Padding: 180 (Android), 225 (macOS).

Adaptive icon XML descriptors generated for Android API 26+:

- `res/mipmap-anydpi-v26/ic_launcher.xml`
- `res/mipmap-anydpi-v26/ic_launcher_round.xml`

**Android:**

| Generated file                                | Source            |
| --------------------------------------------- | ----------------- |
| `app/src/main/assets/brand.json`              | `logo.svg`        |
| `app/src/main/assets/sofia-sans.ttf`          | `sofia-sans.ttf`  |
| `res/drawable/mesh.png`                       | `mesh.svg`        |
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
| `Resources/Mesh.png`      | `mesh.svg`        |
| `Resources/AppIcon.icns`  | Both (composited) |

---

## Icons

24x24, stroke style, `currentColor`. SVG path data embedded in source code. Parser must support arc commands (A/a).

| Icon             | Description        | Stroke Attributes                                    |
| ---------------- | ------------------ | ---------------------------------------------------- |
| `qr-code`        | QR code            | Mixed stroke and fill                                |
| `undo-left`      | Back arrow         | Round cap, round join                                |
| `shield-check`   | Shield + checkmark | Shield: default. Inner: round cap, round join        |
| `shield-cross`   | Shield + cross     | Shield: default. Inner: round cap                    |
| `shield-keyhole` | Shield + keyhole   | Shield: default. Inner: round join (uses arcs)       |
| `shield-up`      | Shield + chevrons  | Shield: default. Inner: round cap, round join        |
| `shield-warning` | Shield + warning   | Shield: default. Line: round cap. Dot: filled circle |
