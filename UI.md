# Buzzel UI

Dark and light mode. macOS uses pt, Android uses dp.

### Android Scale Factors

Android applies per-type scale factors for visual parity on phone screens:

| Type       | Scale | Applies to                                |
| ---------- | ----- | ----------------------------------------- |
| Layout     | 1.25x | Spacing, padding, margins, element sizing |
| Typography | 1.15x | Font sizes                                |
| Detail     | 1.0x  | Dots, dividers, small decorative elements |

---

## Design Tokens

### Colors

Resolved from platform system colors. macOS uses native color tokens directly. Android uses system theme attributes where reliable, with hardcoded fallbacks for older devices (pre-Android 10) where `UI_MODE_NIGHT_MASK` may not reflect the actual theme.

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

#### Android Dark Mode Detection

Android 10+ uses the standard `UI_MODE_NIGHT_MASK`. Older devices (e.g. Nokia Android 9) may use vendor-specific settings like `theme_mode` in `Settings.Secure` (1=light, 2=dark). Check vendor setting first on pre-Q, then fall back to `uiMode`.

#### Muted Colors (Power Button Fill)

Soft adaptive fills per theme. Not raw system colors.

| Token         | Light RGB        | Dark RGB         | State         |
| ------------- | ---------------- | ---------------- | ------------- |
| `mutedGray`   | 0.55, 0.55, 0.58 | 0.45, 0.45, 0.48 | Unpaired      |
| `mutedYellow` | 0.95, 0.78, 0.10 | 0.92, 0.75, 0.08 | No permission |
| `mutedOrange` | 0.95, 0.55, 0.10 | 0.92, 0.50, 0.08 | Connecting    |
| `mutedGreen`  | 0.20, 0.75, 0.38 | 0.18, 0.70, 0.35 | Connected     |
| `mutedRed`    | 0.90, 0.28, 0.25 | 0.85, 0.25, 0.22 | Disconnected  |

### Typography

System font on each platform (San Francisco / Roboto).

| Token        | Size | Weight   | Notes   |
| ------------ | ---- | -------- | ------- |
| `title`      | 13   | Semibold | Rounded |
| `body`       | 14   | Regular  |         |
| `statusLine` | 12   | Regular  |         |
| `badge`      | 10   | Regular  |         |
| `logEntry`   | 13   | Regular  |         |
| `logTime`    | 11   | Regular  |         |
| `logDir`     | 9    | Medium   |         |

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
| `icon.sm`    | 14    | App logo in header    |
| `icon.md`    | 20    | Header trailing icon  |
| `button.sm`  | 90    | Power button diameter |
| `button.lg`  | 120   | Content frame, QR     |
| `orbit.area` | 280   | Orbit rings container |

### Layout

| Element             | Value         | Notes                     |
| ------------------- | ------------- | ------------------------- |
| Header height       | 48            |                           |
| Header padding      | 16 x 12       | Horizontal x Vertical     |
| Logo ↔ title gap    | 8             |                           |
| Logo offset         | -1 top        | Optical alignment         |
| Power button        | 90 in 120     | Centered in content frame |
| QR code             | 120           | Circular                  |
| Status line bottom  | 24            | Bottom padding            |
| Status line padding | 16 x 8        | Horizontal x Vertical     |
| Status line bg      | secondary 5%  | Capsule, single line      |
| Badge padding       | 8 x 4         | Horizontal x Vertical     |
| Badge radius        | 4             |                           |
| Badge bg            | secondary 10% |                           |
| Window (macOS)      | 320 x 480     | Fixed size                |
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

Android only. Two-phase splash: an instant static background (window background) followed by an animated logo draw.

### Background

Mesh gradient using four overlapping radial gradients from each corner. Same PNG image for both static and animated phases to ensure seamless transition.

| Corner       | Color     | Name       |
| ------------ | --------- | ---------- |
| Top-left     | `#023E8A` | Deep ocean |
| Top-right    | `#0077B6` | Ocean blue |
| Bottom-right | `#00B4D8` | Cyan       |
| Bottom-left  | `#48CAE4` | Light cyan |

