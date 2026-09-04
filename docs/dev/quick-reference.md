# Quick reference

One-page cheat sheet for common commands. Full details in the linked docs.

## Build

```bash
# Debug build
xcodebuild -project AudioPlayerMac/AudioPlayerMac.xcodeproj \
  -scheme AudioPlayerMac -configuration Debug build

# Clean + build
xcodebuild -project AudioPlayerMac/AudioPlayerMac.xcodeproj \
  -scheme AudioPlayerMac -configuration Debug clean build
```

## Test

```bash
# Unit tests
xcodebuild -project AudioPlayerMac/AudioPlayerMac.xcodeproj \
  -scheme AudioPlayerMac -configuration Debug test
```

## Smoke test

```bash
# Generated WAV only
./AudioPlayerMac/scripts/run-playback-smoke.sh

# With local media files
./AudioPlayerMac/scripts/run-playback-smoke.sh /path/to/media
```

## Generate test files

```bash
# Requires ffmpeg (brew install ffmpeg)
./AudioPlayerMac/scripts/generate-test-files.sh
```

## Collect evidence

```bash
./AudioPlayerMac/scripts/collect-evidence.sh [build-dir] [output-dir]
```

## Environment variables

| Variable | Purpose | Default |
| --- | --- | --- |
| `AUDIOPLAYER_LOG_LEVEL` | Log level | `info` |
| `AUDIOPLAYER_CACHE_DIR` | Cache directory | `~/Library/Caches/AudioPlayerMac` |
| `AUDIOPLAYER_FFMPEG_PATH` | FFmpeg path | Auto-detect |
| `AUDIOPLAYER_SMOKE_MEDIA_DIR` | Smoke test media dir | (none) |
| `AUDIOPLAYER_SMOKE_REPORT` | Smoke report output path | (auto) |

## Key files

| What | Where |
| --- | --- |
| App entry point | `AudioPlayerMac/AudioPlayerMac/App/AudioPlayerMacApp.swift` |
| Playback coordinator | `AudioPlayerMac/AudioPlayerMac/Core/PlaybackController.swift` (line 237) |
| Decoder router | `AudioPlayerMac/AudioPlayerMac/Core/DecoderRouter.swift` |
| Unit tests | `AudioPlayerMac/Tests/AudioPlayerMacTests.swift` |
| Smoke script | `AudioPlayerMac/scripts/run-playback-smoke.sh` |
| Smoke reports | `AudioPlayerMac/build/reports/` |
| Built app (Debug) | `AudioPlayerMac/build/Products/Debug/AudioPlayerMac.app` |

## Build output

By default xcodebuild writes to DerivedData. Use `./scripts/quick-build.sh` to
build and automatically copy the `.app` into the worktree under
`AudioPlayerMac/build/Products/<Config>/`.

## See also

- Full build guide: `docs/dev/build-guide.md`
- Validation checklist: `docs/dev/validation.md`
- Code map: `docs/dev/code-map.md`
