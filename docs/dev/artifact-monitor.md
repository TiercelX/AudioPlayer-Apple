# Audio Artifact Monitor

## Overview

The Audio Artifact Monitor detects audio anomalies (pops, clicks, crackles) in PCM data. It analyzes audio blocks for discontinuities, transient spikes, and other artifacts.

## Playback path requirements

The artifact monitor requires access to decoded PCM samples. This is only
available on playback paths that use AVAudioEngine or FFmpeg:

| Backend | PCM access | Artifact monitoring |
|---------|------------|---------------------|
| NativeFilePlayer (AVPlayer) | No | Not available -- system owns the audio pipeline |
| PCMEngine (AVAudioEngine) | Yes | Available |
| FFmpegDecoder | Yes | Available (once connected) |

For the current Phase 1 implementation, artifact monitoring can only run on
WAV playback (PCMEngineBackend). Once the FFmpeg decoder is connected for
TrueHD, monitoring will also work there. Formats played through AVPlayer
(EAC3, AC3, AAC, FLAC, MP3) cannot be monitored because the application
never sees the decoded PCM data.

See `architecture.md` for the hybrid strategy rationale.

## Detection types

| Detector | Description | Threshold |
|----------|-------------|-----------|
| **Transient Spike** | Single sample spike | Peak >= 0.68, neighbors <= 0.24 |
| **Short Burst** | Short burst of noise | Peak >= 0.45, RMS >= 0.10 |
| **Crackle Texture** | Multiple small discontinuities | Jump >= 0.24, count >= 4 |
| **Block Boundary** | Discontinuity at block boundary | Jump >= 0.45 |
| **Sample Jump** | Large jump between adjacent samples | Jump >= 0.68 |
| **Silence Hard Switch** | Sudden transition from silence | Peak >= 0.12, jump >= 0.14 |

## Thresholds

### Global thresholds

```swift
enum ArtifactThresholds {
    static let adjacentJumpThreshold: Double = 0.68
    static let boundaryJumpThreshold: Double = 0.45
    static let transientPeakThreshold: Double = 0.68
    static let transientNeighborThreshold: Double = 0.24
    static let silentPeakThreshold: Double = 0.003
    static let silentRmsThreshold: Double = 0.001
    static let hardSwitchOpeningPeakThreshold: Double = 0.12
    static let hardSwitchJumpThreshold: Double = 0.14
}
```

### Severity levels

| Severity | Criteria |
|----------|----------|
| **Critical** | Jump >= 1.50, or peak >= 0.65 with jump >= 0.85 |
| **High** | Jump >= 1.00, or peak >= 0.60 |
| **Medium** | Jump >= 0.68, or peak >= 0.45 |
| **Low** | Below medium thresholds |

## Detectors

### 1. Transient Spike Detector

Detects single-sample spikes that stand out from their neighbors.

**Algorithm**:
```
For each sample:
  if |current| >= 0.68 AND |previous| <= 0.24 AND |next| <= 0.24:
    → Transient spike detected
```

**Swift implementation**:

```swift
func detectTransientSpike(data: UnsafePointer<Float>,
                         frameCount: Int,
                         format: PcmStreamFormat) -> Double {
    var peak: Double = 0.0
    
    for i in 1..<(frameCount - 1) {
        let prev = Double(abs(data[i - 1]))
        let curr = Double(abs(data[i]))
        let next = Double(abs(data[i + 1]))
        
        if curr >= ArtifactThresholds.transientPeakThreshold &&
           prev <= ArtifactThresholds.transientNeighborThreshold &&
           next <= ArtifactThresholds.transientNeighborThreshold {
            peak = max(peak, curr)
        }
    }
    
    return peak
}
```

### 2. Short Burst Detector

Detects short bursts of noise (2ms window).

**Algorithm**:
```
For each 2ms window:
  Calculate peak and RMS
  if peak >= 0.45 AND RMS >= 0.10 AND ratioToBlockRms >= 2.0:
    → Short burst detected
```

**Swift implementation**:

