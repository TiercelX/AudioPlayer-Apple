# AudioPlayerMac Architecture

## Project overview

AudioPlayerMac is a native macOS audio player with Dolby Atmos support. It uses AVFoundation for native decoding of common formats and FFmpeg libav for TrueHD and complex formats.

## Technical stack

| Component | Choice | Reason |
|-----------|--------|--------|
| Language | Swift 5.9+ | Modern, safe, performant |
| UI Framework | SwiftUI + AppKit | SwiftUI for layout, AppKit for complex controls |
| Audio Engine | AVAudioEngine | System-level spatial audio support |
| Native Decoder | AVFoundation | EAC3/AC3/AAC/FLAC/WAV/MP3 |
| FFmpeg Decoder | libav C library | TrueHD and complex formats |
| Build System | Xcode 15+ / SPM | Modern toolchain |

## Version strategy

| Version | Target | Features |
|---------|--------|----------|
| Minimum | macOS 12 Monterey | Core functionality |
| Recommended | macOS 14 Sonoma | Enhanced spatial audio |
| Progressive | macOS 26 Tahoe | Liquid Glass UI |

## Module overview

```
┌─────────────────────────────────────────────────────────────┐
│                         App Layer                           │
│  AudioPlayerMacApp.swift  │  AppState.swift                 │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                         UI Layer                            │
│  MainWindow  │  PlayerControls  │  OutputDeviceMenu         │
│  MediaInfo   │  Settings        │  WaveformView             │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                        Core Layer                           │
│  AudioEngine  │  PlaybackController  │  OutputDeviceManager │
│  DecoderRouter │ VolumeController                           │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                      Decoder Layer                          │
│  AVFoundationDecoder  │  FFmpegDecoder  │  DolbyDownmix     │
│  PcmSeekCache  │  PcmStreamBuffer  │  AudioFormatDetector  │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                      Source Layer                           │
│  SourceProbe  │  SourcePreparer  │  PlaybackPlan  │ MediaInfo│
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                    Diagnostics Layer                        │
│  AudioArtifactMonitor  │  PlayerLogger  │ DiagnosticReport  │
└─────────────────────────────────────────────────────────────┘
```

## Module responsibilities

### App Layer
- **AudioPlayerMacApp**: Application entry point, SwiftUI lifecycle
- **AppState**: Global state management, coordination between views

### UI Layer
- **MainWindow**: Main application window with player controls
- **PlayerControlsView**: Play/Pause/Stop/Seek controls
- **OutputDeviceMenu**: Audio output device selection
- **MediaInfoView**: Display media file information
- **SettingsView**: Application settings
- **WaveformView**: Audio level visualization

### Core Layer
- **AudioEngine**: AVAudioEngine wrapper, manages audio graph
- **PlaybackController**: Playback state machine (Stopped/Playing/Paused/Stopping)
- **OutputDeviceManager**: CoreAudio device enumeration and selection
- **DecoderRouter**: Routes files to appropriate decoder (AVFoundation or FFmpeg)
- **VolumeController**: Volume control with fade in/out

### Decoder Layer
- **AVFoundationDecoder**: Native decoding for EAC3/AC3/AAC/FLAC/WAV/MP3
- **FFmpegDecoder**: FFmpeg libav decoding for TrueHD and complex formats
- **DolbyDownmixProcessor**: Dolby LoRo/LtRt downmix algorithm
- **PcmSeekCache**: PCM data caching for seek operations
- **PcmStreamBuffer**: Ring buffer for PCM streaming
- **AudioFormatDetector**: Detect audio format from file

### Source Layer
- **SourceProbe**: Probe media file info using AVAsset/ffprobe
- **SourcePreparer**: Prepare files for playback (remux if needed)
- **PlaybackPlan**: Build playback plan (decoder selection, source mode)
- **MediaInfo**: Media file information structure

### Diagnostics Layer
- **AudioArtifactMonitor**: Detect audio artifacts (pops/clicks)
- **PlayerLogger**: Structured logging system

## Hybrid playback strategy

AudioPlayerMac uses a **hybrid playback architecture** that selects the
highest-fidelity path for each format rather than forcing all audio through a
single pipeline.

| Format family | Path | Why |
|---|---|---|
| EAC3-JOC / Atmos | `NativeFilePlayerBackend` (AVPlayer) | Only Apple's system decoder can render Atmos object metadata and drive AirPods spatial audio / head tracking. Decoding to PCM ourselves would lose object metadata and reduce to 7.1 channels. |
| EAC3 / AC3 / AAC / ALAC / FLAC / MP3 | `NativeFilePlayerBackend` (AVPlayer) | System decoding is hardware-accelerated and covers all common lossy/lossless codecs. |
| WAV / uncompressed PCM | `PCMEngineBackend` (AVAudioEngine) | Direct PCM scheduling with full access to sample data for metering, visualization, and future DSP. |
| TrueHD / MLP | `FFmpegDecoder` (FFmpeg libav) | Apple does not support TrueHD; FFmpeg is the only option. Output is multichannel PCM routed through AVAudioEngine. |
| Unknown but system-playable (m4a, mp4, caf, aif, aiff) | `NativeFilePlayerBackend` (AVPlayer) | Let the system try; if it fails, report unsupported. |

