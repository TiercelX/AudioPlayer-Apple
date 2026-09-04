# Output Format Control (macOS vs Windows)

## Overview

This document describes the differences in audio output format control between macOS (CoreAudio) and Windows (WASAPI), and what can be achieved on each platform.

## Architecture comparison

### Windows WASAPI

```
┌─────────────────────────────────────────────────────────┐
│                    Application                          │
│              WASAPI Exclusive Mode                      │
│              - Set exact sample rate                    │
│              - Set exact bit depth                      │
│              - Set exact channel count                  │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    WASAPI Shared Mode                    │
│              - Negotiate with system mixer               │
│              - System resamples if needed                │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    Audio Hardware                        │
└─────────────────────────────────────────────────────────┘
```

### macOS CoreAudio

```
┌─────────────────────────────────────────────────────────┐
│                    Application                          │
│              AVAudioEngine                              │
│              - Request format                            │
│              - System negotiates                         │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    CoreAudio HAL                         │
│              - Set device sample rate (if supported)     │
│              - Bit depth determined by hardware          │
│              - No exclusive mode                         │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    Audio Hardware                        │
└─────────────────────────────────────────────────────────┘
```

## Feature comparison

| Feature | Windows WASAPI | macOS CoreAudio | Notes |
|---------|----------------|-----------------|-------|
| **Exclusive mode** | ✅ Supported | ❌ Not available | WASAPI exclusive bypasses system mixer |
| **Set sample rate** | ✅ Exclusive mode | ✅ CoreAudio HAL | Both can set sample rate |
| **Set bit depth** | ✅ Exclusive mode | ⚠️ Limited | CoreAudio bit depth determined by hardware |
| **Set channel count** | ✅ Exclusive mode | ✅ CoreAudio | Both can set channel count |
| **Format negotiation** | ✅ Shared mode | ✅ CoreAudio | Both support format negotiation |
| **Device capabilities** | ✅ Enumerate | ✅ Enumerate | Both can query device capabilities |

## macOS CoreAudio capabilities

### What CAN be controlled

1. **Sample rate**
   - Can set device nominal sample rate via CoreAudio HAL
   - Device must support the requested rate
   - Example: Set to 48kHz, 96kHz, etc.

2. **Channel count**
   - Can configure output channel count
   - Device must support the requested count
   - Example: Stereo, 5.1, 7.1

3. **Format selection**
   - Can query supported formats
   - Can select best matching format
   - System handles resampling if needed

### What CANNOT be controlled

1. **Bit depth**
   - Determined by hardware and driver
   - Application cannot force specific bit depth
   - Example: Cannot force 24-bit output on 16-bit hardware

2. **Exclusive mode**
   - No WASAPI-style exclusive mode
   - Always goes through system mixer
   - Cannot bypass system audio processing

3. **Hardware-level format**
   - Final output format determined by hardware
   - Application can only request, not force

## Implementation guide

### Query device capabilities

```swift
// AudioPlayerMac/Core/OutputDeviceManager.swift

import CoreAudio

class OutputDeviceManager {
    
    /// Get supported sample rates for a device
    func getSupportedSampleRates(deviceID: AudioDeviceID) -> [Float64] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize
        )
        
        guard status == noErr else { return [] }
        
        let count = Int(dataSize) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        
        AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &ranges
        )
        
        // Extract unique sample rates
        var rates = Set<Float64>()
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                rates.insert(range.mMinimum)
            } else {
                // Range - collect common rates
                for rate in [44100.0, 48000.0, 88200.0, 96000.0, 176400.0, 192000.0] {
                    if rate >= range.mMinimum && rate <= range.mMaximum {
                        rates.insert(rate)
                    }
                }
            }
        }
        
        return Array(rates).sorted()
    }
    
    /// Get current sample rate
    func getCurrentSampleRate(deviceID: AudioDeviceID) -> Float64 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var sampleRate: Float64 = 0
        var dataSize = UInt32(MemoryLayout<Float64>.size)
        
        AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &sampleRate
        )
        
        return sampleRate
    }
    
    /// Set sample rate
    func setSampleRate(deviceID: AudioDeviceID, sampleRate: Float64) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var rate = sampleRate
        let status = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            UInt32(MemoryLayout<Float64>.size),
            &rate
        )
        
        return status == noErr
    }
    
    /// Get supported stream formats
    func getSupportedFormats(deviceID: AudioDeviceID) -> [AudioStreamBasicDescription] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormats,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize
        )
        
        guard status == noErr else { return [] }
        
        let count = Int(dataSize) / MemoryLayout<AudioStreamBasicDescription>.size
        var formats = [AudioStreamBasicDescription](repeating: AudioStreamBasicDescription(), count: count)
        
        AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &formats
        )
        
        return formats
    }
    
    /// Get current output format
    func getCurrentFormat(deviceID: AudioDeviceID) -> AudioStreamBasicDescription? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var format = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0, nil,
            &dataSize,
            &format
        )
        
        return status == noErr ? format : nil
    }
}
```