```swift
struct BurstScanResult {
    let peak: Double
    let rms: Double
    let ratioToBlockRms: Double
}

func detectShortBurst(data: UnsafePointer<Float>,
                     frameCount: Int,
                     format: PcmStreamFormat,
                     blockRms: Double) -> BurstScanResult {
    let windowMs: Double = 2.0
    let windowSamples = Int(Double(format.sampleRate) * windowMs / 1000.0)
    let step = windowSamples / 2
    
    var maxPeak: Double = 0.0
    var maxRms: Double = 0.0
    
    for start in stride(from: 0, to: frameCount - windowSamples, by: step) {
        var sum: Double = 0.0
        var peak: Double = 0.0
        
        for i in start..<(start + windowSamples) {
            let sample = Double(abs(data[i]))
            sum += sample * sample
            peak = max(peak, sample)
        }
        
        let rms = sqrt(sum / Double(windowSamples))
        maxPeak = max(maxPeak, peak)
        maxRms = max(maxRms, rms)
    }
    
    let ratio = blockRms > 0 ? maxRms / blockRms : 0.0
    
    return BurstScanResult(peak: maxPeak, rms: maxRms, ratioToBlockRms: ratio)
}
```

### 3. Crackle Texture Detector

Detects multiple small discontinuities (crackling sound).

**Algorithm**:
```
For each 3ms window:
  Count jumps >= 0.24
  if jumpCount >= 4 AND averageJump >= 0.30:
    → Crackle detected
```

**Swift implementation**:

```swift
struct CrackleScanResult {
    let score: Double
    let averageJump: Double
    let maxJump: Double
    let jumpCount: Int
}

func detectCrackleTexture(data: UnsafePointer<Float>,
                         frameCount: Int,
                         format: PcmStreamFormat,
                         sensitiveContext: Bool) -> CrackleScanResult {
    let windowMs: Double = 3.0
    let windowSamples = Int(Double(format.sampleRate) * windowMs / 1000.0)
    let step = windowSamples / 2
    
    let jumpThreshold = sensitiveContext ? 0.10 : 0.24
    let avgJumpThreshold = sensitiveContext ? 0.14 : 0.30
    let minJumpCount = max(4, format.channelCount * 3)
    
    var totalJumps: Int = 0
    var sumJumps: Double = 0.0
    var maxJump: Double = 0.0
    
    for start in stride(from: 0, to: frameCount - windowSamples, by: step) {
        for i in (start + 1)..<(start + windowSamples) {
            let jump = Double(abs(data[i] - data[i - 1]))
            if jump >= jumpThreshold {
                totalJumps += 1
                sumJumps += jump
                maxJump = max(maxJump, jump)
            }
        }
    }
    
    let averageJump = totalJumps > 0 ? sumJumps / Double(totalJumps) : 0.0
    let score = averageJump * sqrt(Double(totalJumps))
    
    return CrackleScanResult(
        score: score,
        averageJump: averageJump,
        maxJump: maxJump,
        jumpCount: totalJumps
    )
}
```

### 4. Block Boundary Detector

Detects discontinuities at block boundaries.

**Algorithm**:
```
Compare last sample of previous block with first sample of current block:
  if maxJump >= 0.45:
    → Boundary discontinuity detected
```

**Swift implementation**:

```swift
func detectBlockBoundary(previousBlock: [Float],
                        currentBlock: [Float],
                        channelCount: Int) -> Double {
    guard !previousBlock.isEmpty && !currentBlock.isEmpty else {
        return 0.0
    }
    
    var maxJump: Double = 0.0
    
    for ch in 0..<channelCount {
        let prev = Double(previousBlock[previousBlock.count - channelCount + ch])
        let curr = Double(currentBlock[ch])
        let jump = abs(curr - prev)
        maxJump = max(maxJump, jump)
    }
    
    return maxJump
}
```

### 5. Sample Jump Detector

Detects large jumps between adjacent samples within a block.

**Algorithm**:
```
For each adjacent pair:
  if |current - previous| >= 0.68:
    → Sample jump detected
```

**Swift implementation**:

```swift
func detectSampleJump(data: UnsafePointer<Float>,
                     frameCount: Int,
                     format: PcmStreamFormat) -> Double {
    var maxJump: Double = 0.0
    
    for i in 1..<frameCount {
        let jump = Double(abs(data[i] - data[i - 1]))
        maxJump = max(maxJump, jump)
    }
    
    return maxJump
}
```

### 6. Silence Hard Switch Detector

Detects sudden transitions from silence.

**Algorithm**:
```
if previousBlockIsSilent AND currentBlockOpeningPeak >= 0.12 AND boundaryJump >= 0.14:
  → Silence hard switch detected
```

**Swift implementation**:

