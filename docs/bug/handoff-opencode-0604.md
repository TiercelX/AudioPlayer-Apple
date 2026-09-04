# opencode-0604 Handoff: Audio Playback Bug

## Project
AudioPlayerMac — macOS audio player with Dolby Atmos support (Swift + AVFoundation + FFmpeg)

**Repo**: https://github.com/TiercelX/AudioPlayer-Apple (branch: `opencode-0604`)
**Reference project**: https://github.com/TiercelX/AudioPlayer (branch: `opencode-0528`) — Windows C++ + Qt

## Current State

The project compiles (`BUILD SUCCEEDED`) and tests pass (`TEST SUCCEEDED`). All pipeline components are integrated (downmix, artifact monitor, seek cache, volume fade). **But audio playback is broken** — no sound or garbled audio.

## The Bug

### Symptom
- User reports "声音变慢了" (audio slowed down), "放不出来声" (no sound), "进度条不动" (progress bar stuck)
- Logs show buffers are being scheduled at ~103ms intervals for 85ms buffers

### Root Cause (partially identified)
The playback pipeline has a fundamental scheduling problem. Read the full analysis below.

## Key Files

| File | Role |
|------|------|
| `AudioPlayerMac/Core/PlaybackController.swift` | Main playback orchestrator — **this is where the bug is** |
| `AudioPlayerMac/Core/AudioEngine.swift` | AVAudioEngine + AVAudioPlayerNode wrapper |
| `AudioPlayerMac/Decoders/Common/PcmStreamBuffer.swift` | Ring buffer (decoder writes, output reads) |
| `AudioPlayerMac/Decoders/AVFoundation/AVFoundationDecoder.swift` | AVAudioFile-based decoder |
| `AudioPlayerMac/Decoders/FFmpeg/FFmpegDecoder.swift` | FFmpeg libav decoder (for TrueHD/MLP) |

## What's Been Tried (and failed)

### Attempt 1: Timer-based output loop
```swift
outputTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
    outputTick()  // read 4096 frames from buffer, schedule to playerNode
}
```
**Problem**: Each buffer is 85ms (4096/48000), but timer fires every 20ms. Buffers pile up in playerNode queue, audio plays at ~4.3x slower speed.

### Attempt 2: Completion-handler-driven scheduling
```swift
audioEngine.play(buffer: pcmBuffer) {
    self.scheduleNextOutput()  // schedule next buffer when current finishes
}
```
**Problem**: Completion fires AFTER buffer finishes (85ms), then dispatches to main thread (+16ms), then next buffer is scheduled. Result: ~18ms silence gap between every buffer. Audio sounds choppy.

### Attempt 3: Pre-fill + completion handler (current code)
Wait until 200ms of data buffered, schedule 4 buffers at once, then use completion handler for replenishment.
**Problem**: Still not working correctly. The issue may be deeper.

## Deeper Investigation Needed

### 1. PcmStreamBuffer may be the problem
The `PcmStreamBuffer.read()` creates a NEW `AVAudioPCMBuffer` each time and copies data via `memcpy`. This is inefficient and may have issues:
- Creating a new buffer for every read is expensive
- The buffer format may not match what AVAudioPlayerNode expects

**Compare with Windows**: The Windows `PcmStreamBuffer` extends `QIODevice` — `QAudioSink` reads directly from the circular buffer. No copying, no new buffer creation.

### 2. Consider removing PcmStreamBuffer entirely
For AVFoundation decoder, `AVAudioFile.read(into:)` already returns properly formatted buffers. The PcmStreamBuffer intermediate layer may be unnecessary overhead. Consider:
- Decoder → directly schedule to playerNode (no intermediate buffer)
- Use playerNode's internal queue as the buffer (it handles scheduling naturally)

### 3. The Windows approach can't be directly ported
Windows uses `QAudioSink` (pull model — QAudioSink reads from QIODevice). macOS uses `AVAudioPlayerNode` (push model — you schedule buffers onto it). The paradigms are fundamentally different.

### 4. Reference project's Apple backend is a stub
The Windows reference project has `AppleNativeAudioPlayer` which returns `isSupportedForContext() = false`. There's no reference implementation for macOS audio output. You need to design this yourself based on AVAudioEngine/AVAudioPlayerNode best practices.

## Recommended Fix Approach

**Simplest correct implementation**: Skip PcmStreamBuffer for the output path. Use a timer or CADisplayLink to periodically check if playerNode needs more buffers, and schedule them directly from the decoder.

```swift
// Pseudocode for the simplest working approach:
func outputTick() {
    // Read directly from decoder, schedule to playerNode
    guard let buffer = try? decoder.decode() else { return }
    playerNode.scheduleBuffer(buffer)
    playerNode.play()  // no-op if already playing
}

// Use CADisplayLink (~60fps) or a 20ms timer
// Schedule when playerNode's queued buffer count < threshold
```

Or use AVAudioEngine's `tap` on the mixer node for a pull-model approach.

## Build & Test

```bash
# Build
cd AudioPlayerMac
xcodebuild -scheme AudioPlayerMac -configuration Debug build

# Test
xcodebuild -scheme AudioPlayerMac -configuration Debug test

# Run
open ~/Library/Developer/Xcode/DerivedData/AudioPlayerMac-*/Build/Products/Debug/AudioPlayerMac.app

# Logs
cat ~/Library/Application\ Support/AudioPlayerMac/logs/player-*.log | tail -30

# FFmpeg (if rebuild needed)
./scripts/build-ffmpeg-audio-core.sh --force
```

## Test Media Files
Located in `media/` (gitignored):
- `003-グランドエスケープ feat. 三浦透子.m4a` — ALAC 48kHz 2ch 16-bit
- `01 Inferno.flac` — FLAC
- `POWDER SNOW Live V9.8.6.eb3` — EAC3 raw
- `POWDER SNOW Live V9.8.6.mlp` — TrueHD/MLP raw

## Reference Project
The Windows project at `/tmp/AudioPlayer-ref/` (branch `opencode-0528`) has the working audio output implementation. Key files:
- `src/backends/ffmpeg/ffmpegaudioplayer.cpp` — dual-thread model, startup threshold, pumpOutput()
- `src/backends/ffmpeg/ffmpegpcmshared.h` — PcmStreamBuffer (QIODevice-based), FfmpegDecoderWorker
- `src/backends/wasapi/windowswasapiaudioplayer_worker.h` — WASAPI render worker (most sophisticated)

## Other Completed Work (don't redo)
- FFmpeg audio-core self-built (n8.1.1, universal static libs)
- DolbyDownmixProcessor integrated (multichannel → stereo)
- AudioArtifactMonitor integrated (real-time PCM analysis)
- PcmSeekCache integrated (FFmpegDecoder seek acceleration)
- VolumeController integrated (fade in/out)
- MediaInfoView (SwiftUI metadata popover)
- 19 unit tests (all passing)
- Smoke test script (`scripts/run-smoke-test.sh`)
- GitHub Actions CI (`.github/workflows/build.yml`)
- docs/dev/code-map.md, docs/bug/README.md, docs/dev/agent-workflow.md
- 31 Windows .ps1 scripts removed

## Git Config
If required by the local network, configure a proxy globally:
```
git config --global http.proxy http://<proxy-host>:<proxy-port>
git config --global https.proxy http://<proxy-host>:<proxy-port>
```
FFmpeg source is in `AudioPlayerMac/ffmpeg-audio-core/src/` (gitignored).
