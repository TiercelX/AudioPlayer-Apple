#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="AudioPlayerMac"
CONFIG="${1:-Debug}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [CONFIGURATION]

Build AudioPlayerMac with xcodebuild and copy the .app to the worktree.

Arguments:
  CONFIGURATION   Build configuration: Debug (default) or Release

Options:
  --help          Show this help message
EOF
}

if [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

echo "========================================"
echo " AudioPlayerMac quick build"
echo "========================================"
echo "Scheme:   $SCHEME"
echo "Config:   $CONFIG"
echo "Project:  $PROJECT_ROOT/AudioPlayerMac"
echo ""

START_TIME=$(date +%s)

xcodebuild \
    -project "$PROJECT_ROOT/AudioPlayerMac/AudioPlayerMac.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    build

# Locate the built .app via xcodebuild -showBuildSettings
BUILD_SETTINGS_APP=$(
    xcodebuild \
        -project "$PROJECT_ROOT/AudioPlayerMac/AudioPlayerMac.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -showBuildSettings 2>/dev/null \
    | grep -m1 'BUILT_PRODUCTS_DIR' \
    | sed 's/.*= //'
)

WORKTREE_PRODUCTS="$PROJECT_ROOT/AudioPlayerMac/build/Products/$CONFIG"
APP_NAME="AudioPlayerMac.app"

if [[ -n "$BUILD_SETTINGS_APP" && -d "$BUILD_SETTINGS_APP/$APP_NAME" ]]; then
    mkdir -p "$WORKTREE_PRODUCTS"
    cp -R "$BUILD_SETTINGS_APP/$APP_NAME" "$WORKTREE_PRODUCTS/"
    echo ""
    echo "Copied $APP_NAME to worktree:"
    echo "  $WORKTREE_PRODUCTS/$APP_NAME"
else
    # Fallback: find the most recent DerivedData for this project
    DD_APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/AudioPlayerMac-*/Build/Products/"$CONFIG/$APP_NAME" 2>/dev/null | head -1)
    if [[ -n "$DD_APP" && -d "$DD_APP" ]]; then
        mkdir -p "$WORKTREE_PRODUCTS"
        cp -R "$DD_APP" "$WORKTREE_PRODUCTS/"
        echo ""
        echo "Copied $APP_NAME to worktree (fallback):"
        echo "  $WORKTREE_PRODUCTS/$APP_NAME"
    else
        echo ""
        echo "WARNING: Could not locate built app."
        echo "Check DerivedData: ~/Library/Developer/Xcode/DerivedData/AudioPlayerMac-*/"
    fi
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo ""
echo "========================================"
echo " Build complete"
echo "========================================"
echo "Duration: ${ELAPSED}s"
echo "Config:   $CONFIG"
echo "App:      $WORKTREE_PRODUCTS/$APP_NAME"
