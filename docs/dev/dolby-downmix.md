# Dolby Downmix Algorithm

## Overview

The Dolby downmix processor converts multichannel Dolby audio (5.1, 7.1, etc.) to stereo output. It supports three modes: LoRo, LtRt, and Dolby Pro Logic II.

## Playback path requirements

The Dolby downmix processor operates on decoded PCM data. It is only usable on
playback paths where the application owns the PCM buffer:

| Backend | PCM access | Downmix available |
|---------|------------|-------------------|
| NativeFilePlayer (AVPlayer) | No | No -- system handles all output mixing |
| PCMEngine (AVAudioEngine) | Yes | Yes |
| FFmpegDecoder | Yes | Yes (once connected) |

**Current state:** The `DolbyDownmixProcessor` is implemented but not wired
into any active playback path. It will be activated when:
- A PCM-based decoder path is available for compressed formats (future
  "PCM everywhere" mode), or
- The FFmpeg decoder is connected for TrueHD (multichannel PCM output).

For EAC3/AC3 played through AVPlayer, the system handles downmix internally.
The application cannot intervene.

See `architecture.md` for the hybrid strategy rationale.

## Downmix types

| Type | Description | Use case |
|------|-------------|----------|
| **LoRo** | Line out, Reference out | Simple stereo downmix |
| **LtRt** | Left total, Right total | Surround-encoded stereo |
| **DplII** | Dolby Pro Logic II | Enhanced surround decoding |

## Matrix coefficients

### Default coefficients

| Parameter | Value | Description |
|-----------|-------|-------------|
| `centerMixLevel` | 0.707 (-3dB) | Center channel mix level |
| `centerMixLevelLtRt` | 0.707 (-3dB) | Center channel mix level for LtRt |
| `surroundMixLevel` | 0.707 (-3dB) | Surround channel mix level |
| `surroundMixLevelLtRt` | 0.707 (-3dB) | Surround channel mix level for LtRt |
| `lfeMixLevel` | 0.0 (-inf dB) | LFE channel mix level (usually muted) |

### Dolby standard coefficients

According to Dolby specifications:

| Parameter | LoRo | LtRt/DplII |
|-----------|------|------------|
| Center | -3dB (0.707) | -3dB (0.707) |
| Surround | -3dB (0.707) | -3dB (0.707) |
| LFE | -inf (0.0) | -inf (0.0) |

## Channel layout

### 5.1 channel layout

```
Channel 0: L (Left)
Channel 1: R (Right)
Channel 2: C (Center)
Channel 3: LFE (Low Frequency Effects)
Channel 4: Ls (Left Surround)
Channel 5: Rs (Right Surround)
```

### 7.1 channel layout

```
Channel 0: L (Left)
Channel 1: R (Right)
Channel 2: C (Center)
Channel 3: LFE (Low Frequency Effects)
Channel 4: Ls (Left Surround)
Channel 5: Rs (Right Surround)
Channel 6: Lb (Left Back)
Channel 7: Rb (Right Back)
```

## Downmix formulas

### LoRo mode (simple stereo)

```
outL = L + cmix * C + lfeMix * LFE + smix * Ls + smix * Lb
outR = R + cmix * C + lfeMix * LFE + smix * Rs + smix * Rb
```

### LtRt/DplII mode (surround-encoded stereo)

```
outL = L + cmix * C + lfeMix * LFE + smix * Ls - smix * Rs + smix * Lb - smix * Rb
outR = R + cmix * C + lfeMix * LFE - smix * Ls + smix * Rs - smix * Lb + smix * Rb
```

The LtRt mode uses phase inversion to encode surround information, which can be decoded by Dolby Pro Logic decoders.

## Implementation

### Swift implementation

