#!/bin/bash

set -e
cd "$(dirname "$0")"

for cmd in swift-format jq; do
    command -v "$cmd" &>/dev/null || { echo "Error: $cmd required."; exit 1; }
done

find Sources Tests -name '*.swift' | while read -r file; do
    swift-format format -i "$file"
done

for f in $(find Resources -name '*.json' 2>/dev/null); do
    jq --indent 4 . "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

echo "Done"
