#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

if [ ! -f "Dropit.app/Contents/MacOS/Dropit" ]; then
    echo "App not built yet. Building now..."
    ./build.sh
fi

echo "🚀 Launching Dropit..."
open "$DIR/Dropit.app"