```swift
// AudioPlayerMac/Decoders/Common/DolbyDownmixProcessor.swift

import Foundation

enum DolbyDownmixType {
    case none
    case loRo    // Line out, Reference out
    case ltRt    // Left total, Right total
    case dplII   // Dolby Pro Logic II
}

struct DolbyDownmixParams {
    var type: DolbyDownmixType = .none
    var centerMixLevel: Double = 0.707      // -3dB
    var centerMixLevelLtRt: Double = 0.707
    var surroundMixLevel: Double = 0.707
    var surroundMixLevelLtRt: Double = 0.707
    var lfeMixLevel: Double = 0.0
}

class DolbyDownmixProcessor {
    private var params: DolbyDownmixParams = DolbyDownmixParams()
    private var inputChannelCount: Int = 0
    private var outputChannelCount: Int = 0
    private var active: Bool = false
    
    private var cmix: Float = 0.707
    private var smix: Float = 0.707
    private var lfeMix: Float = 0.0
    private var preferLtRt: Bool = false
    
    /// Configure the downmix processor
    /// - Parameters:
    ///   - params: Downmix parameters
    ///   - inputChannelCount: Number of input channels (must be >= 3)
    ///   - outputChannelCount: Number of output channels (must be 2)
    /// - Returns: true if configuration succeeded
    func configure(params: DolbyDownmixParams,
                   inputChannelCount: Int,
                   outputChannelCount: Int) -> Bool {
        self.params = params
        self.inputChannelCount = inputChannelCount
        self.outputChannelCount = outputChannelCount
        self.active = false
        
        guard params.type != .none else { return false }
        guard outputChannelCount == 2 else { return false }
        guard inputChannelCount >= 3 else { return false }
        
        cmix = (params.type == .ltRt || params.type == .dplII)
            ? Float(params.centerMixLevelLtRt)
            : Float(params.centerMixLevel)
        smix = (params.type == .ltRt || params.type == .dplII)
            ? Float(params.surroundMixLevelLtRt)
            : Float(params.surroundMixLevel)
        lfeMix = Float(params.lfeMixLevel)
        preferLtRt = (params.type == .ltRt || params.type == .dplII)
        
        active = true
        return true
    }
    
    func isActive() -> Bool { return active }
    func getInputChannelCount() -> Int { return inputChannelCount }
    func getOutputChannelCount() -> Int { return outputChannelCount }
    
    /// Process interleaved Float32 PCM data
    /// - Parameters:
    ///   - inputInterleaved: Input buffer (interleaved multichannel)
    ///   - outputInterleaved: Output buffer (interleaved stereo)
    ///   - frameCount: Number of frames to process
    func processFloat32(inputInterleaved: UnsafePointer<Float>,
                        outputInterleaved: UnsafeMutablePointer<Float>,
                        frameCount: Int) {
        guard active else { return }
        
        let inCh = inputChannelCount
        let outCh = outputChannelCount
        
        for i in 0..<frameCount {
            let inPtr = inputInterleaved.advanced(by: i * inCh)
            let outPtr = outputInterleaved.advanced(by: i * outCh)
            processFrameFloat32(in: inPtr, out: outPtr)
        }
    }
    
    /// Process planar Float32 PCM data
    /// - Parameters:
    ///   - inputPlanes: Array of input channel pointers
    ///   - outputPlanes: Array of output channel pointers
    ///   - frameCount: Number of frames to process
    func processFloat32Planar(inputPlanes: [UnsafePointer<Float>],
                              outputPlanes: [UnsafeMutablePointer<Float>],
                              frameCount: Int) {
        guard active else { return }
        
        let ch = inputChannelCount
        
        for i in 0..<frameCount {
            let L = inputPlanes[0][i]
            let R = inputPlanes[1][i]
            let C = (ch > 2) ? inputPlanes[2][i] : 0.0
            let LFE = (ch > 3) ? inputPlanes[3][i] : 0.0
            let Ls = (ch > 4) ? inputPlanes[4][i] : 0.0
            let Rs = (ch > 5) ? inputPlanes[5][i] : 0.0
            let Lb = (ch > 6) ? inputPlanes[6][i] : 0.0
            let Rb = (ch > 7) ? inputPlanes[7][i] : 0.0
            
            var outL = L + cmix * C + lfeMix * LFE
            var outR = R + cmix * C + lfeMix * LFE
            
            if preferLtRt {
                outL += smix * Ls - smix * Rs + smix * Lb - smix * Rb
                outR += -smix * Ls + smix * Rs - smix * Lb + smix * Rb
            } else {
                outL += smix * Ls + smix * Lb
                outR += smix * Rs + smix * Rb
            }
            
            outputPlanes[0][i] = outL
            outputPlanes[1][i] = outR
        }
    }
    
    private func processFrameFloat32(in: UnsafePointer<Float>,
                                     out: UnsafeMutablePointer<Float>) {
        let ch = inputChannelCount
        
        let L = in[0]
        let R = in[1]
        let C = (ch > 2) ? in[2] : 0.0
        let LFE = (ch > 3) ? in[3] : 0.0
        let Ls = (ch > 4) ? in[4] : 0.0
        let Rs = (ch > 5) ? in[5] : 0.0
        let Lb = (ch > 6) ? in[6] : 0.0
        let Rb = (ch > 7) ? in[7] : 0.0
        
        var outL = L + cmix * C + lfeMix * LFE
        var outR = R + cmix * C + lfeMix * LFE
        
        if preferLtRt {
            outL += smix * Ls - smix * Rs + smix * Lb - smix * Rb
            outR += -smix * Ls + smix * Rs - smix * Lb + smix * Rb
        } else {
            outL += smix * Ls + smix * Lb
            outR += smix * Rs + smix * Rb
        }
        
        out[0] = outL
        out[1] = outR
    }
}
```