### When AVPlayer is the right choice

For lossy and lossless compressed formats the system decoder is the pragmatic
default:

- Hardware-accelerated decoding with zero maintenance cost.
- EAC3-JOC Atmos object rendering works out of the box.
- AirPods spatial audio and head tracking are handled at the OS level.

### When AVPlayer is not enough

AVPlayer is a black box -- the application never sees decoded PCM samples. This
makes it unsuitable for:

- Real-time level metering or waveform visualization.
- Custom DSP chains (EQ, Dolby downmix, crossfeed).
- Audio artifact detection (pops, clicks, silence gaps).
- Precise seek control or sample-accurate position reporting.

These features require an AVAudioEngine path where the application owns the
PCM buffer. Currently only the WAV / PCM backend uses this path. TrueHD will
also use it once the FFmpeg decoder is fully integrated.

### Future evolution

A "PCM everywhere" mode can be added later for formats where Apple's decoder
can produce PCM output via `AVAudioFile` / `ExtAudioFile`. This would route
decoded PCM through AVAudioEngine, enabling metering and DSP for all non-Atmos
content. Atmos content should always stay on the system rendering path to
preserve object metadata.
- **DiagnosticReportBuilder**: Generate JSON diagnostic reports

## Data flow

1. **User opens file**
   - UI sends URL to PlaybackController
   - PlaybackController calls SourceProbe to detect format

2. **Format detection**
   - SourceProbe uses AVAsset to detect format
   - For raw Dolby files, uses ffprobe for detailed info
   - Returns MediaInfo with format, codec, channels, sample rate

3. **Decoder selection**
   - DecoderRouter selects decoder based on format
   - EAC3/AC3/AAC/FLAC/WAV/MP3 → AVFoundationDecoder
   - TrueHD → FFmpegDecoder

4. **Decoding**
   - Decoder opens file and produces AVAudioPCMBuffer
   - Buffers stored in PcmStreamBuffer
   - DolbyDownmixProcessor applied if needed (multichannel → stereo)

5. **Audio output**
   - AudioEngine schedules buffers from PcmStreamBuffer
   - AVAudioPlayerNode plays buffers
   - System handles spatial audio rendering for AirPods

6. **Diagnostics**
   - AudioArtifactMonitor analyzes PCM data
   - PlayerLogger records events
   - DiagnosticReportBuilder generates reports

## Thread model

| Thread | Responsibility | Notes |
|--------|---------------|-------|
| Main thread | UI updates, user interactions | SwiftUI updates |
| Decoder thread | Format decoding, PCM production | Background thread |
| Audio thread | AVAudioEngine rendering | System-managed |

## Key protocols

```swift
// Decoder protocol
protocol AudioDecoder {
    func open(url: URL) throws
    func decode() throws -> AVAudioPCMBuffer?
    func seek(to positionMs: Int64) throws
    func close()
}

// Playback controller delegate
protocol PlaybackControllerDelegate {
    func playbackStateDidChange(_ state: PlaybackState)
    func positionDidChange(_ positionMs: Int64)
    func audioLevelsDidChange(left: Float, right: Float)
}

// Output device manager delegate
protocol OutputDeviceManagerDelegate {
    func outputDevicesDidChange(_ devices: [AudioDevice])
    func selectedDeviceDidChange(_ device: AudioDevice)
}
```

## State machines

### Playback state machine

```
                    ┌──────────────────────────────────────────┐
                    │                                          │
                    ▼                                          │
    ┌───────────┐  play()   ┌───────────┐  pause()  ┌───────────┐
    │  Stopped  │──────────→│  Playing  │──────────→│  Paused   │
    └───────────┘           └───────────┘           └───────────┘
          ▲                    │    │                    │
          │                    │    │                    │
          │  stop()完成        │    │         play()     │
          │                    │    │         (resume)   │
          │                    ▼    │                    │
          │              ┌───────────┐                   │
          │              │ Stopping  │───────────────────┘
          │              └───────────┘
          │                    │
          │                    │ decoder finished
          ▼                    ▼
          └────────────────────┘
```

## Error handling

| Error type | Handling | Recovery |
|------------|----------|----------|
| File not found | Show error dialog | User selects another file |
| Unsupported format | Show error dialog | User selects another file |
| Decoder error | Stop playback | User can retry |
| Output device error | Switch to default device | Automatic recovery |
| Memory warning | Clear caches | Automatic |

## Memory management

- **PcmSeekCache**: LRU cache with configurable size (64MB - 2GB)
- **PcmStreamBuffer**: Ring buffer, fixed size
- **Decoder buffers**: Released after decode
- **UI images**: Cached with NSCache

## Security considerations

- No network access required
- No user data collection
- Files accessed via security-scoped bookmarks
- Sandbox compatible

## Performance considerations

- Decoder runs on background thread
- UI updates throttled to 60fps
- Seek cache reduces decode time
- Lazy loading for large files

## See also

- Code navigation map: `docs/dev/code-map.md`
- Decoder path selection: `docs/dev/decoder-paths.md`
- FFmpeg integration: `docs/dev/ffmpeg-integration.md`
- Dolby downmix: `docs/dev/dolby-downmix.md`
