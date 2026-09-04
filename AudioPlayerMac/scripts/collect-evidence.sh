#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${1:-${PROJECT_DIR}/build}"
OUTPUT_DIR="${2:-${PROJECT_DIR}/build/evidence}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "${OUTPUT_DIR}"

echo "Collecting evidence into ${OUTPUT_DIR}"

# Copy smoke reports
if ls "${BUILD_DIR}"/reports/*.json 1>/dev/null 2>&1; then
  cp "${BUILD_DIR}"/reports/*.json "${OUTPUT_DIR}/"
  echo "  Copied smoke reports"
else
  echo "  No smoke reports found in ${BUILD_DIR}/reports/"
fi

# Copy logs if present
if ls "${BUILD_DIR}"/logs/*.log 1>/dev/null 2>&1; then
  cp "${BUILD_DIR}"/logs/*.log "${OUTPUT_DIR}/"
  echo "  Copied logs"
fi

# Create manifest
MANIFEST="${OUTPUT_DIR}/manifest-${TIMESTAMP}.json"
cat > "${MANIFEST}" << MANIFEST_JSON
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "build_dir": "${BUILD_DIR}",
  "evidence_dir": "${OUTPUT_DIR}",
  "files": [
$(find "${OUTPUT_DIR}" -maxdepth 1 -name '*.json' -o -name '*.log' | sort | while read -r f; do echo "    \"$(basename "$f")\","; done | sed '$ s/,$//')
  ]
}
MANIFEST_JSON

echo "  Manifest: ${MANIFEST}"
echo ""
echo "Evidence collected to ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}"
