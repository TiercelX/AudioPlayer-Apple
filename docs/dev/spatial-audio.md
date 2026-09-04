# Spatial Audio Integration

## Overview

AudioPlayerMac integrates with macOS spatial audio for immersive listening experiences with AirPods. The system handles spatial audio rendering automatically when playing multichannel audio.

## How spatial audio works on macOS

### System-level rendering

macOS automatically renders spatial audio for:
- EAC3-JOC (Dolby Atmos) content decoded by AVFoundation
- Multichannel PCM output (5.1, 7.1, etc.)
- AirPods Pro, AirPods Max, and compatible headphones

### Application role

The application's role depends on the playback path:

**NativeFilePlayer path (AVPlayer) -- used for EAC3-JOC/Atmos and most formats:**
- AVPlayer hands the compressed stream directly to the system decoder.
- The system decodes Atmos object metadata and renders spatial audio natively.
- AirPods head tracking and spatial audio work automatically.
- The application never sees decoded PCM; it controls play/pause/seek/volume only.

**PCMEngine path (AVAudioEngine) -- used for WAV and future FFmpeg output:**
- The application decodes audio to multichannel PCM (5.1, 7.1).
- Outputs via AVAudioEngine.
- System renders spatial audio from multichannel PCM.
- AirPods head tracking works, but Atmos object metadata is not available --
  only channel-based rendering (max 7.1).

> **Why not decode EAC3-JOC ourselves?** Decoding Atmos to PCM loses the
> object metadata. The result is 7.1 channel audio at best -- no height
> channels, no object positioning, no spatial rendering. For true Atmos
> playback, the system decoder (AVPlayer) is the only correct path.
> See `architecture.md` for the full hybrid strategy rationale.

## Why Atmos must use the system decoder

EAC3-JOC (Dolby Atmos) contains object-based audio metadata -- position,
size, trajectory of individual sound objects. This metadata is only meaningful
to a renderer that understands the Atmos object model.

**If we decode EAC3-JOC ourselves (FFmpeg or AVFoundation PCM path):**
- Object metadata is discarded.
- Output is 7.1 channel PCM at best (L, R, C, LFE, Ls, Rs, Lb, Rb).
- No height channels, no object positioning.
- AirPods spatial audio renders from fixed channels, not objects.

**If we let AVPlayer handle it (current NativeFilePlayerBackend):**
- System decoder preserves and renders Atmos object metadata.
- AirPods spatial audio uses true object-based rendering.
- Head tracking adjusts individual objects, not just the sound field.
- No PCM access for the application, but the tradeoff is worth it for Atmos.

**Recommendation:** Always route EAC3-JOC through AVPlayer (NativeFilePlayerBackend).
Never decode Atmos content to PCM unless the goal is channel-based playback only.

## Playback path and spatial audio

| Backend | Spatial audio | Atmos objects | Head tracking |
|---------|--------------|---------------|---------------|
| NativeFilePlayer (AVPlayer) | System renders | Preserved | Full object tracking |
| PCMEngine (AVAudioEngine) | System renders from channels | Lost (7.1 max) | Channel-based only |
| FFmpegDecoder (future) | System renders from channels | Lost (7.1 max) | Channel-based only |

## AVAudioEngine setup

### Basic setup

```swift
// AudioPlayerMac/Core/AudioEngine.swift

import AVFoundation

class AudioEngine {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var outputFormat: AVAudioFormat?
    
    init() {
        setupEngine()
    }
    
    private func setupEngine() {
        // Attach player node
        engine.attach(playerNode)
        
        // Get output format
        let mainMixer = engine.mainMixerNode
        let outputFormat = mainMixer.outputFormat(forBus: 0)
        
        // Connect player to main mixer
        engine.connect(playerNode, to: mainMixer, format: outputFormat)
        
        // Prepare engine
        engine.prepare()
    }
    
    func start() throws {
        try engine.start()
    }
    
    func stop() {
        engine.stop()
    }
    
    func play(buffer: AVAudioPCMBuffer) {
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        playerNode.play()
    }
    
    func pause() {
        playerNode.pause()
    }
    
    func resume() {
        playerNode.play()
    }
}
```

### Multichannel output

For spatial audio, output multichannel PCM when available:

```swift
func setupMultichannelOutput(channelCount: Int) {
    // Create multichannel format
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48000,
        channels: AVAudioChannelCount(channelCount),
        interleaved: false
    ) else { return }
    
    // Reconnect with multichannel format
    engine.disconnectNodeOutput(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: format)
}
```

## AirPods head tracking

### How head tracking works

1. AirPods Pro/Max have built-in accelerometers and gyroscopes
2. macOS receives head tracking data via CoreMotion
3. System adjusts spatial audio rendering based on head orientation
4. Application doesn't need to handle head tracking directly

### CMHeadphoneMotionManager (macOS 14+)

On macOS 14+, you can access head tracking data:

```swift
import CoreMotion

@available(macOS 14.0, *)
class HeadTrackingManager {
    private let motionManager = CMHeadphoneMotionManager()
    
    func startTracking() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let motion = motion else { return }
            
            // Get head orientation
            let yaw = motion.attitude.yaw
            let pitch = motion.attitude.pitch
            let roll = motion.attitude.roll
            
            // Use for custom spatial audio if needed
            self?.updateSpatialAudio(yaw: yaw, pitch: pitch, roll: roll)
        }
    }
    
    func stopTracking() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    private func updateSpatialAudio(yaw: Double, pitch: Double, roll: Double) {
        // Custom spatial audio processing if needed
        // Most apps don't need this - system handles it
    }
}
```

## Spatial audio modes

### Fixed head tracking (default)

- Sound field stays fixed relative to the device
- Turning head doesn't change sound direction
- Good for music listening

