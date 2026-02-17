#!/bin/bash

set -e

if ! command -v swift-format &>/dev/null; then
    echo "Error: swift-format not found. Install with: brew install swift-format"
    exit 1
fi

find Sources Tests -name '*.swift' | while read -r file; do
    swift-format format -i "$file"
done

echo "Done"
