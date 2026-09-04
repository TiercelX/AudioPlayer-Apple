# AudioPlayerMac Project Instructions

Durable rules for this macOS audio player. Detailed guidance lives in `docs/dev/*.md`.

## Project overview
Native macOS audio player with Dolby Atmos support, built with Swift + AVFoundation + FFmpeg libav. This is a new project derived from the Windows AudioPlayer (C++ + Qt).

## Version strategy
- Minimum deployment target: macOS 12 Monterey
- Recommended: macOS 14 Sonoma (enhanced spatial audio)
- Progressive enhancement: macOS 26 Tahoe (Liquid Glass UI)

## Technical stack
- Language: Swift 5.9+
- UI: SwiftUI + AppKit (NSViewRepresentable for complex controls)
- Audio engine: AVAudioEngine
- Native decoder: AVFoundation (EAC3/AC3/AAC/FLAC/WAV/MP3)
- FFmpeg decoder: libav C library via Swift-C bridge
- Build system: Xcode 15+ with Swift Package Manager

## General collaboration
- Make minimal, localized changes and keep the existing project structure unless there is a concrete reason to do otherwise.
- Explain the plan before editing code; keep plans and progress updates brief.
- Prefer SwiftUI and AVFoundation APIs.
- Do not rename files or classes unless required.
- Read and edit the smallest relevant set of files needed for the task.
- Commit only completed implementation work after validation passes.

## Audio architecture
- Preserve AVFoundation as primary decoder for supported formats.
- Use FFmpeg libav for TrueHD and complex formats.
- Route format detection through DecoderRouter before selecting decoder path.
- Preserve AVAudioEngine as output layer.
- Let system handle spatial audio rendering for AirPods head tracking.

## Dolby support
- EAC3/AC3: AVFoundation native decoding.
- TrueHD: FFmpeg libav decoding.
- Dolby downmix: Preserve LoRo/LtRt matrix coefficients from original project.
- Atmos metadata: AVFoundation handles EAC3-JOC; TrueHD decoded to multichannel PCM.

## Playback architecture invariants
- Preserve dual-thread model: decoder thread + audio output thread.
- Preserve teardown order: release audio output, stop decoder, clear buffer.
- Preserve per-launch log rotation: timestamp plus PID.

## Diagnostics honesty
- Do not guess fixes for audible pops/clicks without improving observability.
- Treat decoder-side PCM, internal levels, and actual output-device audio as different evidence layers.
- Smoke tests must report PASS, FAIL, or INCONCLUSIVE.

## Validation requirements
- Build must succeed with `xcodebuild -scheme AudioPlayerMac -configuration Debug`
- Smoke test must pass with test EAC3, TrueHD, FLAC, MP3 files
- No memory leaks detected by Instruments

## Progressive disclosure

See `docs/dev/README.md` for the full index with reading order.

### Entry points
- General workflow and scope: `docs/dev/agent-workflow.md`.
- Code/file navigation map: `docs/dev/code-map.md`.
- Build, smoke-test, and playback automation: `docs/dev/build-guide.md`.
- Validation checklist and report schema: `docs/dev/validation.md`.
- One-page command cheat sheet: `docs/dev/quick-reference.md`.
- Bug/status tracking index: `docs/bug/README.md`.

### Architecture reference
- High-level architecture overview: `docs/dev/architecture.md`.
- AVFoundation vs FFmpeg decoder path rules: `docs/dev/decoder-paths.md`.
- Dolby LoRo/LtRt downmix design: `docs/dev/dolby-downmix.md`.
- FFmpeg libav C bridge integration: `docs/dev/ffmpeg-integration.md`.
- Audio output format negotiation: `docs/dev/output-format.md`.
- PCM seek cache design: `docs/dev/pcm-seek-cache.md`.
- Spatial audio and AirPods head tracking: `docs/dev/spatial-audio.md`.
- Audio artifact detection design: `docs/dev/artifact-monitor.md`.

### Task planning and coordination
- Phase 1 MVP task breakdown: `docs/dev/phase1-tasks.md`.
- opencode local-agent workflow and handoff templates: `docs/dev/opencode-workflow.md`.

## Work modes
- Use opencode with Xiaomi MiMo as a local implementation agent when it can read/write the worktree and run local commands.
- Treat opencode output as advisory only if it cannot execute locally.
- Prevent conflicts with separate worktrees and branch names that include both executor and model, such as `opencode-MiMo-*`.
- Do not claim local validation from advisory-only tools.

## Current issue tracking
Use `docs/bug/README.md` as the index for current status trackers.
