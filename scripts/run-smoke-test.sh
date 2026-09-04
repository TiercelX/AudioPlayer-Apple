#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$PROJECT_ROOT/AudioPlayerMac/build/Debug/AudioPlayerMac.app"
BINARY_PATH="$APP_PATH/Contents/MacOS/AudioPlayerMac"
MEDIA_DIR="$PROJECT_ROOT/media"

PASS_COUNT=0
FAIL_COUNT=0
INCONCLUSIVE_COUNT=0
TOTAL_COUNT=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Run smoke tests for AudioPlayerMac.

Options:
  --build     Build the app before running tests
  --help      Show this help message
EOF
}

BUILD_FIRST=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build)  BUILD_FIRST=1; shift ;;
        --help)   usage; exit 0 ;;
        *)        echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

log_pass() {
    ((PASS_COUNT++))
    ((TOTAL_COUNT++))
    echo "  PASS  $1"
}

log_fail() {
    ((FAIL_COUNT++))
    ((TOTAL_COUNT++))
    echo "  FAIL  $1"
}

log_inconclusive() {
    ((INCONCLUSIVE_COUNT++))
    ((TOTAL_COUNT++))
    echo "  INCONCLUSIVE  $1"
}

echo "========================================"
echo " AudioPlayerMac smoke test"
echo "========================================"
echo "Project:  $PROJECT_ROOT"
echo "Date:     $(date)"
echo "Host:     $(uname -m) / $(sw_vers -productVersion)"
echo ""

if [[ $BUILD_FIRST -eq 1 ]]; then
    echo "--- Building app ---"
    "$PROJECT_ROOT/scripts/quick-build.sh" Debug
    echo ""
fi

echo "--- Test 1: App bundle exists ---"
if [[ -d "$APP_PATH" ]]; then
    log_pass "App bundle exists at $APP_PATH"
else
    log_fail "App bundle not found at $APP_PATH"
    echo ""
    echo "========================================"
    echo " Smoke test aborted: no app bundle"
    echo "========================================"
    exit 1
fi

echo ""
echo "--- Test 2: Bundle structure ---"
BUNDLE_OK=1
for item in \
    "Contents/Info.plist" \
    "Contents/MacOS/AudioPlayerMac" \
    "Contents/PkgInfo" \
    "Contents/_CodeSignature"; do
    if [[ -e "$APP_PATH/$item" ]]; then
        log_pass "Bundle contains $item"
    else
        log_fail "Bundle missing $item"
        BUNDLE_OK=0
    fi
done

echo ""
echo "--- Test 3: Binary validation ---"
if [[ -f "$BINARY_PATH" ]]; then
    FILE_TYPE=$(file "$BINARY_PATH")
    if echo "$FILE_TYPE" | grep -q "Mach-O"; then
        log_pass "Binary is Mach-O executable"
    else
        log_fail "Binary is not Mach-O: $FILE_TYPE"
    fi

    LIPO_INFO=$(lipo -info "$BINARY_PATH" 2>/dev/null || echo "unknown")
    if echo "$LIPO_INFO" | grep -q "Architectures in the fat file"; then
        log_pass "Binary is universal ($LIPO_INFO)"
    elif echo "$LIPO_INFO" | grep -q "Non-fat file"; then
        log_inconclusive "Binary is single-arch ($LIPO_INFO)"
    else
        log_inconclusive "Could not determine binary architecture"
    fi
else
    log_fail "Binary not found at $BINARY_PATH"
fi

echo ""
echo "--- Test 4: FFmpeg library integration ---"
if [[ -f "$BINARY_PATH" ]]; then
    OTOOL_OUTPUT=$(otool -L "$BINARY_PATH" 2>/dev/null || true)
    NM_OUTPUT=$(nm "$BINARY_PATH" 2>/dev/null || true)

    HAS_DYNAMIC=0
    for lib in libavformat libavcodec libswresample libavutil; do
        if echo "$OTOOL_OUTPUT" | grep -q "$lib"; then
            log_pass "Binary dynamically links $lib"
            HAS_DYNAMIC=1
        fi
    done

    if [[ $HAS_DYNAMIC -eq 0 ]]; then
        STATIC_SYMBOLS=0
        for sym in AVFormatContext AVCodecContext AVPacket avformat avcodec swresample avutil; do
            COUNT=$(printf '%s' "$NM_OUTPUT" | grep -ci "$sym" || true)
            if [[ $COUNT -gt 0 ]]; then
                STATIC_SYMBOLS=$((STATIC_SYMBOLS + 1))
            fi
        done
        if [[ $STATIC_SYMBOLS -gt 0 ]]; then
            log_pass "FFmpeg statically linked ($STATIC_SYMBOLS symbols found)"
        else
            log_inconclusive "FFmpeg linking status unknown"
        fi
    fi

    if echo "$OTOOL_OUTPUT" | grep -q "libav"; then
        echo ""
        echo "  Linked FFmpeg libraries:"
        echo "$OTOOL_OUTPUT" | grep "libav" | sed 's/^/    /'
    fi
else
    log_fail "Cannot check linking: binary not found"
fi

echo ""
echo "--- Test 5: Test media files ---"
EXPECTED_FILES=(
    "003-グランドエスケープ feat. 三浦透子.m4a"
    "01 Inferno.flac"
    "POWDER SNOW Live V9.8.6.eb3"
    "POWDER SNOW Live V9.8.6.mlp"
)

for f in "${EXPECTED_FILES[@]}"; do
    FILE_PATH="$MEDIA_DIR/$f"
    if [[ -f "$FILE_PATH" ]]; then
        SIZE=$(du -h "$FILE_PATH" | cut -f1)
        log_pass "Media file exists: $f ($SIZE)"
    else
        log_fail "Media file missing: $f"
    fi
done

echo ""
echo "--- Test 6: App Info.plist ---"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ -f "$INFO_PLIST" ]]; then
    BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST" 2>/dev/null || echo "unknown")
    VERSION=$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST" 2>/dev/null || echo "unknown")
    log_pass "Bundle ID: $BUNDLE_ID"
    log_pass "Version: $VERSION"
else
    log_fail "Info.plist not found"
fi

echo ""
echo "========================================"
echo " Smoke test summary"
echo "========================================"
echo "Total:         $TOTAL_COUNT"
echo "Pass:          $PASS_COUNT"
echo "Fail:          $FAIL_COUNT"
echo "Inconclusive:  $INCONCLUSIVE_COUNT"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo "Result: FAIL"
    exit 1
elif [[ $INCONCLUSIVE_COUNT -gt 0 ]]; then
    echo "Result: INCONCLUSIVE"
    exit 0
else
    echo "Result: PASS"
    exit 0
fi
