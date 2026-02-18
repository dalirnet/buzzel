#!/bin/bash
#
# Generate macOS app icon, splash assets, and brand.json from source SVGs.
#
# Usage:  sh assets.sh
# Requires: rsvg-convert, magick, iconutil
#
# Input  (../assets/):  logo.svg, mesh.svg, sofia-sans.ttf
# Output:
#   Resources/AppIcon.icns       — macOS app icon
#   Resources/Brand.json         — runtime brand config
#   Resources/Mesh.png            — splash background
#   Resources/SofiaSans.ttf      — custom font

set -euo pipefail
cd "$(dirname "$0")/.."

# --- Constants ---

PADDING=225

# --- Paths ---

ASSETS="../assets"
LOGO="$ASSETS/logo.svg"
MESH="$ASSETS/mesh.svg"
TMP=$(mktemp -d /tmp/macos_prepare_XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- Checks ---

for cmd in rsvg-convert magick iconutil; do
    command -v "$cmd" &>/dev/null || { echo "Error: $cmd required."; exit 1; }
done
for f in "$LOGO" "$MESH"; do
    [ -f "$f" ] || { echo "Error: $f not found."; exit 1; }
done

# --- 1. Extract brand data ---

echo "Extracting brand data..."

PATH_D=$(sed -n 's/.*d="\([^"]*\)".*/\1/p' "$LOGO" | tr '\n' ' ' | sed 's/  */ /g; s/ *$//')
[ -z "$PATH_D" ] && { echo "Error: no path in logo.svg"; exit 1; }

VB=$(sed -n 's/.*viewBox="[0-9]* [0-9]* \([0-9]*\) [0-9]*".*/\1/p' "$LOGO")
VB=${VB:-512}

# --- 2. Generate Brand.json + copy font ---

echo "Generating Brand.json..."
cat > Resources/Brand.json <<EOF
{
    "logo": {
        "path": "$PATH_D",
        "viewbox": $VB
    }
}
EOF
cp "$ASSETS/sofia-sans.ttf" Resources/SofiaSans.ttf

# --- 3. Render mesh gradient ---

echo "Rendering mesh gradient..."
rsvg-convert -w 1024 -h 1024 "$MESH" -o "$TMP/mesh.png"
rsvg-convert -w 1080 -h 1920 "$MESH" -o Resources/Mesh.png

# --- 4. Recolored logo SVG ---

PVB=$((VB + PADDING * 2))
sed \
    -e "s/viewBox=\"[^\"]*\"/viewBox=\"-${PADDING} -${PADDING} ${PVB} ${PVB}\"/" \
    -e "s/width=\"[^\"]*\"/width=\"${PVB}\"/" \
    -e "s/height=\"[^\"]*\"/height=\"${PVB}\"/" \
    -e "s/<path /<path fill=\"#FFFFFF\" /g" \
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
