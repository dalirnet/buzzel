#!/bin/bash

CONFIG=${1:-debug}

if [ "$CONFIG" != "debug" ] && [ "$CONFIG" != "release" ]; then
    echo "Usage: $0 [debug|release]"
    exit 1
fi

echo "Building $CONFIG..."

mkdir -p build/Buzzel.app/Contents/{MacOS,Resources}

build_arch() {
    swiftc ${2} -o ${1} \
        Sources/App/*.swift \
        Sources/Models/*.swift \
        Sources/Services/*.swift \
        Sources/Views/*.swift \
        -framework SwiftUI -framework AppKit -framework CoreBluetooth \
        -framework Network -framework UserNotifications \
        -framework IOBluetooth \
        -target ${3}-apple-macos13.0
}

if [ "$CONFIG" = "release" ]; then
    build_arch build/Buzzel_arm64 "-O" "arm64"
    build_arch build/Buzzel_x86_64 "-O" "x86_64"
    lipo -create -output build/Buzzel.app/Contents/MacOS/Buzzel build/Buzzel_{arm64,x86_64}
    rm build/Buzzel_{arm64,x86_64}
else
    build_arch build/Buzzel.app/Contents/MacOS/Buzzel "-g" $(uname -m)
fi

cp Resources/Info.plist build/Buzzel.app/Contents/
cp Resources/AppIcon.icns build/Buzzel.app/Contents/Resources/ 2>/dev/null || true

codesign --force --sign - --entitlements Resources/Buzzel.entitlements build/Buzzel.app

echo "Done: build/Buzzel.app"
