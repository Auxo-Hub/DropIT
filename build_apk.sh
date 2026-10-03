#!/bin/bash
# Builds the Dropit Phone Android app.
#
# Requires a JDK 17 and the Android SDK. This script will use the copies installed
# under ~/Library/Android, or fall back to JAVA_HOME / ANDROID_HOME if you set them.
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export JAVA_HOME="${JAVA_HOME:-$HOME/Library/Android/jdk17/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

if [ ! -x "$JAVA_HOME/bin/java" ]; then
    echo "❌ No JDK 17 found. Install one, or set JAVA_HOME."
    echo "   e.g. brew install openjdk@17 && export JAVA_HOME=\$(brew --prefix openjdk@17)/libexec/openjdk.jdk/Contents/Home"
    exit 1
fi
if [ ! -d "$ANDROID_HOME/platforms" ]; then
    echo "❌ No Android SDK found. Install it, or set ANDROID_HOME."
    exit 1
fi

echo "🔨 Building Dropit Phone (Android)..."
cd "$DIR/android"

if [ "${1:-}" = "--release" ]; then
    ./gradlew :app:assembleRelease --no-daemon
    echo "✅ APK: $DIR/android/app/build/outputs/apk/release/app-release.apk"
else
    ./gradlew :app:assembleDebug --no-daemon
    echo "✅ APK: $DIR/android/app/build/outputs/apk/debug/app-debug.apk"
    cp "$DIR/android/app/build/outputs/apk/debug/app-debug.apk" "$DIR/DropitPhone.apk"
    echo "✅ Copied to $DIR/DropitPhone.apk"
fi
