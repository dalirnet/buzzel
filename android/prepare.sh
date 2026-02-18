#!/bin/bash
#
# Generate Android app icons, splash assets, and brand.json from source SVGs.
#
# Usage:  sh prepare.sh [--color COLOR] [--padding PADDING]
# Requires: rsvg-convert, magick (ImageMagick 7)
#
# Input  (../assets/):  logo.svg, mesh-gradient.svg, brand.json, sofia-sans.ttf
# Output:
#   app/src/main/assets/brand.json              — runtime brand config
#   app/src/main/assets/sofia-sans.ttf          — custom font
#   app/src/main/res/drawable/mesh_gradient.png — splash background
#   app/src/main/res/mipmap-*/ic_launcher*.png  — app icons (legacy + adaptive)

set -euo pipefail
cd "$(dirname "$0")"

# --- Defaults ---

COLOR="#FFFFFF"
PADDING=160

while [[ $# -gt 0 ]]; do
    case "$1" in
        --color)   COLOR="$2"; shift 2 ;;
        --padding) PADDING="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Paths ---

ASSETS="../assets"
LOGO="$ASSETS/logo.svg"
MESH="$ASSETS/mesh-gradient.svg"
BRAND="$ASSETS/brand.json"
RES="app/src/main/res"
OUT="app/src/main/assets"
TMP=$(mktemp -d /tmp/android_prepare_XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- Checks ---

for cmd in rsvg-convert magick; do
    command -v "$cmd" &>/dev/null || { echo "Error: $cmd required."; exit 1; }
done
for f in "$LOGO" "$MESH" "$BRAND"; do
    [ -f "$f" ] || { echo "Error: $f not found."; exit 1; }
done

# --- 1. Extract brand data ---

echo "Extracting brand data..."

SPLASH_SCALE=$(sed -n 's/.*"logo_scale"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p' "$BRAND")
SPLASH_LIGHT=$(sed -n 's/.*"logo_color_light"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$BRAND")
SPLASH_DARK=$(sed -n 's/.*"logo_color_dark"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$BRAND")

PATH_D=$(sed -n 's/.*d="\([^"]*\)".*/\1/p' "$LOGO")
[ -z "$PATH_D" ] && { echo "Error: no path in logo.svg"; exit 1; }

VB=$(sed -n 's/.*viewBox="[0-9]* [0-9]* \([0-9]*\) [0-9]*".*/\1/p' "$LOGO")
VB=${VB:-512}

SW=$(sed -n 's/.*stroke-width="\([^"]*\)".*/\1/p' "$LOGO")
SW=${SW:-46}

# --- 2. Generate brand.json + copy font ---

echo "Generating brand.json..."
mkdir -p "$OUT"
cp "$ASSETS/sofia-sans.ttf" "$OUT/sofia-sans.ttf"
cat > "$OUT/brand.json" <<EOF
{
  "logo": {
    "path": "$PATH_D",
    "viewbox": $VB,
    "stroke_width": $SW
  },
  "splash": {
    "logo_scale": $SPLASH_SCALE,
    "logo_color_light": "$SPLASH_LIGHT",
    "logo_color_dark": "$SPLASH_DARK"
  }
}
EOF

# --- 3. Render mesh gradient ---

echo "Rendering mesh gradient..."
rsvg-convert -w 1080 -h 1920 "$MESH" -o "$TMP/mesh.png"
cp "$TMP/mesh.png" "$RES/drawable/mesh_gradient.png"

# --- 4. Recolored logo SVG ---

PVB=$((VB + PADDING * 2))
sed \
    -e "s/viewBox=\"[^\"]*\"/viewBox=\"-${PADDING} -${PADDING} ${PVB} ${PVB}\"/" \
    -e "s/stroke=\"[^\"]*\"/stroke=\"${COLOR}\"/" \
    "$LOGO" > "$TMP/logo.svg"

# --- 5. Adaptive icons ---

echo "Generating icons..."
for pair in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
    d="${pair%%:*}"; s="${pair##*:}"
    magick "$TMP/mesh.png" -resize "${s}x${s}!" "$RES/mipmap-$d/ic_launcher_background.png"
    rsvg-convert -w "$s" -h "$s" "$TMP/logo.svg" -o "$RES/mipmap-$d/ic_launcher_foreground.png"
done

# --- 6. Legacy icons ---

for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    d="${pair%%:*}"; s="${pair##*:}"
    magick "$TMP/mesh.png" -resize "${s}x${s}!" "$TMP/bg.png"
    rsvg-convert -w "$s" -h "$s" "$TMP/logo.svg" -o "$TMP/fg.png"
    magick "$TMP/bg.png" "$TMP/fg.png" -composite "$RES/mipmap-$d/ic_launcher.png"
done

echo "Done."
