# Validation Checklist

## Overview

This document defines the validation requirements for AudioPlayerMac. All validation must report PASS, FAIL, or INCONCLUSIVE.

## Build validation

### Debug build
```bash
xcodebuild -scheme AudioPlayerMac -configuration Debug build
```
**Expected**: Build succeeds with no errors

### Release build
```bash
xcodebuild -scheme AudioPlayerMac -configuration Release build
```
**Expected**: Build succeeds with no errors

## Smoke tests

### Basic playback test
1. Open a FLAC file
2. Verify playback starts
3. Verify audio output is audible
4. Pause playback
5. Verify playback pauses
6. Resume playback
7. Verify playback resumes
8. Stop playback
9. Verify playback stops

**Report format**:
```json
{
  "test": "basic-playback",
  "result": "PASS|FAIL|INCONCLUSIVE",
  "details": "...",
  "timestamp": "2026-06-04T12:00:00Z"
}
```

### Format support test
Test each supported format:

| Format | Test file | Expected result |
|--------|-----------|-----------------|
| EAC3 | test.eac3 | PASS |
| AC3 | test.ac3 | PASS |
| AAC | test.aac | PASS |
| ALAC | test.alac | PASS |
| FLAC | test.flac | PASS |
| WAV | test.wav | PASS |
| MP3 | test.mp3 | PASS |
| TrueHD | test.thd | PASS |

**Report format**:
```json
{
  "test": "format-support",
  "result": "PASS|FAIL|INCONCLUSIVE",
  "formats": {
    "eac3": "PASS|FAIL",
    "ac3": "PASS|FAIL",
    "aac": "PASS|FAIL",
    "alac": "PASS|FAIL",
    "flac": "PASS|FAIL",
    "wav": "PASS|FAIL",
    "mp3": "PASS|FAIL",
    "truehd": "PASS|FAIL"
  },
  "timestamp": "2026-06-04T12:00:00Z"
}
```

### Seek test
1. Open a file
2. Start playback
3. Seek to middle of file
4. Verify playback continues from new position
5. Seek to end of file
6. Verify playback stops

**Report format**:
```json
{
  "test": "seek",
  "result": "PASS|FAIL|INCONCLUSIVE",
  "details": "...",
  "timestamp": "2026-06-04T12:00:00Z"
}
```

### Output device test
1. Open a file
2. Start playback
3. Switch output device
4. Verify audio continues on new device

**Report format**:
```json
{
  "test": "output-device",
  "result": "PASS|FAIL|INCONCLUSIVE",
  "details": "...",
  "timestamp": "2026-06-04T12:00:00Z"
}
```

## Audio quality validation

### Artifact detection
1. Play test file
2. Monitor for pops/clicks
3. Report findings

**Report format**:
```json
{
  "test": "artifact-detection",
  "result": "PASS|FAIL|INCONCLUSIVE",
  "artifacts_detected": 0,
  "details": "...",
  "timestamp": "2026-06-04T12:00:00Z"
}
```

### Level check
1. Play test file
2. Monitor audio levels
3. Verify no clipping

**Report format**:
```json
{
  "test": "level-check",
  "result": "PASS|FAIL|INCONCLUSIVE",
  "peak_level_db": -6.0,
  "clipping_detected": false,
  "timestamp": "2026-06-04T12:00:00Z"
}
```

## Performance validation

### Memory usage
1. Open large file (>100MB)
2. Play for 5 minutes
3. Monitor memory usage

**Report format**:
```json
{
  "test": "memory-usage",
  "result": "PASS|FAIL|INCONCLUSIVE",
  "peak_memory_mb": 150,
  "timestamp": "2026-06-04T12:00:00Z"
}
```

### CPU usage
1. Play file
2. Monitor CPU usage

**Report format**:
```json
{
  "test": "cpu-usage",
  "result": "PASS|FAIL|INCONCLUSIVE",
  "average_cpu_percent": 5.0,
  "timestamp": "2026-06-04T12:00:00Z"
}
```

## Validation scripts

### run-playback-smoke.sh

The primary smoke test script is at `AudioPlayerMac/scripts/run-playback-smoke.sh`.

