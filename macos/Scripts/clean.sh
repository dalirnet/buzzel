#!/bin/bash
#
# Deep cleanup for macOS build artifacts, caches, and generated resources.
#
# Usage:  sh clean.sh
#
# Removes build output, SPM cache, intermediate files, icon cache,
# and generated resources. Run assets.sh to regenerate assets.

set -euo pipefail
cd "$(dirname "$0")/.."

removed=0
remove() {
    for p in "$@"; do
        if [ -e "$p" ]; then
            rm -rf "$p"
            echo "  removed $p"
            removed=$((removed + 1))
        fi
    done
}

# --- 1. Build output ---

echo "Cleaning build output..."
remove build

# --- 2. Swift Package Manager cache ---

echo "Cleaning SPM cache..."
remove .build .swiftpm Package.resolved

# --- 3. Compiler intermediates ---

echo "Cleaning compiler intermediates..."
for f in $(find . -maxdepth 2 \( -name '*.o' -o -name '*.swiftmodule' -o -name '*.swiftdoc' -o -name '*.dSYM' \) 2>/dev/null); do
    remove "$f"
done

# --- 4. Xcode / DerivedData leftovers ---

echo "Cleaning Xcode leftovers..."
remove DerivedData xcuserdata

# --- 5. System junk ---

echo "Cleaning system junk..."
for f in $(find . -name '.DS_Store' 2>/dev/null); do
    remove "$f"
done

# --- 6. macOS icon cache (system-wide) ---

echo "Flushing icon cache..."
if [ -d "/Library/Caches/com.apple.iconservices.store" ]; then
    sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null && echo "  flushed system icon cache" || echo "  skipped (requires sudo)"
fi
find "${HOME}/Library/Caches" -name "com.apple.iconservices*" -exec rm -rf {} + 2>/dev/null && echo "  flushed user icon cache" || true

# --- 7. Generated resources ---

echo "Cleaning generated resources..."
remove Resources/AppIcon.icns Resources/Brand.json Resources/Mesh.png Resources/SofiaSans.ttf

echo ""
if [ "$removed" -gt 0 ]; then
    echo "Cleanup done ($removed items removed)."
else
    echo "Already clean."
fi
