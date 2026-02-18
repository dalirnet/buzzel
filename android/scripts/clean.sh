#!/bin/bash
#
# Deep cleanup for Android build artifacts, caches, and generated resources.
#
# Usage:  sh clean.sh
#
# Removes build output, Gradle cache, Kotlin cache, and generated
# resources. Run assets.sh to regenerate assets.

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
remove build app/build

# --- 2. Gradle cache ---

echo "Cleaning Gradle cache..."
remove .gradle

# --- 3. Kotlin cache ---

echo "Cleaning Kotlin cache..."
remove .kotlin

# --- 4. IDE leftovers ---

echo "Cleaning IDE leftovers..."
remove .idea *.iml app/*.iml

# --- 5. System junk ---

echo "Cleaning system junk..."
for f in $(find . -name '.DS_Store' 2>/dev/null); do
    remove "$f"
done

# --- 6. Generated resources ---

echo "Cleaning generated resources..."
remove app/src/main/assets/brand.json app/src/main/assets/sofia-sans.ttf
remove app/src/main/res/drawable/mesh.png
for d in app/src/main/res/mipmap-*/; do
    [ -d "$d" ] && remove "$d"
done

echo ""
if [ "$removed" -gt 0 ]; then
    echo "Cleanup done ($removed items removed)."
else
    echo "Already clean."
fi