### Head tracking (optional)

- Sound field stays fixed in space
- Turning head changes sound direction
- Good for movies and games

## macOS version differences

| Feature | macOS 12-13 | macOS 14+ | macOS 26+ |
|---------|-------------|-----------|-----------|
| Basic spatial audio | ✅ | ✅ | ✅ |
| Head tracking data | ❌ | ✅ | ✅ |
| Enhanced rendering | ❌ | ✅ | ✅ |
| Liquid Glass UI | ❌ | ❌ | ✅ |

## Implementation

### SpatialAudioManager

```swift
// AudioPlayerMac/Decoders/AVFoundation/SpatialAudioManager.swift

import AVFoundation
import CoreMotion

class SpatialAudioManager {
    enum SpatialMode {
        case standard      // Basic spatial audio
        case headTracked   // Head tracking enabled
        case fixed         // Fixed sound field
    }
    
    private var mode: SpatialMode = .standard
    private var headTrackingAvailable: Bool = false
    private var motionManager: CMHeadphoneMotionManager?
    
    init() {
        checkAvailability()
    }
    
    private func checkAvailability() {
        // Check if head tracking is available (macOS 14+)
        if #available(macOS 14.0, *) {
            motionManager = CMHeadphoneMotionManager()
            headTrackingAvailable = motionManager?.isDeviceMotionAvailable ?? false
        }
    }
    
    func enableSpatialAudio(mode: SpatialMode) {
        self.mode = mode
        
        switch mode {
        case .standard:
            // System handles automatically
            break
            
        case .headTracked:
            if headTrackingAvailable {
                startHeadTracking()
            }
            
        case .fixed:
            // Disable head tracking
            stopHeadTracking()
        }
    }
    
    @available(macOS 14.0, *)
    private func startHeadTracking() {
        guard let manager = motionManager else { return }
        
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let motion = motion else { return }
            self?.handleHeadMotion(motion)
        }
    }
    
    private func stopHeadTracking() {
        if #available(macOS 14.0, *) {
            motionManager?.stopDeviceMotionUpdates()
        }
    }
    
    @available(macOS 14.0, *)
    private func handleHeadMotion(_ motion: CMDeviceMotion) {
        // System handles spatial audio rendering
        // This is only needed for custom spatial processing
    }
    
    func isSpatialAudioEnabled() -> Bool {
        // Check if spatial audio is active
        // This is handled by the system
        return true
    }
    
    func isHeadTrackingAvailable() -> Bool {
        return headTrackingAvailable
    }
}
```

### Integration with AudioEngine

```swift
class AudioEngine {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var spatialManager: SpatialAudioManager?
    
    init() {
        setupEngine()
        setupSpatialAudio()
    }
    
    private func setupSpatialAudio() {
        spatialManager = SpatialAudioManager()
        
        if #available(macOS 14.0, *) {
            spatialManager?.enableSpatialAudio(mode: .headTracked)
        } else {
            spatialManager?.enableSpatialAudio(mode: .standard)
        }
    }
    
    func play(buffer: AVAudioPCMBuffer) {
        // Check if buffer is multichannel (for spatial audio)
        let channelCount = buffer.format.channelCount
        if channelCount > 2 {
            // Multichannel - system will handle spatial rendering
            setupMultichannelOutput(channelCount: Int(channelCount))
        }
        
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        playerNode.play()
    }
}
```

## Dolby Atmos integration

### EAC3-JOC (Atmos) content

Atmos playback uses the `NativeFilePlayerBackend` (AVPlayer) path:

1. `DecoderRouter` detects EAC3 format and routes to `NativeFilePlayerBackend`.
2. AVPlayer hands the compressed EAC3-JOC stream to the system decoder.
3. System decodes Atmos object metadata and renders spatial audio.
4. AirPods spatial audio and head tracking work automatically.
5. Application controls play/pause/seek/volume via AVPlayer API.

The application never touches the decoded audio. This is intentional -- only
the system decoder can render Atmos objects.

### TrueHD content (future FFmpeg path)

TrueHD is decoded by FFmpeg to multichannel PCM (up to 7.1). This PCM output
goes through AVAudioEngine. The system can render spatial audio from
multichannel PCM, but Atmos object metadata is not available -- only
channel-based rendering.

## Testing

### Test cases

1. **Stereo content**: Should play normally
2. **5.1 content**: Should render spatial audio on AirPods
3. **7.1 content**: Should render spatial audio on AirPods
4. **Atmos content**: Should render full spatial audio
5. **Head tracking**: Should adjust sound field when moving head

### Test devices

- AirPods Pro (1st gen or later)
- AirPods Max
- AirPods (3rd gen or later)
- Beats Fit Pro
- Compatible Bluetooth headphones

### Test files

- Stereo FLAC file
- 5.1 EAC3 file
- 7.1 TrueHD file
- Atmos EAC3-JOC file

## Troubleshooting

### Spatial audio not working

1. Check if AirPods are connected
2. Check if spatial audio is enabled in System Settings
3. Check if content is multichannel
4. Check macOS version (head tracking requires macOS 14+)

### Head tracking not working

1. Check if AirPods support head tracking
2. Check if head tracking is enabled in System Settings
3. Check macOS version (requires macOS 14+)
4. Check if motion data is available

### Audio quality issues

1. Check output format (should be multichannel for spatial)
2. Check sample rate (48kHz recommended)
3. Check for audio artifacts
4. Check system audio settings

## References

- Apple Developer Documentation: AVAudioEngine
- Apple Developer Documentation: CMHeadphoneMotionManager
- Apple Developer Documentation: Spatial Audio
- WWDC23: Explore immersive sound design

## See also

- Audio output format: `docs/dev/output-format.md`
- Architecture overview: `docs/dev/architecture.md`
