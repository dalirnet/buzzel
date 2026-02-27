#!/bin/bash
#
# Generate Android app icons, brand.json, and notification icon from source SVGs.
#
# Usage:  sh assets.sh
# Requires: rsvg-convert, magick (ImageMagick 7)
#
# Input  (../assets/):  logo.svg, mesh.svg, sofia-sans.ttf
# Output:
#   app/src/main/assets/brand.json              — runtime brand config
#   app/src/main/assets/sofia-sans.ttf          — custom font
#   app/src/main/res/mipmap-*/ic_launcher*.png  — app icons (legacy + adaptive)
#   app/src/main/res/drawable-*/ic_notification.png — notification icon

set -euo pipefail
cd "$(dirname "$0")/.."

# --- Constants ---

PADDING=450
NOTIF_PADDING=120

# --- Paths ---

ASSETS="../assets"
LOGO="$ASSETS/logo.svg"
MESH="$ASSETS/mesh.svg"
RES="app/src/main/res"
OUT="app/src/main/assets"
TMP=$(mktemp -d /tmp/android_prepare_XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- Checks ---

for cmd in rsvg-convert magick; do
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

# --- 2. Generate brand.json + copy font ---

echo "Generating brand.json..."
mkdir -p "$OUT"
cp "$ASSETS/sofia-sans.ttf" "$OUT/sofia-sans.ttf"
cat > "$OUT/brand.json" <<EOF
{
  "logo": {
    "path": "$PATH_D",
    "viewbox": $VB
  }
}
EOF

# --- 3. Render mesh gradient for icon ---

echo "Rendering mesh gradient..."
rsvg-convert -w 1080 -h 1920 "$MESH" -o "$TMP/mesh.png"

# --- 4. Logo mask SVG (white for alpha mask) ---

PVB=$((VB + PADDING * 2))
sed \
    -e "s/viewBox=\"[^\"]*\"/viewBox=\"-${PADDING} -${PADDING} ${PVB} ${PVB}\"/" \
    -e "s/width=\"[^\"]*\"/width=\"${PVB}\"/" \
    -e "s/height=\"[^\"]*\"/height=\"${PVB}\"/" \
    -e "s/<path /<path fill=\"#FFFFFF\" /g" \
    "$LOGO" > "$TMP/logo.svg"

# --- 5. Adaptive icons ---

echo "Generating icons..."
mkdir -p "$RES/mipmap-mdpi" "$RES/mipmap-hdpi" "$RES/mipmap-xhdpi" "$RES/mipmap-xxhdpi" "$RES/mipmap-xxxhdpi"
mkdir -p "$RES/mipmap-anydpi-v26"

# Generate adaptive icon XML
cat > "$RES/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
XML

cat > "$RES/mipmap-anydpi-v26/ic_launcher_round.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
XML

for pair in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
    d="${pair%%:*}"; s="${pair##*:}"
    magick "$TMP/mesh.png" -resize "${s}x${s}!" \
        -define png:color-type=2 "$RES/mipmap-$d/ic_launcher_background.png"
    rsvg-convert -w "$s" -h "$s" "$TMP/logo.svg" -o "$RES/mipmap-$d/ic_launcher_foreground.png"
done

# --- 6. Legacy icons ---

for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    d="${pair%%:*}"; s="${pair##*:}"
    rsvg-convert -w "$s" -h "$s" "$TMP/logo.svg" -o "$TMP/mask.png"
    magick \
        \( "$TMP/mesh.png" -resize "${s}x${s}!" \) \
        \( -size "${s}x${s}" "xc:#1a1a1a" "$TMP/mask.png" -compose CopyOpacity -composite \) \
        -compose Over -composite -define png:color-type=2 "$RES/mipmap-$d/ic_launcher.png"
done

# --- 7. Notification icon ---

NPVB=$((VB + NOTIF_PADDING * 2))
sed \
    -e "s/viewBox=\"[^\"]*\"/viewBox=\"-${NOTIF_PADDING} -${NOTIF_PADDING} ${NPVB} ${NPVB}\"/" \
    -e "s/width=\"[^\"]*\"/width=\"${NPVB}\"/" \
    -e "s/height=\"[^\"]*\"/height=\"${NPVB}\"/" \
    -e "s/<path /<path fill=\"#FFFFFF\" /g" \
    "$LOGO" > "$TMP/notif_logo.svg"

mkdir -p "$RES/drawable-mdpi" "$RES/drawable-hdpi" "$RES/drawable-xhdpi" "$RES/drawable-xxhdpi" "$RES/drawable-xxxhdpi"
for pair in mdpi:24 hdpi:36 xhdpi:48 xxhdpi:72 xxxhdpi:96; do
    d="${pair%%:*}"; s="${pair##*:}"
    rsvg-convert -w "$s" -h "$s" "$TMP/notif_logo.svg" -o "$RES/drawable-$d/ic_notification.png"
done

echo "Done."