Radial gradient parameters: radius = `max(width, height) * 0.55`, solid to 40%, then fade to transparent. Base fill: `#023E8A`.

System bars (status + navigation) are transparent with fullscreen layout flags so the gradient extends edge-to-edge.

### Logo Animation

Uses the wave-b logo path drawn as a stroke via `PathMeasure.getSegment()`.

| Property    | Value                               |
| ----------- | ----------------------------------- |
| Scale       | 35% of `min(width, height)`         |
| Stroke      | 46 (in 512 viewbox), round cap/join |
| Color light | `rgb(220, 245, 250)` (cyan tint)    |
| Color dark  | `rgb(1, 30, 65)` (ocean tint)       |

### Animation Sequence

| Phase      | Duration | Delay | Easing                                  | Description                          |
| ---------- | -------- | ----- | --------------------------------------- | ------------------------------------ |
| Wait       | —        | 250ms | —                                       | Pause before drawing starts          |
| Draw in    | 1000ms   | —     | `PathInterpolator(0.25, 0.7, 0.2, 1.0)` | Path draws from start to end         |
| Undraw     | 1000ms   | —     | `PathInterpolator(0.8, 0.0, 0.75, 0.3)` | Path erases from start to end        |
| Wait       | —        | 500ms | —                                       | Pause after undraw completes         |
| Transition | 500ms    | —     | accelerate + decelerate                 | Slide down + fade to 50%, main stays |

### Transition to Main

The splash slides down off-screen while fading to 50% opacity. The main activity is already rendered underneath with no enter animation (`stay`). Uses `overridePendingTransition` with custom anim resources.

### Assets

| File                                 | Purpose                              |
| ------------------------------------ | ------------------------------------ |
| `assets/mesh_gradient.png`           | Source mesh gradient image           |
| `assets/mesh_gradient.svg`           | SVG version of mesh gradient         |
| `res/drawable/mesh_gradient.png`     | Android drawable (copy of source)    |
| `res/drawable/splash_background.xml` | Bitmap wrapper for window background |
| `res/anim/slide_down_out.xml`        | Splash exit: slide down + fade       |
| `res/anim/stay.xml`                  | Main enter: stay visible             |

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

- Container: 280 x 280
- Ring stroke: 1pt, `secondary` at 8% opacity

| Ring   | Radius | Duration | Direction         | Dots                       |
| ------ | ------ | -------- | ----------------- | -------------------------- |
| Inner  | 80     | 12s      | Clockwise         | 6pt `accent`, 4pt `green`  |
| Middle | 105    | 18s      | Counter-clockwise | 5pt `orange`, 3pt `accent` |
| Outer  | 130    | 25s      | Clockwise         | 4pt `red`, 3pt `green`     |

Each dot: 60% opacity fill with a glow circle behind it (40% opacity, 1.8x dot diameter).

### Power Button

Circular button at `button.sm` (90), centered in the orbit area.

**Layers (inner to outer):**

1. Shield icon — 45% of button diameter, `onButton` color
2. Solid circle — `mutedColor` fill, pulses when connecting
3. Ripple ring — state color stroke, appears on tap only
4. Halo — state color, continuous pulse animation (see Animation table)

| State         | Color         | Icon             | Tap Action         |
| ------------- | ------------- | ---------------- | ------------------ |
| No permission | `mutedYellow` | `shield-warning` | Request permission |
| Unpaired      | `mutedGray`   | `shield-keyhole` | —                  |
| Connecting    | `mutedOrange` | `shield-up`      | —                  |
| Connected     | `mutedGreen`  | `shield-check`   | Disconnect         |
| Disconnected  | `mutedRed`    | `shield-cross`   | Reconnect          |

### Circular QR Code

120pt circular clip with dot-style modules. Center logo cutout at 28% with `WaveBLogoView`. Uses "H" error correction (30%).

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

Each row contains:

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

- Portrait only
- Foreground service notification when connected
- QR: opens a full-screen camera activity
- Activity log: in-window view with back button
- Permissions required: Camera, Bluetooth, Location, Notifications

### macOS (Computer)

