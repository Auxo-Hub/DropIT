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

# Create symlink to Applications folder
echo "Creating /Applications shortcut link..."
ln -s /Applications "$STAGING_DIR/Applications"

# Build compressed UDZO disk image using diskutil image create
echo "Building compressed DMG..."
if diskutil image help create >/dev/null 2>&1; then
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

# Clean up staging area
rm -rf "$STAGING_DIR"

echo ""
echo "🎉 Successfully created $DMG_NAME!"
ls -lh "$DMG_NAME"
echo "📍 Location: $DIR/$DMG_NAME"