## Usage example

```swift
// Create processor
let processor = DolbyDownmixProcessor()

// Configure for 5.1 to stereo downmix
var params = DolbyDownmixParams()
params.type = .ltRt
params.centerMixLevel = 0.707
params.surroundMixLevel = 0.707
params.lfeMixLevel = 0.0

let success = processor.configure(
    params: params,
    inputChannelCount: 6,
    outputChannelCount: 2
)

// Process audio
if success {
    var inputData: [Float] = [...] // 5.1 interleaved PCM
    var outputData: [Float] = [Float](repeating: 0, count: frameCount * 2)
    
    inputData.withUnsafeBufferPointer { inPtr in
        outputData.withUnsafeMutableBufferPointer { outPtr in
            processor.processFloat32(
                inputInterleaved: inPtr.baseAddress!,
                outputInterleaved: outPtr.baseAddress!,
                frameCount: frameCount
            )
        }
    }
}
```

## Dolby metadata extraction

FFmpeg can extract Dolby downmix metadata from EAC3 streams:

```c
// In FFmpegBridge.c
AVFrameSideData *sd = av_frame_get_side_data(frame, AV_FRAME_DATA_DOWNMIX_INFO);
if (sd) {
    AVDownmixInfo *info = (AVDownmixInfo *)sd->data;
    // Extract preferred_downmix_type, center_mix_level, etc.
}
```

## Testing

### Test cases

1. **5.1 LoRo downmix**: Verify simple stereo output
2. **5.1 LtRt downmix**: Verify surround-encoded stereo
3. **7.1 to stereo**: Verify back channel handling
4. **LFE handling**: Verify LFE is muted by default
5. **Center channel**: Verify center channel is mixed at -3dB

### Test files

- 5.1 EAC3 test file
- 7.1 TrueHD test file
- 5.1 FLAC test file

## References

- Dolby Digital Professional Encoder Manual
- Dolby Pro Logic II Decoder Specification
- FFmpeg AV_FRAME_DATA_DOWNMIX_INFO documentation

## See also

- Decoder path selection rules: `docs/dev/decoder-paths.md`
- Architecture overview: `docs/dev/architecture.md`
