#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "💿 Packaging Dropit into a macOS Disk Image (DMG)..."

# Ensure app is built with latest changes
./build.sh

DMG_NAME="Dropit.dmg"
VOLUME_NAME="Dropit"
STAGING_DIR=".dmg_staging"

# Clean previous build artifacts
rm -rf "$STAGING_DIR"
rm -f "$DMG_NAME"

# Create staging directory
mkdir -p "$STAGING_DIR"

# Copy App into staging
echo "Copying Dropit.app into DMG staging area..."
cp -R "Dropit.app" "$STAGING_DIR/Dropit.app"

# Create symlink to Applications folder so users can drag straight onto it
echo "Creating /Applications shortcut link..."
ln -s /Applications "$STAGING_DIR/Applications"

# Build compressed UDZO disk image
echo "Building compressed DMG..."
if diskutil image create from --help >/dev/null 2>&1; then
    diskutil image create from \
        --format UDZO \
        --volumeName "$VOLUME_NAME" \
        "$STAGING_DIR" \
        "$DMG_NAME"
else
    hdiutil create \
        -volname "$VOLUME_NAME" \
        -srcfolder "$STAGING_DIR" \
        -ov \
        -format UDZO \
        "$DMG_NAME"
fi

# Lay the icons out side by side with an arrow between them, so opening the
# DMG shows an obvious drag target instead of a pile of overlapping icons.
echo "Arranging DMG window layout..."
MOUNT_POINT=""
cleanup() {
    [ -n "$MOUNT_POINT" ] && hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

MOUNT_POINT="$(hdiutil attach "$DMG_NAME" -nobrowse -readonly 2>/dev/null | tail -1 | sed 's/.*\(\/Volumes\/.*\)/\1/')"

if [ -d "$MOUNT_POINT" ]; then
    osascript <<APPLESCRIPT
    tell application "Finder"
        tell disk "$VOLUME_NAME"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {300, 220, 800, 460}
            set theViewOptions to the icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 96
            set position of item "Dropit.app" of container window to {150, 130}
            set position of item "Applications" of container window to {450, 130}
            update without registering applications
            delay 1
            close
        end tell
    end tell
APPLESCRIPT
fi

echo ""
echo "🎉 Successfully created $DMG_NAME!"
ls -lh "$DMG_NAME"
echo "📍 Location: $DIR/$DMG_NAME"