```swift
func detectSilenceHardSwitch(previousBlockSilent: Bool,
                            currentBlock: [Float],
                            boundaryJump: Double) -> Bool {
    guard previousBlockSilent else { return false }
    
    let openingPeak = Double(abs(currentBlock[0]))
    
    return openingPeak >= ArtifactThresholds.hardSwitchOpeningPeakThreshold &&
           boundaryJump >= ArtifactThresholds.hardSwitchJumpThreshold
}
```

## Complete implementation

```swift
// AudioPlayerMac/Diagnostics/AudioArtifactMonitor.swift

import Foundation

class AudioArtifactMonitor {
    struct PlaybackContext {
        let sessionId: Int
        let source: String
        let playbackState: String
        let recentControlEvent: String
        let positionMs: Int64
        let audioLevelLeft: Float
        let audioLevelRight: Float
        let recoveryPending: Bool
        let recoveryAttempt: Int
    }
    
    struct RenderContext {
        let warmup: Bool
        let silenceFill: Bool
        let recovery: Bool
        let firstDataBlockAfterConfigure: Bool
        let firstDataBlockAfterDeviceRebuild: Bool
    }
    
    // Thresholds
    private let adjacentJumpThreshold: Double = 0.68
    private let boundaryJumpThreshold: Double = 0.45
    private let transientPeakThreshold: Double = 0.68
    private let transientNeighborThreshold: Double = 0.24
    private let silentPeakThreshold: Double = 0.003
    private let silentRmsThreshold: Double = 0.001
    private let hardSwitchOpeningPeakThreshold: Double = 0.12
    private let hardSwitchJumpThreshold: Double = 0.14
    
    // State
    private var previousSamples: [Float] = []
    private var previousBlockSilent: Bool = true
    private var hasPreviousBlock: Bool = false
    private var artifactCountTotal: UInt64 = 0
    private var artifactCountByType: [String: UInt64] = [:]
    private var recentArtifactTimesMs: [Int64] = []
    
    /// Analyze a block of PCM data for artifacts
    func analyzePcmBlock(data: UnsafePointer<Float>,
                        byteCount: Int,
                        format: PcmStreamFormat,
                        context: PlaybackContext,
                        renderSource: String,
                        renderContext: RenderContext) {
        let frameCount = byteCount / (format.channelCount * format.bitsPerSample / 8)
        
        // Calculate block metrics
        let metrics = calculateBlockMetrics(data: data, frameCount: frameCount, format: format)
        
        // Check if block is silent
        let isSilent = isSilentBlock(metrics: metrics)
        
        // Run detectors
        var artifacts: [(String, Double)] = []
        
        // 1. Transient spike
        let transientPeak = detectTransientSpike(data: data, frameCount: frameCount, format: format)
        if transientPeak > 0 {
            artifacts.append(("TransientSpike", transientPeak))
        }
        
        // 2. Short burst
        let burstResult = detectShortBurst(data: data, frameCount: frameCount, format: format, blockRms: metrics.rms)
        let burstThreshold = sensitiveContext(renderContext: renderContext) ? 0.10 : 0.45
        if burstResult.peak >= burstThreshold {
            artifacts.append(("ShortBurst", burstResult.peak))
        }
        
        // 3. Crackle texture
        let crackleResult = detectCrackleTexture(data: data, frameCount: frameCount, format: format, sensitiveContext: sensitiveContext(renderContext: renderContext))
        if crackleResult.jumpCount >= 4 {
            artifacts.append(("CrackleTexture", crackleResult.maxJump))
        }
        
        // 4. Block boundary
        if hasPreviousBlock {
            let boundaryJump = detectBlockBoundary(previousBlock: previousSamples, currentBlock: Array(UnsafeBufferPointer(start: data, count: frameCount)), channelCount: format.channelCount)
            if boundaryJump >= boundaryJumpThreshold {
                artifacts.append(("BlockBoundary", boundaryJump))
            }
            
            // 5. Silence hard switch
            if detectSilenceHardSwitch(previousBlockSilent: previousBlockSilent, currentBlock: Array(UnsafeBufferPointer(start: data, count: frameCount)), boundaryJump: boundaryJump) {
                artifacts.append(("SilenceHardSwitch", boundaryJump))
            }
        }
        
        // 6. Sample jump
        let sampleJump = detectSampleJump(data: data, frameCount: frameCount, format: format)
        if sampleJump >= adjacentJumpThreshold {
            artifacts.append(("SampleJump", sampleJump))
        }
        
        // Log artifacts
        for (type, magnitude) in artifacts {
            logArtifact(type: type, magnitude: magnitude, context: context, renderSource: renderSource, renderContext: renderContext)
        }
        
        // Update state
        previousSamples = Array(UnsafeBufferPointer(start: data, count: min(frameCount, 1024)))
        previousBlockSilent = isSilent
        hasPreviousBlock = true
    }
    
    func resetContinuity(reason: String) {
        previousSamples.removeAll()
        previousBlockSilent = true
        hasPreviousBlock = false
    }
    
    func artifactCountTotal() -> UInt64 { return artifactCountTotal }
    func artifactCountByType() -> [String: UInt64] { return artifactCountByType }
    
    // MARK: - Private
    
    private func calculateBlockMetrics(data: UnsafePointer<Float>, frameCount: Int, format: PcmStreamFormat) -> BlockMetrics {
        var peak: Double = 0.0
        var sumSquares: Double = 0.0
        
        for i in 0..<frameCount {
            let sample = Double(abs(data[i]))
            peak = max(peak, sample)
            sumSquares += sample * sample
        }
        
        let rms = sqrt(sumSquares / Double(frameCount))
        
        return BlockMetrics(peak: peak, rms: rms, frameCount: frameCount)
    }
    
    private func isSilentBlock(metrics: BlockMetrics) -> Bool {
        return metrics.peak < silentPeakThreshold && metrics.rms < silentRmsThreshold
    }
    
    private func sensitiveContext(renderContext: RenderContext) -> Bool {
        return renderContext.recovery ||
               renderContext.firstDataBlockAfterConfigure ||
               renderContext.firstDataBlockAfterDeviceRebuild
    }
    
    private func logArtifact(type: String, magnitude: Double, context: PlaybackContext, renderSource: String, renderContext: RenderContext) {
        artifactCountTotal += 1
        artifactCountByType[type, default: 0] += 1
        recentArtifactTimesMs.append(context.positionMs)
        
        // Log to PlayerLogger
        PlayerLogger.log(category: "artifact", message: "\(type) magnitude=\(String(format: "%.3f", magnitude)) position=\(context.positionMs)ms state=\(context.playbackState)")
    }
}

struct BlockMetrics {
    let peak: Double
    let rms: Double
    let frameCount: Int
}
```

