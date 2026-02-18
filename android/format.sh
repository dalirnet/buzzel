#!/bin/bash

set -e
cd "$(dirname "$0")"

for cmd in ktlint jq xmllint; do
    command -v "$cmd" &>/dev/null || { echo "Error: $cmd required."; exit 1; }
done

ktlint -F "app/src/**/*.kt"

for f in $(find app/src -name '*.json' 2>/dev/null); do
    jq --indent 4 . "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

export XMLLINT_INDENT="    "
for f in $(find app/src/main/res -name '*.xml' 2>/dev/null); do
    xmllint --format "$f" -o "$f" 2>/dev/null || true
done

echo "Done"
