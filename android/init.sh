#!/bin/bash

echo "Checking dependencies..."

# Check Java
command -v java >/dev/null 2>&1 || { echo "Error: Java not found. Install JDK 17+."; exit 1; }

JAVA_VER=$(java -version 2>&1 | head -1 | sed 's/.*"\([0-9]*\).*/\1/')
if [ "$JAVA_VER" -lt 17 ] 2>/dev/null; then
    echo "Error: JDK 17+ required (found $JAVA_VER)."
    exit 1
fi
java -version 2>&1 | head -1

# Check Android SDK
if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
    if [ -f local.properties ]; then
        SDK_DIR=$(grep '^sdk.dir=' local.properties | cut -d= -f2)
        if [ -n "$SDK_DIR" ] && [ -d "$SDK_DIR" ]; then
            export ANDROID_HOME="$SDK_DIR"
        fi
    fi
fi

if [ -z "$ANDROID_HOME" ] && [ -z "$ANDROID_SDK_ROOT" ]; then
    echo "Error: Android SDK not found. Set ANDROID_HOME or add sdk.dir to local.properties."
    exit 1
fi
echo "Android SDK: ${ANDROID_HOME:-$ANDROID_SDK_ROOT}"

# Prepare Gradle
chmod +x gradlew
./gradlew --version | head -3

# Resolve dependencies
./gradlew dependencies -q

echo "Ready."