### Format negotiation

```swift
// AudioPlayerMac/Core/AudioEngine.swift

import AVFoundation

extension AudioEngine {
    
    /// Negotiate output format with device
    func negotiateOutputFormat(desiredFormat: AVAudioFormat) -> AVAudioFormat {
        guard let deviceID = getCurrentOutputDeviceID() else {
            return desiredFormat
        }
        
        let deviceManager = OutputDeviceManager()
        
        // Get device capabilities
        let supportedRates = deviceManager.getSupportedSampleRates(deviceID: deviceID)
        let currentRate = deviceManager.getCurrentSampleRate(deviceID: deviceID)
        
        // Check if desired sample rate is supported
        let targetRate: Float64
        if supportedRates.contains(desiredFormat.sampleRate) {
            targetRate = desiredFormat.sampleRate
        } else {
            // Find closest supported rate
            targetRate = supportedRates.min(by: { abs($0 - desiredFormat.sampleRate) < abs($1 - desiredFormat.sampleRate) }) ?? currentRate
        }
        
        // Set device sample rate if different
        if targetRate != currentRate {
            _ = deviceManager.setSampleRate(deviceID: deviceID, sampleRate: targetRate)
        }
        
        // Create output format
        // Note: Bit depth is determined by hardware, we can only request
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,  // Always use Float32 internally
            sampleRate: targetRate,
            channels: AVAudioChannelCount(desiredFormat.channelCount),
            interleaved: false
        ) ?? desiredFormat
        
        return outputFormat
    }
    
    private func getCurrentOutputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceID
        )
        
        return status == noErr ? deviceID : nil
    }
}
```

## Windows WASAPI comparison

### Exclusive mode capabilities

```cpp
// Windows WASAPI exclusive mode (for reference)
// This is NOT available on macOS

// In exclusive mode, you can:
// 1. Set exact sample rate
// 2. Set exact bit depth
// 3. Set exact channel count
// 4. Bypass system mixer

// macOS equivalent: None - always goes through system mixer
```

### What Windows can do that macOS cannot

| Feature | Windows | macOS |
|---------|---------|-------|
| Force 24-bit output | ✅ Exclusive mode | ❌ Hardware dependent |
| Force 16-bit output | ✅ Exclusive mode | ❌ Hardware dependent |
| Bypass system mixer | ✅ Exclusive mode | ❌ Not available |
| Force exact format | ✅ Exclusive mode | ❌ Negotiate only |

## Practical implications

### For AudioPlayerMac

1. **Sample rate control**: ✅ Can set device sample rate
2. **Bit depth control**: ❌ Cannot force, hardware dependent
3. **Format negotiation**: ✅ Can negotiate with device
4. **Display current format**: ✅ Can query device format

### User experience

- User can select preferred sample rate in settings
- Application will set device to that rate if supported
- Bit depth is automatic (hardware decides)
- Current output format displayed in UI

## Implementation in Phase 1

### Tasks to add

1. **OutputDeviceManager implementation**
   - Query device capabilities
   - Set sample rate
   - Get current format

2. **Settings UI**
   - Sample rate selection
   - Display current output format
   - Show device capabilities

3. **AudioEngine integration**
   - Negotiate output format
   - Apply user preferences
   - Handle format changes

## References

- Apple Developer Documentation: Core Audio
- Apple Developer Documentation: Audio Object Properties
- Windows WASAPI Documentation (for comparison)

## See also

- Architecture overview: `docs/dev/architecture.md`
- Spatial audio: `docs/dev/spatial-audio.md`
