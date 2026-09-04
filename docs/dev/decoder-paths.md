# Decoder Paths

## Overview

AudioPlayerMac routes each audio file through one of three playback backends
selected by `DecoderRouter`. The choice depends on the detected codec and the
file extension. See `architecture.md` for the hybrid strategy rationale.

## Routing table

| Format | Backend | Decoder | PCM access | Notes |
|--------|---------|---------|------------|-------|
| EAC3-JOC (Atmos) | NativeFilePlayer | AVPlayer (system) | No | Object metadata preserved; spatial audio works |
| EAC3 / AC3 | NativeFilePlayer | AVPlayer (system) | No | Hardware-accelerated |
| AAC | NativeFilePlayer | AVPlayer (system) | No | |
| ALAC | NativeFilePlayer | AVPlayer (system) | No | Apple Lossless |
| FLAC | NativeFilePlayer | AVPlayer (system) | No | |
| MP3 | NativeFilePlayer | AVPlayer (system) | No | |
| WAV | PCMEngine | AVAudioEngine | Yes | Direct PCM scheduling |
| TrueHD / MLP | FFmpeg (reserved) | FFmpeg libav | Yes | Not connected in Phase 1 |
| m4a, mp4, caf, aif, aiff | NativeFilePlayer | AVPlayer (system) | No | Extension-based fallback for unknown codec |

## Routing logic

Source: `Core/DecoderRouter.swift`

```swift
class DecoderRouter {
    private let detector = AudioFormatDetector()

    func selectBackend(for url: URL) throws -> PlaybackRoute {
        let format = detector.detect(url: url)
        let ext = url.pathExtension.lowercased()

        switch format {
        case .wav:
            return PlaybackRoute(format: format, extensionName: ext,
                                 backendKind: .pcmEngine,
                                 preservesCompressedSource: false)
        case .mp3, .aac, .alac, .flac, .ac3, .eac3:
            return PlaybackRoute(format: format, extensionName: ext,
                                 backendKind: .nativeFilePlayer,
                                 preservesCompressedSource: true)
        case .truehd, .mlp:
            throw PlaybackRoutingError.ffmpegFallbackReserved(format)
        case .unknown:
            if isLikelySystemPlayableExtension(ext) {
                return PlaybackRoute(format: format, extensionName: ext,
                                     backendKind: .nativeFilePlayer,
                                     preservesCompressedSource: true)
            }
            throw PlaybackRoutingError.unsupportedFormat(format, url)
        }
    }
}
```

### PlaybackRoute

```swift
struct PlaybackRoute {
    let format: AudioFormat
    let extensionName: String
    let backendKind: PlaybackBackendKind
    let preservesCompressedSource: Bool
}

enum PlaybackBackendKind: String {
    case nativeFilePlayer = "NativeFilePlayerBackend"
    case pcmEngine = "PCMEngineBackend"
    case ffmpegFallback = "FFmpegFallbackBackend"
    case unsupported = "Unsupported"
}
```

## Backend details

### NativeFilePlayerBackend

- Uses `AVPlayer` for playback.
- System handles decoding, output routing, and spatial audio rendering.
- No access to decoded PCM data.
- Best for: all compressed formats where system decoding is sufficient,
  especially EAC3-JOC (Atmos) where object metadata must be preserved.

### PCMEngineBackend

- Uses `AVAudioEngine` + `AVAudioPlayerNode` for playback.
- Schedules `AVAudioFile` segments directly.
- Full access to PCM data for metering, DSP, artifact detection.
- Seek requires restarting playback from the new position.
- Best for: WAV / uncompressed PCM.

### FFmpegDecoder (reserved)

- Uses FFmpeg libav via C bridge (`FFmpegBridge.h/.c`).
- Decodes to PCM via `FFmpegWrapper`, with `PcmSeekCache` for fast seeking.
- Not connected to `PlaybackCoordinator` in Phase 1.
- Best for: TrueHD and MLP (Apple does not support these codecs).

## Format detection

Source: `Decoders/Common/AudioFormatDetector.swift`

Detection is two-step:

1. **Extension-based** (fast path): eac3, eb3, ac3, alac, flac, wav, mp3,
   truehd, thd, mlp.
2. **AVAsset probe** (ambiguous extensions): reads `CMFormatDescription` from
   the first audio track and checks `mFormatID`. Falls back to `.aac` for
   m4a/aac extensions, `.unknown` otherwise.

## Decoders in the tree (not wired to Phase 1 path)

| File | Status |
|------|--------|
| `Decoders/AVFoundation/AVFoundationDecoder.swift` | Exists; rejects Dolby compressed formats |
| `Decoders/FFmpeg/FFmpegDecoder.swift` | Exists; reserved for TrueHD |
| `Decoders/FFmpeg/FFmpegWrapper.swift` | Exists; Swift wrapper around FFmpegBridge C |
| `Decoders/Common/DolbyDownmixProcessor.swift` | Exists; needs PCM path to activate |
| `Decoders/Common/PcmSeekCache.swift` | Exists; segment-based seek cache for FFmpeg |
| `Decoders/Common/PcmStreamBuffer.swift` | Exists; ring buffer for PCM streaming |

## See also

- Hybrid strategy rationale: `docs/dev/architecture.md`
- FFmpeg integration: `docs/dev/ffmpeg-integration.md`
- Dolby downmix: `docs/dev/dolby-downmix.md`
- Spatial audio: `docs/dev/spatial-audio.md`
- Audio output format: `docs/dev/output-format.md`
