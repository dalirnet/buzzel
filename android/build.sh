#!/bin/bash

CONFIG=${1:-debug}

if [ "$CONFIG" != "debug" ] && [ "$CONFIG" != "release" ]; then
    echo "Usage: $0 [debug|release]"
    exit 1
fi

echo "Building $CONFIG..."

if [ "$CONFIG" = "release" ]; then
    ./gradlew assembleRelease --no-configuration-cache -q || { echo "Build failed."; exit 1; }
    APK=$(find app/build/outputs/apk/release -name '*.apk' 2>/dev/null | head -1)
else
    ./gradlew assembleDebug --no-configuration-cache -q || { echo "Build failed."; exit 1; }
    APK=$(find app/build/outputs/apk/debug -name '*.apk' 2>/dev/null | head -1)
fi

if [ -z "$APK" ]; then
    echo "Build failed."
    exit 1
fi

echo "Done: $APK"
