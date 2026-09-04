# Playback core smoke evidence

This file tracks Phase 1.1 Apple-native smoke evidence for ordinary media
playback. Keep durable workflow rules in `AGENTS.md` and `docs/dev/*.md`.

## Status refresh: 2026-06-05

- Scope is ordinary Apple-native playback only.
- This tracker does not cover FFmpeg hookup, TrueHD/MLP, MKV remux,
  EAC3-JOC/Atmos rendering, UI polish, or Instruments leak validation.
- Automated evidence can verify routing, backend state, AVPlayer item status or
  AVAudioEngine running logs, and transport state transitions.
- Automated evidence cannot verify physical endpoint audio. Audible playback
  remains manual evidence only.

## Current focus

- Use generated WAV evidence for the `PCMEngineBackend` path.
- Use local real media evidence for ALAC/M4A and FLAC native AVPlayer paths.
- Keep MP3 and AAC/M4A listed as not yet verified until real local samples are
  provided and heard.

## Current validation baseline

- Command:
  `AudioPlayerMac/scripts/run-playback-smoke.sh <local-media-dir>`
- Result: PASS for generated WAV, local ALAC/M4A, and local FLAC automated
  transport evidence; FAIL observation for optional EB3/EAC3 native candidate.
- Report path:
  `AudioPlayerMac/build/reports/playback-smoke-20260605-013919.json`
- Evidence limit: all `audibleSound` fields are `INCONCLUSIVE`.

## Automated Evidence

| Format | Input file path | Selected backend | Detected format/container/extension | AVPlayer item status / AVAudioEngine running | UI state | Transport | Audible sound | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| WAV | Generated temp WAV at `/var/folders/.../AudioPlayerMac-smoke-23F444EB-31FD-4FDD-BB02-7BC8D7C9EB22.wav` | `PCMEngineBackend` | `wav` / `wav` | `PCMEngineBackend start running=true` | Ready -> Playing -> Paused -> Playing -> Stopped | play/pause/resume/stop normal | INCONCLUSIVE | PASS |
| ALAC/M4A | `<local-media-dir>/sample-alac.m4a` | `NativeFilePlayerBackend` | `alac` / `m4a` | `readyToPlay` | Ready -> Playing -> Paused -> Playing -> Stopped | play/pause/resume/stop normal | INCONCLUSIVE | PASS |
| FLAC | `<local-media-dir>/sample.flac` | `NativeFilePlayerBackend` | `flac` / `flac` | `readyToPlay` | Ready -> Playing -> Paused -> Playing -> Stopped | play/pause/resume/stop normal | INCONCLUSIVE | PASS |
| EAC3 candidate | `<local-media-dir>/sample.eb3` | `NativeFilePlayerBackend` | `eac3` / `eb3` | `failed: Cannot Open` | Unsupported/Failed: Cannot Open | not run after failed open | INCONCLUSIVE | FAIL |

## Manual Evidence

No manual audible playback pass was recorded in this round.

Manual smoke rows must record:

- input file path
- selected backend
- detected format/container/extension
- AVPlayer item status or AVAudioEngine running state
- UI state
- whether sound was actually heard
- pause/resume/stop behavior
- PASS, FAIL, or INCONCLUSIVE

## Not Yet Verified

| Format | Reason |
| --- | --- |
| MP3 | No MP3 sample found in the local media directory; do not infer from build/test. |
| AAC/M4A | Local M4A sample is ALAC, not AAC; provide a real AAC/M4A sample before claiming support. |
| Real WAV | Generated WAV covers `PCMEngineBackend` transport, but no real user-provided WAV sample was present. |
| Audible ALAC/M4A | Automated transport passed, but no physical endpoint listening evidence was recorded. |
| Audible FLAC | Automated transport passed, but no physical endpoint listening evidence was recorded. |
| AC3/EAC3 playback | EB3/EAC3 native candidate failed with AVPlayer `Cannot Open`; no Atmos/JOC claim is made. |

## Dated notes

- 2026-06-05: Added optional smoke evidence test and
  `AudioPlayerMac/scripts/run-playback-smoke.sh`. Local automated run passed for
  generated WAV, ALAC/M4A, and FLAC transport evidence. Optional EB3/EAC3
  candidate failed to open in AVPlayer with `Cannot Open`. Audible playback is
  still `INCONCLUSIVE`.