- Fixed window: 320 x 480, hides on close (stays in status bar)
- QR: displayed inline via AnimatedSwitcher, replacing the power button
- Activity log: in-window view with back icon in header
- Permissions required: Bluetooth only
- Status bar icon using wave-b logo as template image

| Status Bar State | Appearance                 |
| ---------------- | -------------------------- |
| Disconnected     | Dimmed                     |
| Connecting       | Blinking (dimmed ↔ active) |
| Connected        | Active                     |

Right-click menu: connection status, Open App, Quit.

---

## Assets

All shared assets live in the `assets/` folder at the project root.

| File                       | Size      | Purpose                  |
| -------------------------- | --------- | ------------------------ |
| `assets/logo.svg`          | 512x512   | App logo, black stroke   |
| `assets/logo-animated.svg` | 512x512   | Animated draw-on variant |
| `assets/mesh_gradient.svg` | 1080x1920 | Mesh gradient background |

### Logo

Waveform lowercase **b**, single open stroke (viewbox 512x512, stroke-width 46, round cap/join). Black by default — color is applied by the rendering context (theme color for in-app header, tinted for splash).

Path data and brand config are loaded at runtime from `brand.json` via the `Brand` singleton on Android. The reversed path (start at bottom, for draw animation) is computed at runtime.

### Mesh Gradient

Four overlapping radial gradients, one per corner. See [Splash Screen](#splash-screen) for full specification.

### Brand Config (`brand.json`)

Runtime config generated by `prepare.sh` from the source SVGs. Contains logo path data, mesh gradient colors, and splash screen parameters. Not manually maintained.

| Field                     | Source               | Description                      |
| ------------------------- | -------------------- | -------------------------------- |
| `logo.path`               | `logo.svg`           | SVG path d attribute             |
| `logo.viewbox`            | `logo.svg`           | Viewbox size (square)            |
| `logo.stroke_width`       | `logo.svg`           | Stroke width                     |
| `mesh.colors`             | `mesh_gradient.svg`  | Gradient colors (TL, TR, BR, BL) |
| `splash.logo_scale`       | `prepare.sh` default | Logo scale on splash (0.35)      |
| `splash.logo_color_light` | `prepare.sh` default | Logo color for light mode        |
| `splash.logo_color_dark`  | `prepare.sh` default | Logo color for dark mode         |

### Asset Generation

Android image assets and `brand.json` are generated from the source SVGs using `prepare.sh`. Run via Makefile:

```
make prepare    # prepare.sh → format.sh
```

Requires `rsvg-convert`, `magick` (ImageMagick 7), `ktlint`, `jq`, `xmllint`.

| Generated file                                         | Source                           |
| ------------------------------------------------------ | -------------------------------- |
| `app/src/main/assets/brand.json`                       | `logo.svg` + `mesh_gradient.svg` |
| `app/src/main/res/drawable/mesh_gradient.png`          | `mesh_gradient.svg`              |
| `app/src/main/res/mipmap-*/ic_launcher.png`            | Both (composited)                |
| `app/src/main/res/mipmap-*/ic_launcher_background.png` | `mesh_gradient.svg`              |
| `app/src/main/res/mipmap-*/ic_launcher_foreground.png` | `logo.svg` (white, padded)       |

---

## Icons

UI icons are 24x24, stroke style, using `currentColor`. SVG path data is embedded directly in source code. The SVG path parser must support arc commands (A/a).

### UI Icons

| Icon             | Description        | Stroke Attributes                                    |
| ---------------- | ------------------ | ---------------------------------------------------- |
| `qr-code`        | QR code            | Mixed stroke and fill                                |
| `undo-left`      | Back arrow         | Round cap, round join                                |
| `shield-check`   | Shield + checkmark | Shield: default. Inner: round cap, round join        |
| `shield-cross`   | Shield + cross     | Shield: default. Inner: round cap                    |
| `shield-keyhole` | Shield + keyhole   | Shield: default. Inner: round join (uses arcs)       |
| `shield-up`      | Shield + chevrons  | Shield: default. Inner: round cap, round join        |
| `shield-warning` | Shield + warning   | Shield: default. Line: round cap. Dot: filled circle |
