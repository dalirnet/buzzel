#!/bin/bash

echo "Checking dependencies..."

command -v swiftc >/dev/null 2>&1 || { echo "Error: Xcode Command Line Tools not found. Run: xcode-select --install"; exit 1; }
command -v codesign >/dev/null 2>&1 || { echo "Error: codesign not found. Install Xcode Command Line Tools."; exit 1; }

OS_VER=$(sw_vers -productVersion | cut -d. -f1)
[ "$OS_VER" -ge 13 ] 2>/dev/null || echo "Warning: macOS 13+ recommended."

swiftc --version | head -1

echo "Ready."
