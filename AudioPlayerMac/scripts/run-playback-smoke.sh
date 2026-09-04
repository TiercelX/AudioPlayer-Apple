#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MEDIA_DIR="${1:-${AUDIOPLAYER_SMOKE_MEDIA_DIR:-}}"
REPORT_DIR="${PROJECT_DIR}/build/reports"
DERIVED_DATA_DIR="${PROJECT_DIR}/build/playback-smoke-derived"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_PATH="${REPORT_DIR}/playback-smoke-${TIMESTAMP}.json"

mkdir -p "${REPORT_DIR}"

if [[ -n "${MEDIA_DIR}" && ! -d "${MEDIA_DIR}" ]]; then
  echo "Media directory does not exist: ${MEDIA_DIR}" >&2
  exit 2
fi

echo "Writing playback smoke evidence to ${REPORT_PATH}"
if [[ -n "${MEDIA_DIR}" ]]; then
  echo "Using local media directory: ${MEDIA_DIR}"
else
  echo "No media directory provided; generated WAV evidence only."
fi

cd "${PROJECT_DIR}"
xcodebuild \
  -scheme AudioPlayerMac \
  -configuration Debug \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  build-for-testing

XCTESTRUN_PATH="$(find "${DERIVED_DATA_DIR}/Build/Products" -name '*.xctestrun' -print -quit)"
if [[ -z "${XCTESTRUN_PATH}" ]]; then
  echo "Could not find .xctestrun under ${DERIVED_DATA_DIR}/Build/Products" >&2
  exit 3
fi

TEST_ENV=":TestConfigurations:0:TestTargets:0:EnvironmentVariables"
TESTING_ENV=":TestConfigurations:0:TestTargets:0:TestingEnvironmentVariables"
for ENV_PATH in "${TEST_ENV}" "${TESTING_ENV}"; do
  /usr/libexec/PlistBuddy -c "Delete ${ENV_PATH}:AUDIOPLAYER_SMOKE_REPORT" "${XCTESTRUN_PATH}" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Delete ${ENV_PATH}:AUDIOPLAYER_SMOKE_MEDIA_DIR" "${XCTESTRUN_PATH}" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add ${ENV_PATH}:AUDIOPLAYER_SMOKE_REPORT string ${REPORT_PATH}" "${XCTESTRUN_PATH}"
  /usr/libexec/PlistBuddy -c "Add ${ENV_PATH}:AUDIOPLAYER_SMOKE_MEDIA_DIR string ${MEDIA_DIR}" "${XCTESTRUN_PATH}"
done

xcodebuild \
  -xctestrun "${XCTESTRUN_PATH}" \
  -destination "platform=macOS" \
  -only-testing:AudioPlayerMacTests/AudioPlayerMacTests/testPlaybackSmokeEvidenceWithOptionalRealMedia \
  test-without-building

echo "Playback smoke evidence report: ${REPORT_PATH}"
