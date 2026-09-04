#!/bin/bash
# Build script for AudioPlayerMac

set -e

CONFIGURATION="${1:-Debug}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${2:-${PROJECT_DIR}/build}"
SCHEME="AudioPlayerMac"

echo "=== Building AudioPlayerMac ==="
echo "Configuration: $CONFIGURATION"
echo "Derived data: $DERIVED_DATA"
echo ""

if [ "$3" = "clean" ]; then
    echo "Cleaning build..."
    xcodebuild -project "${PROJECT_DIR}/AudioPlayerMac.xcodeproj" \
        -scheme "$SCHEME" -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA" clean
fi

echo "Building..."
xcodebuild -project "${PROJECT_DIR}/AudioPlayerMac.xcodeproj" \
    -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" build

echo ""
echo "=== Build Successful ==="
echo "App location: ${DERIVED_DATA}/Build/Products/${CONFIGURATION}/AudioPlayerMac.app"
