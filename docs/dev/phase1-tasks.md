# Phase 1 - MVP Tasks (Detailed)

## Overview
Goal: Basic playable audio player with hybrid playback architecture.
Duration: 3-4 weeks
Deliverable: Can play EAC3, TrueHD, FLAC, MP3, WAV with basic controls.

**Architecture note:** Phase 1 uses a hybrid playback strategy (see
`architecture.md`). Most formats go through AVPlayer (system decoder), WAV
goes through AVAudioEngine (PCM path). FFmpeg decoder for TrueHD is built
but not yet connected to the playback coordinator.

## Week 1: Project setup + Core audio

### Day 1-2: Xcode project setup
- [x] Create new Xcode project "AudioPlayerMac"
- [x] Configure project settings (macOS 12+ deployment target)
- [x] Create folder structure (App, Core, Decoders, Source, Diagnostics, UI)
- [x] Create initial files (AudioPlayerMacApp, AppState, AudioEngine,
      PlaybackController, DecoderRouter)

### Day 3-4: Format detection + routing
- [x] Implement AudioFormatDetector
  - Extension-based fast path (eac3, ac3, flac, wav, mp3, truehd, etc.)
  - AVAsset probe for ambiguous extensions (m4a, mp4, caf)
  - Returns AudioFormat enum
- [x] Implement DecoderRouter
  - Routes to PlaybackRoute with PlaybackBackendKind
  - WAV → .pcmEngine (AVAudioEngine)
  - MP3/AAC/ALAC/FLAC/AC3/EAC3 → .nativeFilePlayer (AVPlayer)
  - TrueHD/MLP → .ffmpegFallback (throws, not yet connected)
  - Unknown + system extension → .nativeFilePlayer

### Day 5: Playback backends
- [x] Implement AudioEngine (AVAudioEngine + AVAudioPlayerNode for WAV)
- [x] Implement PlaybackBackend protocol (prepare/play/pause/resume/stop/seek)
- [x] Implement NativeFilePlayerBackend (AVPlayer wrapper)
- [x] Implement PCMEngineBackend (AudioEngine wrapper)
- [x] Implement PlaybackCoordinator (state machine, position timer, backend
  lifecycle)

## Week 2: FFmpeg integration + UI

### Day 1-2: FFmpeg setup
- [x] Build universal FFmpeg audio-core library (arm64 + x86_64)
- [x] Create FFmpegBridge C layer (header + implementation)
- [x] Wire FFmpeg into Xcode build (header search paths, linker flags)

### Day 3-4: FFmpeg decoder (exists, not wired)
- [x] Implement FFmpegWrapper (Swift wrapper around C bridge)
- [x] Implement FFmpegDecoder (AudioDecoder protocol with PcmSeekCache)
- [ ] Wire FFmpegDecoder into PlaybackCoordinator
- [ ] End-to-end TrueHD playback test

### Day 5: UI
- [x] Implement MainWindow (SwiftUI)
- [x] Implement PlayerControlsView (play/pause/stop/seek/volume)
- [x] Wire UI to PlaybackCoordinator
- [x] Implement MediaInfoView

## Week 3: Output + Polish

### Day 1-2: Output device management
- [x] Implement OutputDeviceManager (CoreAudio enumeration/selection)
- [ ] Add device selection UI

### Day 3-4: Diagnostics
- [x] Implement PlayerLogger (structured logging, per-launch rotation)
- [x] Implement AudioArtifactMonitor (exists, not wired -- needs PCM path)
- [x] Implement DiagnosticReportBuilder
- [ ] Add file drag & drop
- [ ] Add keyboard shortcuts (Space = play/pause)

## Week 4: Testing + Stabilization

### Day 1-2: Testing
- [ ] Test all supported formats (EAC3, AC3, FLAC, MP3, WAV, AAC, ALAC)
- [ ] Test seek functionality across backends
- [ ] Test output device switching
- [ ] Test error cases (corrupted files, unsupported formats)

### Day 3-5: Bug fixes + documentation
- [ ] Fix issues found during testing
- [ ] Update docs to reflect actual implementation (partially done)

## Acceptance criteria

- [x] Can open and play EAC3, FLAC, MP3, WAV files via hybrid backend
- [x] Play/Pause/Stop controls work correctly
- [x] Volume control works
- [x] Progress bar shows current position
- [x] Time labels show current time and total duration
- [ ] TrueHD playback works (FFmpeg decoder not yet connected)
- [ ] Output device selection UI
- [ ] No crashes during normal operation
- [ ] Memory usage is reasonable (< 200MB for typical files)

## What is connected vs. reserved

### Connected in Phase 1 playback path

| Component | File | Role |
|-----------|------|------|
| PlaybackCoordinator | Core/PlaybackController.swift | State machine, backend lifecycle |
| NativeFilePlayerBackend | Core/PlaybackController.swift | AVPlayer for most formats |
| PCMEngineBackend | Core/PlaybackController.swift | AVAudioEngine for WAV |
| DecoderRouter | Core/DecoderRouter.swift | Format → backend selection |
| AudioFormatDetector | Decoders/Common/AudioFormatDetector.swift | Codec detection |
| AudioEngine | Core/AudioEngine.swift | AVAudioEngine + AVAudioPlayerNode |
| OutputDeviceManager | Core/OutputDeviceManager.swift | CoreAudio device management |
| SourcePreparer | Source/SourcePreparer.swift | Source validation |
| PlayerLogger | Diagnostics/PlayerLogger.swift | Structured logging |

### Exists in tree but not wired

| Component | File | Why not wired |
|-----------|------|---------------|
| FFmpegDecoder | Decoders/FFmpeg/FFmpegDecoder.swift | Reserved for TrueHD |
| FFmpegWrapper | Decoders/FFmpeg/FFmpegWrapper.swift | Used by FFmpegDecoder |
| AVFoundationDecoder | Decoders/AVFoundation/AVFoundationDecoder.swift | Legacy; AVPlayer used instead |
| DolbyDownmixProcessor | Decoders/Common/DolbyDownmixProcessor.swift | Needs PCM path |
| AudioArtifactMonitor | Diagnostics/AudioArtifactMonitor.swift | Needs PCM path |
| PcmSeekCache | Decoders/Common/PcmSeekCache.swift | Used by FFmpegDecoder |
| PcmStreamBuffer | Decoders/Common/PcmStreamBuffer.swift | Not yet needed |

## Phase 2 preview

After Phase 1, the next priorities are:
- Connect FFmpegDecoder for TrueHD playback
- Dolby downmix for FFmpeg-decoded multichannel output
- AudioArtifactMonitor integration (PCM path)
- Device selection UI
- "PCM everywhere" mode for metering/DSP on non-Atmos formats

## Validation commands

```bash
# Build
xcodebuild -scheme AudioPlayerMac -configuration Debug build

# Run
open build/Debug/AudioPlayerMac.app
```

## See also

- Hybrid strategy: `docs/dev/architecture.md`
- Decoder routing: `docs/dev/decoder-paths.md`
- FFmpeg integration: `docs/dev/ffmpeg-integration.md`
- Validation checklist: `docs/dev/validation.md`
