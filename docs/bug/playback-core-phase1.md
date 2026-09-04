# Playback core phase 1 status

This file tracks the Apple-native playback core rewrite. Keep durable rules in
`AGENTS.md` and `docs/dev/*.md`.

## Status refresh: 2026-06-05

- Playback now enters through `PlaybackCoordinator`, with `PlaybackController`
  left as a compatibility wrapper.
- `DecoderRouter` selects `NativeFilePlayerBackend` as the system-native
  candidate for MP3/AAC/M4A/ALAC/FLAC and compressed AC3/EAC3 candidates,
  preserving the original compressed source.
- `DecoderRouter` selects `PCMEngineBackend` for WAV/PCM via `AVAudioEngine`.
- TrueHD/MLP route to an explicit unsupported/reserved FFmpeg fallback error;
  FFmpeg files remain in the tree but are not connected in this phase.
- `SourcePreparer` validates the input file and no longer remuxes EAC3 or
  TrueHD/MLP to WAV.
- The UI exposes the current playback status/error text so unsupported formats
  are not silent.

## Current focus

- Stabilize ordinary file open/play/pause/resume/stop behavior with clear logs.
- Keep EAC3/JOC candidates on the native compressed-source path and fail
  explicitly if AVPlayer cannot play them.

## Current priority order

1. Validate with real local WAV, MP3/M4A/AAC/ALAC/FLAC, and EAC3 samples.
2. Add a small runtime smoke harness that opens files and reports PASS, FAIL, or
   INCONCLUSIVE per evidence layer.
3. Defer FFmpeg PCM fallback, MKV remux, TrueHD/MLP, and Atmos claims.

## Current validation baseline

- `xcodebuild -scheme AudioPlayerMac -configuration Debug build` from
  `AudioPlayerMac/` passed on 2026-06-05.
- `xcodebuild -scheme AudioPlayerMac -configuration Debug test` from
  `AudioPlayerMac/` passed on 2026-06-05.
- Unit tests include generated-WAV coverage that prepares `PCMEngineBackend`,
  starts AVAudioEngine-backed playback, pauses, resumes, and stops.
- Phase 1.1 smoke evidence is tracked in `docs/bug/playback-core-smoke.md`.
  The 2026-06-05 automated local run passed generated WAV, ALAC/M4A, and FLAC
  transport evidence, while audible playback remains inconclusive.
- Validation does not yet prove physical endpoint audio quality, no memory
  leaks, MP3/AAC real-media playback, or Atmos/JOC rendering. The checkout does
  not contain large media files; Phase 1.1 local ALAC/M4A and FLAC evidence used
  external files under a local media directory.

## Current acceptance bar

- WAV enters `PCMEngineBackend` and starts `AVAudioEngine` without crashing.
- MP3/AAC/M4A/ALAC/FLAC enter `NativeFilePlayerBackend` or an explicit
  system-playable native candidate route.
- EAC3/JOC candidates preserve compressed source and use the native backend;
  failure must become a visible failed/unsupported state.
- Unsupported formats must display a user-visible unsupported/failed message
  and write a clear log entry.

## Dated notes

- 2026-06-05: Replaced old decoder/buffer-oriented playback control with
  coordinator/backend routing. Build and unit tests passed, including generated
  WAV `PCMEngineBackend` start/pause/resume/stop coverage. Real audio sample,
  Atmos/JOC rendering, and Instruments leak validation remain unproven.
- 2026-06-05: Added Phase 1.1 smoke evidence tracker and optional local-media
  smoke test entry point. Generated WAV, local ALAC/M4A, and local FLAC
  automated transport evidence passed; EB3/EAC3 native candidate failed with
  AVPlayer `Cannot Open`; physical audible playback remains unverified.
