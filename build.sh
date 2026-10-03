#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "🔨 Building Dropit for macOS..."

# Find suitable Developer Directory
if [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
elif [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

echo "Using Developer Dir: ${DEVELOPER_DIR:-$(xcode-select -p)}"

# Prepare build and bundle directories
mkdir -p .build/cache
APP_BUNDLE="Dropit.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy Info.plist and AppIcon
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Source files
SOURCES=(
    "Sources/Network/FileMIME.swift"
    "Sources/Network/NetworkHelper.swift"
    "Sources/Network/DER.swift"
    "Sources/Network/TLSCertificateManager.swift"
    "Sources/Network/FileSystemBridge.swift"
    "Sources/Network/DeviceProviderRegistry.swift"
    "Sources/Network/DeviceStorageClient.swift"
    "Sources/Network/DiscoveryResponder.swift"
    "Sources/Network/ClientConnection.swift"
    "Sources/Network/SecureConnectionBridge.swift"
    "Sources/Web/ReceiverWebTemplate.swift"
    "Sources/Network/HTTPServer.swift"
    "Sources/Network/HTTPServer+Transfers.swift"
    "Sources/Network/HTTPServer+FileSystem.swift"
    "Sources/QRCode/QRCodeGenerator.swift"
    "Sources/Models/AppState.swift"
    "Sources/Views/DropZoneView.swift"
    "Sources/Views/SessionHubView.swift"
    "Sources/Views/DeviceStorageView.swift"
    "Sources/Views/ContentView.swift"
    "Sources/Main/main.swift"
)

echo "Compiling Swift sources..."
xcrun swiftc -O \
    -disable-sandbox \
    -module-cache-path .build/cache \
    "${SOURCES[@]}" \
    -o "$APP_BUNDLE/Contents/MacOS/Dropit"

# Sign bundle ad-hoc for local execution
echo "Signing application bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ Dropit.app built successfully!"
echo "📍 Location: $DIR/$APP_BUNDLE"
