#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

if [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
elif [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

mkdir -p .build/cache
rm -f .build/test_runner

SOURCES=(
    "Sources/Network/FileMIME.swift"
    "Sources/Network/NetworkHelper.swift"
    "Sources/Web/ReceiverWebTemplate.swift"
    "Sources/QRCode/QRCodeGenerator.swift"
    "Sources/Models/AppState.swift"
    "Sources/Network/HTTPServer.swift"
    "Tests/test_transfer.swift"
)

xcrun swiftc -Onone \
    -disable-sandbox \
    -module-cache-path .build/cache \
    "${SOURCES[@]}" \
    -o .build/test_runner

echo "Running test_runner..."
.build/test_runner