```bash
# Usage:
#   ./scripts/run-playback-smoke.sh [media-directory]
#
# Runs the playback smoke evidence XCTest entry point and writes a JSON
# report to AudioPlayerMac/build/reports/playback-smoke-<timestamp>.json.
# If a media directory is provided, real media files are tested alongside
# the generated WAV. Without a media directory, only generated WAV evidence
# is produced.
#
# Environment variables:
#   AUDIOPLAYER_SMOKE_MEDIA_DIR - path to test media directory
#   AUDIOPLAYER_SMOKE_REPORT   - path to write JSON report
```

### Format tests

Format testing is integrated into `testPlaybackSmokeEvidenceWithOptionalRealMedia`
in `AudioPlayerMac/Tests/AudioPlayerMacTests.swift`. When `AUDIOPLAYER_SMOKE_MEDIA_DIR`
points to a directory containing test media, the smoke test automatically discovers
one file per known format (WAV, MP3, AAC, ALAC, FLAC, AC3, EAC3) and reports
PASS/FAIL per format in the JSON report.

## Validation reports

### Report location
Reports are saved to:
```
AudioPlayerMac/build/reports/
└── playback-smoke-<YYYYMMDD-HHMMSS>.json
```

### Report format
```json
{
  "test": "playback-core-smoke-evidence",
  "timestamp": "2026-06-05T01:39:19Z",
  "audiblePlaybackEvidence": "INCONCLUSIVE",
  "cases": [
    {
      "inputFilePath": "/path/to/file.wav",
      "source": "generated",
      "detectedFormat": "wav",
      "selectedBackend": "PCMEngineBackend",
      "uiState": "open=Ready | play=Playing | pause=Paused | resume=Playing | stop=Stopped",
      "transportStates": {
        "play": "playing",
        "pause": "paused",
        "resume": "playing",
        "stop": "stopped"
      },
      "audibleSound": "INCONCLUSIVE",
      "result": "PASS"
    }
  ]
}
```

## Acceptance criteria

### Phase 1 acceptance
- [x] Debug build succeeds
- [x] Generated WAV transport (open/play/pause/resume/stop) passes
- [x] Local ALAC/M4A and FLAC transport evidence passes
- [ ] All supported formats play correctly (MP3, AAC, AC3, EAC3 not yet verified)
- [ ] Seek works correctly
- [ ] Output device switching works
- [ ] No crashes during normal operation
- [ ] Audible playback verified (manual evidence)

### Phase 2 acceptance
- [ ] Dolby downmix works correctly
- [ ] PCM seek cache improves seek performance
- [ ] Media info displays correctly
- [ ] Cache settings work
- [ ] Diagnostic reports generate correctly

### Phase 3 acceptance
- [ ] Audio artifact detection works
- [ ] Spatial audio works with AirPods
- [ ] CLI automation works
- [ ] All diagnostic reports are complete

## Evidence collection

### Collect evidence
```bash
#!/bin/bash
# Collect validation evidence into a single directory

BUILD_DIR="${1:-build}"
OUTPUT_DIR="${2:-evidence}"

mkdir -p "$OUTPUT_DIR"

# Copy reports
cp "$BUILD_DIR"/reports/*.json "$OUTPUT_DIR/" 2>/dev/null || true

# Create manifest
cat > "$OUTPUT_DIR/manifest.json" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "build_dir": "$BUILD_DIR",
  "reports": $(ls "$OUTPUT_DIR"/*.json 2>/dev/null | xargs -I{} basename {} | jq -R . | jq -s .)
}
EOF

echo "Evidence collected to $OUTPUT_DIR"
```

## Continuous integration

CI is not yet configured. The intended workflow:

```yaml
# .github/workflows/validate.yml (template, not yet active)

name: Validate

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14

    steps:
    - uses: actions/checkout@v3

    - name: Build
      run: |
        xcodebuild -scheme AudioPlayerMac -configuration Debug build

    - name: Smoke Test
      run: |
        ./AudioPlayerMac/scripts/run-playback-smoke.sh

    - name: Upload Reports
      uses: actions/upload-artifact@v3
      with:
        name: validation-reports
        path: AudioPlayerMac/build/reports/
```
