#!/bin/bash
#
# Generate Android app icons, splash assets, and brand.json from source SVGs.
#
# Usage:  sh prepare.sh [--color COLOR] [--padding PADDING]
# Requires: rsvg-convert, magick (ImageMagick 7)
#
# Input  (../assets/):  logo.svg, mesh_gradient.svg
# Output:
#   app/src/main/assets/brand.json              — runtime brand config
#   app/src/main/res/drawable/mesh_gradient.png — splash background
#   app/src/main/res/mipmap-*/ic_launcher*.png  — app icons (legacy + adaptive)

set -euo pipefail
cd "$(dirname "$0")"

# --- Defaults (override with flags) ---

LOGO_COLOR="#FFFFFF"
LOGO_PADDING=160
SPLASH_SCALE=0.35
SPLASH_COLOR_LIGHT="#DCF5FA"
SPLASH_COLOR_DARK="#011E41"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --color)   LOGO_COLOR="$2"; shift 2 ;;
        --padding) LOGO_PADDING="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Paths ---

ASSETS="../assets"
LOGO_SVG="$ASSETS/logo.svg"
MESH_SVG="$ASSETS/mesh_gradient.svg"
RES="app/src/main/res"
APP_ASSETS="app/src/main/assets"
TMP=$(mktemp -d /tmp/icon_XXXXXX)
MESH_PNG="$TMP/mesh_gradient.png"
trap 'rm -rf "$TMP"' EXIT

# --- Checks ---

for cmd in rsvg-convert magick; do
    command -v "$cmd" &>/dev/null || { echo "Error: $cmd required."; exit 1; }
done
for f in "$LOGO_SVG" "$MESH_SVG"; do
    [ -f "$f" ] || { echo "Error: $f not found."; exit 1; }
done

# --- 1. Extract brand data from SVGs ---

echo "Extracting brand data..."

LOGO_PATH=$(sed -n 's/.*d="\([^"]*\)".*/\1/p' "$LOGO_SVG")
[ -z "$LOGO_PATH" ] && { echo "Error: no path in logo.svg"; exit 1; }

LOGO_VB=$(sed -n 's/.*viewBox="[0-9]* [0-9]* \([0-9]*\) [0-9]*".*/\1/p' "$LOGO_SVG")
LOGO_VB=${LOGO_VB:-512}

LOGO_SW=$(sed -n 's/.*stroke-width="\([^"]*\)".*/\1/p' "$LOGO_SVG")
LOGO_SW=${LOGO_SW:-46}

COLORS=$(grep 'stop-color=' "$MESH_SVG" | sed -n 's/.*stop-color="\([^"]*\)".*/\1/p' | awk '!seen[$0]++')
COLOR_JSON=""
while IFS= read -r c; do
    [ -z "$c" ] && continue
    [ -n "$COLOR_JSON" ] && COLOR_JSON="$COLOR_JSON, "
    COLOR_JSON="$COLOR_JSON\"$c\""
done <<< "$COLORS"
[ -z "$COLOR_JSON" ] && { echo "Error: no colors in mesh_gradient.svg"; exit 1; }

# --- 2. Generate brand.json ---

echo "Generating brand.json..."
mkdir -p "$APP_ASSETS"
cat > "$APP_ASSETS/brand.json" <<EOF
{
  "logo": {
    "path": "$LOGO_PATH",
    "viewbox": $LOGO_VB,
    "stroke_width": $LOGO_SW
  },
  "mesh": {
    "colors": [$COLOR_JSON]
  },
  "splash": {
    "logo_scale": $SPLASH_SCALE,
    "logo_color_light": "$SPLASH_COLOR_LIGHT",
    "logo_color_dark": "$SPLASH_COLOR_DARK"
  }
}
EOF

# --- 3. Render mesh PNG ---

echo "Rendering mesh gradient..."
rsvg-convert -w 1080 -h 1920 "$MESH_SVG" -o "$MESH_PNG"
cp "$MESH_PNG" "$RES/drawable/mesh_gradient.png"

# --- 4. Recolored logo SVG (white, padded viewbox) ---

VB=$((LOGO_VB + LOGO_PADDING * 2))
sed \
    -e "s/viewBox=\"[^\"]*\"/viewBox=\"-${LOGO_PADDING} -${LOGO_PADDING} ${VB} ${VB}\"/" \
    -e "s/stroke=\"[^\"]*\"/stroke=\"${LOGO_COLOR}\"/" \
    "$LOGO_SVG" > "$TMP/logo.svg"

# --- 5. Adaptive icon backgrounds ---

echo "Generating icons..."
for pair in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
    d="${pair%%:*}"; s="${pair##*:}"
    magick "$MESH_PNG" -resize "${s}x${s}!" "$RES/mipmap-$d/ic_launcher_background.png"
done

# --- 6. Adaptive icon foregrounds ---

for pair in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
    d="${pair%%:*}"; s="${pair##*:}"
    rsvg-convert -w "$s" -h "$s" "$TMP/logo.svg" -o "$RES/mipmap-$d/ic_launcher_foreground.png"
done

# --- 7. Legacy icons (composited) ---

for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    d="${pair%%:*}"; s="${pair##*:}"
    magick "$MESH_PNG" -resize "${s}x${s}!" "$TMP/bg.png"
    rsvg-convert -w "$s" -h "$s" "$TMP/logo.svg" -o "$TMP/fg.png"
    magick "$TMP/bg.png" "$TMP/fg.png" -composite "$RES/mipmap-$d/ic_launcher.png"
done

echo "Done."
