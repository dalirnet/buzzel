#!/bin/bash

set -e

if ! command -v ktlint &>/dev/null; then
    echo "Error: ktlint not found. Install with: brew install ktlint"
    exit 1
fi

ktlint -F "app/src/**/*.kt"

echo "Done"
