#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_DIR="${PROJECT_DIR}/test-files"
DURATION="${1:-5}"

if ! command -v ffmpeg &>/dev/null; then
  echo "ERROR: ffmpeg not found. Install with: brew install ffmpeg" >&2
  exit 1
fi

mkdir -p "${TEST_DIR}"

echo "Generating test files (${DURATION}s each) into ${TEST_DIR}"

# WAV (PCM 16-bit, 44.1kHz, mono)
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=${DURATION}" \
  -ar 44100 -ac 1 -sample_fmt s16 "${TEST_DIR}/test-sine.wav" 2>/dev/null
echo "  WAV  test-sine.wav"

# MP3
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=${DURATION}" \
  -ar 44100 -ac 2 "${TEST_DIR}/test-sine.mp3" 2>/dev/null
echo "  MP3  test-sine.mp3"

# FLAC
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=${DURATION}" \
  -ar 44100 -ac 2 "${TEST_DIR}/test-sine.flac" 2>/dev/null
echo "  FLAC test-sine.flac"

# AAC (M4A container)
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=${DURATION}" \
  -ar 44100 -ac 2 -c:a aac "${TEST_DIR}/test-sine.m4a" 2>/dev/null
echo "  AAC  test-sine.m4a"

# ALAC (M4A container)
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=${DURATION}" \
  -ar 44100 -ac 2 -c:a alac "${TEST_DIR}/test-sine-alac.m4a" 2>/dev/null
echo "  ALAC test-sine-alac.m4a"

# AC3
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=${DURATION}" \
  -ar 48000 -ac 2 -c:a ac3 "${TEST_DIR}/test-sine.ac3" 2>/dev/null
echo "  AC3  test-sine.ac3"

# EAC3
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=${DURATION}" \
  -ar 48000 -ac 2 -c:a eac3 "${TEST_DIR}/test-sine.eac3" 2>/dev/null
echo "  EAC3 test-sine.eac3"

echo ""
echo "Done. Files in ${TEST_DIR}:"
ls -lh "${TEST_DIR}"/test-sine.* 2>/dev/null