## Severity classification

```swift
func classifySeverity(type: String, magnitude: Double) -> ArtifactSeverity {
    switch type {
    case "SampleJump", "BlockBoundary":
        if magnitude >= 1.50 { return .critical }
        if magnitude >= 1.00 { return .high }
        if magnitude >= 0.68 { return .medium }
        return .low
        
    case "SilenceHardSwitch":
        if magnitude >= 0.85 { return .high }
        if magnitude >= 0.45 { return .medium }
        return .low
        
    case "ShortBurst":
        if magnitude >= 0.60 { return .high }
        if magnitude >= 0.45 { return .medium }
        return .low
        
    case "CrackleTexture":
        if magnitude >= 0.45 { return .high }
        if magnitude >= 0.30 { return .medium }
        return .low
        
    default:
        return .low
    }
}

enum ArtifactSeverity {
    case critical
    case high
    case medium
    case low
}
```

## Testing

```swift
func testArtifactMonitor() {
    let monitor = AudioArtifactMonitor()
    
    // Create test data with a spike
    var data: [Float] = [Float](repeating: 0.0, count: 1024)
    data[512] = 1.0 // Spike
    
    let format = PcmStreamFormat(sampleRate: 48000, channelCount: 2, bitsPerSample: 32)
    let context = PlaybackContext(sessionId: 1, source: "test.wav", playbackState: "Playing", recentControlEvent: "", positionMs: 0, audioLevelLeft: 0, audioLevelRight: 0, recoveryPending: false, recoveryAttempt: 0)
    let renderContext = RenderContext(warmup: false, silenceFill: false, recovery: false, firstDataBlockAfterConfigure: false, firstDataBlockAfterDeviceRebuild: false)
    
    data.withUnsafeBufferPointer { ptr in
        monitor.analyzePcmBlock(
            data: ptr.baseAddress!,
            byteCount: data.count * 4,
            format: format,
            context: context,
            renderSource: "test",
            renderContext: renderContext
        )
    }
    
    assert(monitor.artifactCountTotal() > 0)
}
```

## See also

- Validation checklist: `docs/dev/validation.md`
- Status tracking: `docs/bug/README.md`
