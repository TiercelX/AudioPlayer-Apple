# Code map

Use this page to choose the first files to inspect. It is a navigation aid, not
a replacement for the current status trackers in `docs/bug/`.

## App layer

- SwiftUI app entry point and window management:
  `AudioPlayerMac/AudioPlayerMac/App/AudioPlayerMacApp.swift`
- Global application state and playback orchestration:
  `AudioPlayerMac/AudioPlayerMac/App/AppState.swift`

## Core

- PCM/WAV AVAudioEngine setup and file scheduling:
  `AudioPlayerMac/AudioPlayerMac/Core/AudioEngine.swift`
- High-level playback coordination (open/play/pause/resume/stop/seek):
  `AudioPlayerMac/AudioPlayerMac/Core/PlaybackController.swift`
- Playback coordinator (Phase 1 entry point, wraps backends):
  `AudioPlayerMac/AudioPlayerMac/Core/PlaybackController.swift` (line 237, `PlaybackCoordinator`)
- Backend selection routing based on format detection:
  `AudioPlayerMac/AudioPlayerMac/Core/DecoderRouter.swift`
- Volume control with fade-in/out support:
  `AudioPlayerMac/AudioPlayerMac/Core/VolumeController.swift`
- Audio output device enumeration and switching:
  `AudioPlayerMac/AudioPlayerMac/Core/OutputDeviceManager.swift`

## Decoders

- Abstract decoder protocol and shared interface:
  `AudioPlayerMac/AudioPlayerMac/Decoders/Common/AudioDecoder.swift`
- Audio format detection and codec identification:
  `AudioPlayerMac/AudioPlayerMac/Decoders/Common/AudioFormatDetector.swift`
- Dolby LoRo/LtRt downmix matrix processing:
  `AudioPlayerMac/AudioPlayerMac/Decoders/Common/DolbyDownmixProcessor.swift`
- Streaming PCM buffer management:
  `AudioPlayerMac/AudioPlayerMac/Decoders/Common/PcmStreamBuffer.swift`
- Seek position cache for PCM decoding:
  `AudioPlayerMac/AudioPlayerMac/Decoders/Common/PcmSeekCache.swift`
- Decoder error types:
  `AudioPlayerMac/AudioPlayerMac/Decoders/Common/DecoderError.swift`
- Legacy AVFoundation PCM decoder compatibility. It is not the EAC3/Atmos path:
  `AudioPlayerMac/AudioPlayerMac/Decoders/AVFoundation/AVFoundationDecoder.swift`
- FFmpeg-based decoder files for future fallback work. Not connected in the
  Phase 1 Apple-native playback path:
  `AudioPlayerMac/AudioPlayerMac/Decoders/FFmpeg/FFmpegDecoder.swift`
- Swift wrapper around FFmpeg libav C functions:
  `AudioPlayerMac/AudioPlayerMac/Decoders/FFmpeg/FFmpegWrapper.swift`

## Source

- Media file metadata extraction:
  `AudioPlayerMac/AudioPlayerMac/Source/MediaInfo.swift`
- Playback plan (queue, next track logic):
  `AudioPlayerMac/AudioPlayerMac/Source/PlaybackPlan.swift`
- Source probing and format pre-analysis:
  `AudioPlayerMac/AudioPlayerMac/Source/SourceProbe.swift`
- Source validation. Phase 1 keeps the original source URL and does not remux:
  `AudioPlayerMac/AudioPlayerMac/Source/SourcePreparer.swift`

## Diagnostics

- Structured logging with per-launch log rotation:
  `AudioPlayerMac/AudioPlayerMac/Diagnostics/PlayerLogger.swift`
- Audio artifact detection (pops, clicks, silence gaps):
  `AudioPlayerMac/AudioPlayerMac/Diagnostics/AudioArtifactMonitor.swift`
- Diagnostic report builder for troubleshooting:
  `AudioPlayerMac/AudioPlayerMac/Diagnostics/DiagnosticReportBuilder.swift`

## UI

- Main application window:
  `AudioPlayerMac/AudioPlayerMac/UI/MainWindow.swift`
- Player transport controls (play/pause/stop/seek/volume):
  `AudioPlayerMac/AudioPlayerMac/UI/PlayerControlsView.swift`

## FFmpeg bridge

- C header for FFmpeg libav function declarations:
  `AudioPlayerMac/AudioPlayerMac/FFmpegBridge.h`
- C implementation bridging Swift to FFmpeg libav:
  `AudioPlayerMac/AudioPlayerMac/FFmpegBridge.c`
- Swift bridging header:
  `AudioPlayerMac/AudioPlayerMac/AudioPlayerMac-Bridging-Header.h`

## Build

- FFmpeg audio-core build script (arm64/x86_64 universal):
  `scripts/build-ffmpeg-audio-core.sh`

## Tests

- Unit tests:
  `AudioPlayerMac/Tests/AudioPlayerMacTests.swift`

## Playback pipeline data flow

Current Phase 1 path:

```
File on disk
    │
    ▼
PlaybackCoordinator
    │
    ▼
SourcePreparer ──► validate file, keep original URL
    │
    ▼
DecoderRouter ──► select backend
    │
    ├────────────────────────────┐
    ▼                            ▼
NativeFilePlayerBackend      PCMEngineBackend
(AVPlayer, compressed        (AVAudioEngine,
 source preserved)            WAV/PCM file scheduling)
    │                            │
    └──────────────┬─────────────┘
                   ▼
             System audio output
```

Legacy/deferred decoder components still exist for future fallback work, but
Phase 1 ordinary playback does not route through FFmpeg, `AVAudioFile` PCM
decoding for EAC3/JOC, MKV remux, TrueHD/MLP, `PcmStreamBuffer`, or Dolby
downmix.

Historical full-pipeline reference for deferred decoder/downmix work:

```
File on disk
    │
    ▼
SourceProbe ──► format detection, metadata extraction
    │
    ▼
SourcePreparer ──► cache/remux if needed
    │
    ▼
DecoderRouter ──► select AVFoundation or FFmpeg decoder
    │
    ├──────────────────────┐
    ▼                      ▼
AVFoundationDecoder    FFmpegDecoder ──► FFmpegWrapper (C bridge)
    │                      │
    ▼                      ▼
PcmStreamBuffer ◄──── decoded PCM frames
    │
    ▼
DolbyDownmixProcessor ──► LoRo/LtRt matrix downmix (if multichannel)
    │
    ▼
VolumeController ──► gain/fade applied
    │
    ▼
AudioEngine ──► AVAudioEngine output node
    │
    ▼
OutputDeviceManager ──► selected audio device
    │
    ▼
Physical speakers / AirPods (spatial audio)
```

Diagnostics run in parallel:

- `PlayerLogger` captures structured events at each stage
- `AudioArtifactMonitor` analyzes PCM buffers for pops/clicks/silence
- `DiagnosticReportBuilder` aggregates logs and artifact data into reports
