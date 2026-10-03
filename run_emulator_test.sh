#!/bin/bash
# Installs the Android emulator and system image from pre-downloaded zips, then runs
# the Dropit Phone app on a headless emulator and reports any crash.
#
# Usage:  ./run_emulator_test.sh
#
# Expects /tmp/emu-dl/emulator.zip and /tmp/emu-dl/sysimg.zip to be present.
set -u

SDK="$HOME/Library/Android/sdk"
JAVA_HOME="$HOME/Library/Android/jdk17/Contents/Home"
DL="${DL:-/tmp/emu-dl}"
AVD_NAME=dropit_test
PKG=com.dropit.phone
ACTIVITY=".MainActivity"

export JAVA_HOME
export ANDROID_HOME="$SDK"
export PATH="$JAVA_HOME/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$SDK/emulator:$PATH"

say() { echo "▸ $*"; }
fail() { echo "✗ $*"; exit 1; }

# ---------------------------------------------------------------- install packages

if [ ! -x "$SDK/emulator/emulator" ]; then
    [ -f "$DL/emulator.zip" ] || fail "missing $DL/emulator.zip"
    say "installing emulator package"
    rm -rf "$DL/emu-extract" && mkdir -p "$DL/emu-extract"
    unzip -q -o "$DL/emulator.zip" -d "$DL/emu-extract" || fail "emulator.zip did not unzip"
    rm -rf "$SDK/emulator"
    mv "$DL/emu-extract/emulator" "$SDK/emulator" || fail "unexpected emulator.zip layout"
    [ -f "$SDK/emulator/source.properties" ] || fail "emulator package missing source.properties"
fi

IMG_DIR="$SDK/system-images/android-35/default/arm64-v8a"
if [ ! -f "$IMG_DIR/source.properties" ]; then
    [ -f "$DL/sysimg.zip" ] || fail "missing $DL/sysimg.zip"
    say "installing system image"
    mkdir -p "$SDK/system-images/android-35/default"
    rm -rf "$DL/img-extract" && mkdir -p "$DL/img-extract"
    unzip -q -o "$DL/sysimg.zip" -d "$DL/img-extract" || fail "sysimg.zip did not unzip"
    rm -rf "$IMG_DIR"
    mv "$DL/img-extract/arm64-v8a" "$IMG_DIR" || fail "unexpected sysimg.zip layout"
    [ -f "$IMG_DIR/source.properties" ] || fail "system image missing source.properties"
fi

say "emulator: $(ls -d "$SDK/emulator" >/dev/null 2>&1 && echo present || echo MISSING)"
say "image:    $IMG_DIR"

# ---------------------------------------------------------------- create AVD

if ! "$SDK/emulator/emulator" -list-avds | grep -qx "$AVD_NAME"; then
    say "creating AVD $AVD_NAME"
    echo no | "$SDK/cmdline-tools/latest/bin/avdmanager" create avd \
        -n "$AVD_NAME" \
        -k "system-images;android-35;default;arm64-v8a" \
        -d pixel_6 \
        --force >/dev/null 2>&1 || say "avdmanager create reported a problem (continuing)"
fi

"$SDK/emulator/emulator" -list-avds | grep -qx "$AVD_NAME" || fail "AVD $AVD_NAME was not created"

# ---------------------------------------------------------------- boot headless

ADB="$SDK/platform-tools/adb"
say "booting emulator (headless)"
nohup "$SDK/emulator/emulator" -avd "$AVD_NAME" \
    -no-window -no-audio -no-boot-anim -no-snapshot \
    -gpu swiftshader_indirect \
    -partition-size 2048 \
    -memory 2048 \
    > "$DL/emulator-run.log" 2>&1 &
EMU_PID=$!
echo "emulator pid $EMU_PID"

say "waiting for boot (up to 6 minutes)"
BOOTED=no
for _ in $(seq 1 72); do
    if "$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' | grep -q '^1$'; then
        BOOTED=yes; break
    fi
    sleep 5
done
if [ "$BOOTED" != yes ]; then
    echo "✗ emulator did not finish booting; last 40 log lines:"
    tail -40 "$DL/emulator-run.log"
    exit 1
fi
say "booted"

"$ADB" shell settings put global window_animation_scale 0 >/dev/null 2>&1
"$ADB" shell settings put global transition_animation_scale 0 >/dev/null 2>&1
"$ADB" shell input keyevent 82 >/dev/null 2>&1
sleep 3

# ---------------------------------------------------------------- install + run

APK="${APK:-$HOME/Documents/Dev/anigravity/DropIT/DropitPhone.apk}"
[ -f "$APK" ] || fail "APK not found at $APK (set APK=...)"

say "installing $(basename "$APK")"
"$ADB" install -r -g "$APK" 2>&1 | tail -3

say "clearing logcat and launching"
"$ADB" logcat -c 2>/dev/null
"$ADB" shell am force-stop "$PKG" 2>/dev/null
"$ADB" shell am start -W -n "$PKG/$ACTIVITY" 2>&1 | sed 's/^/    /'

sleep 8

echo
echo "===================== CRASH CHECK ====================="
CRASH=$(grep -h "FATAL EXCEPTION" -A 25 /tmp/emu-dl/logcat.txt 2>/dev/null)
"$ADB" logcat -d -v brief 2>/dev/null | grep -iE "FATAL EXCEPTION|AndroidRuntime|dropit.phone|UNINITIALIZED_PROPERTY|DropitPhone" | head -40 > "$DL/logcat.txt"

PID=$("$ADB" shell pidof "$PKG" 2>/dev/null | tr -d '\r')
echo "app pid: ${PID:-<none>}"

if grep -q "FATAL EXCEPTION" "$DL/logcat.txt" 2>/dev/null; then
    echo "✗ CRASH DETECTED"
    echo
    "$ADB" logcat -d -v brief 2>/dev/null | grep -B3 -A 30 "FATAL EXCEPTION" | head -60
    exit 1
fi

if [ -z "$PID" ]; then
    echo "✗ the app is not running (no pid) - it died or never started"
    echo
    echo "--- recent app log ---"
    "$ADB" logcat -d -v brief 2>/dev/null | grep -iE "dropit|AndroidRuntime|ActivityManager.*$PKG" | tail -40
    exit 1
fi

echo "✓ app is alive with pid $PID"
echo
echo "--- app log lines ---"
"$ADB" logcat -d -v brief 2>/dev/null | grep -i "dropit" | tail -20
echo
echo "--- what the app is showing ---"
"$ADB" shell dumpsys activity activities 2>/dev/null | grep -i "mResumedActivity\|topResumedActivity" | head -3
