#!/bin/bash
#
# Generate macOS app icon, splash assets, and brand.json from source SVGs.
#
# Usage:  sh prepare.sh [--color COLOR] [--padding PADDING]
# Requires: rsvg-convert, magick, iconutil
#
# Input  (../assets/):  logo.svg, mesh-gradient.svg, brand.json, sofia-sans.ttf
# Output:
#   Resources/AppIcon.icns       — macOS app icon
#   Resources/Brand.json         — runtime brand config
#   Resources/MeshGradient.png   — splash background
#   Resources/SofiaSans.ttf      — custom font

set -euo pipefail
cd "$(dirname "$0")"

# --- Defaults ---

COLOR="#FFFFFF"
PADDING=22

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
TMP=$(mktemp -d /tmp/macos_prepare_XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- Checks ---

for cmd in rsvg-convert magick iconutil; do
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

# --- 2. Generate Brand.json + copy font ---

echo "Generating Brand.json..."
cat > Resources/Brand.json <<EOF
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
cp "$ASSETS/sofia-sans.ttf" Resources/SofiaSans.ttf

# --- 3. Render mesh gradient ---

echo "Rendering mesh gradient..."
rsvg-convert -w 1024 -h 1024 "$MESH" -o "$TMP/mesh.png"
rsvg-convert -w 1080 -h 1920 "$MESH" -o Resources/MeshGradient.png

# --- 4. Recolored logo SVG ---

PVB=$((VB + PADDING * 2))
sed \
    -e "s/viewBox=\"[^\"]*\"/viewBox=\"-${PADDING} -${PADDING} ${PVB} ${PVB}\"/" \
    -e "s/stroke=\"[^\"]*\"/stroke=\"${COLOR}\"/" \
    "$LOGO" > "$TMP/logo.svg"

# --- 5. Generate app icon ---

echo "Generating app icon..."
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

for pair in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x 128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x; do
    s="${pair%%:*}"; name="${pair##*:}"
    magick "$TMP/mesh.png" -resize "${s}x${s}!" "$TMP/bg.png"
    rsvg-convert -w "$s" -h "$s" "$TMP/logo.svg" -o "$TMP/fg.png"
    magick "$TMP/bg.png" "$TMP/fg.png" -composite "$ICONSET/${name}.png"
done

iconutil --convert icns --output Resources/AppIcon.icns "$ICONSET"

echo "Done."
