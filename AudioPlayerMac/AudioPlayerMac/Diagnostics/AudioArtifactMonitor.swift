import Foundation

enum ArtifactType: String, CaseIterable {
    case transientSpike = "TransientSpike"
    case shortBurst = "ShortBurst"
    case crackleTexture = "CrackleTexture"
    case blockBoundary = "BlockBoundary"
    case sampleJump = "SampleJump"
    case silenceHardSwitch = "SilenceHardSwitch"
    case none = "None"
}

enum ArtifactSeverity: String {
    case critical
    case high
    case medium
    case low
}

struct ArtifactEvent {
    let type: ArtifactType
    let severity: ArtifactSeverity
    let magnitude: Double
    let positionMs: Int64
    let timestamp: Date
    let context: String
}

struct BlockMetrics {
    let peak: Double
    let rms: Double
    let frameCount: Int
}

struct BurstScanResult {
    let peak: Double
    let rms: Double
    let ratioToBlockRms: Double
}

struct CrackleScanResult {
    let score: Double
    let averageJump: Double
    let maxJump: Double
    let jumpCount: Int
}

struct PlaybackContext {
    let sessionId: Int
    let source: String
    let playbackState: String
    let positionMs: Int64
    let audioLevelLeft: Float
    let audioLevelRight: Float
}

struct RenderContext {
    let warmup: Bool
    let silenceFill: Bool
    let recovery: Bool
    let firstDataBlockAfterConfigure: Bool
    let firstDataBlockAfterDeviceRebuild: Bool
}

class AudioArtifactMonitor {
    struct Thresholds {
        static let adjacentJumpThreshold: Double = 0.68
        static let boundaryJumpThreshold: Double = 0.45
        static let transientPeakThreshold: Double = 0.68
        static let transientNeighborThreshold: Double = 0.24
        static let silentPeakThreshold: Double = 0.003
        static let silentRmsThreshold: Double = 0.001
        static let hardSwitchOpeningPeakThreshold: Double = 0.12
        static let hardSwitchJumpThreshold: Double = 0.14
        static let shortBurstPeakThreshold: Double = 0.45
        static let shortBurstRmsThreshold: Double = 0.10
        static let crackleJumpThreshold: Double = 0.24
        static let crackleMinJumpCount: Int = 4
    }

    private var previousSamples: [Float] = []
    private var previousBlockSilent: Bool = true
    private var hasPreviousBlock: Bool = false
    private var artifactCountTotal: UInt64 = 0
    private var artifactCountByType: [String: UInt64] = [:]
    private var recentArtifactEvents: [ArtifactEvent] = []
    private let maxRecentEvents = 100

    func analyzePcmBlock(
        data: UnsafePointer<Float>,
        byteCount: Int,
        format: (sampleRate: Double, channelCount: Int, bitsPerSample: Int),
        context: PlaybackContext,
        renderContext: RenderContext
    ) -> [ArtifactEvent] {
        let bytesPerSample = format.bitsPerSample / 8
        let frameCount = byteCount / (format.channelCount * bytesPerSample)

        let metrics = calculateBlockMetrics(data: data, frameCount: frameCount)
        let isSilent = isSilentBlock(metrics: metrics)

        var artifacts: [ArtifactEvent] = []

        if let event = detectTransientSpike(data: data, frameCount: frameCount, context: context) {
            artifacts.append(event)
        }

        if let event = detectShortBurst(data: data, frameCount: frameCount, format: format, blockRms: metrics.rms, context: context) {
            artifacts.append(event)
        }

        if let event = detectCrackleTexture(data: data, frameCount: frameCount, format: format, context: context) {
            artifacts.append(event)
        }

        if hasPreviousBlock {
            let boundaryJump = detectBlockBoundary(
                previousBlock: previousSamples,
                currentBlock: Array(UnsafeBufferPointer(start: data, count: min(frameCount, 1024))),
                channelCount: format.channelCount
            )

            if boundaryJump >= Thresholds.boundaryJumpThreshold {
                let severity = classifySeverity(type: .blockBoundary, magnitude: boundaryJump)
                let event = ArtifactEvent(
                    type: .blockBoundary,
                    severity: severity,
                    magnitude: boundaryJump,
                    positionMs: context.positionMs,
                    timestamp: Date(),
                    context: "boundary_jump=\(String(format: "%.3f", boundaryJump))"
                )
                artifacts.append(event)
            }

            if detectSilenceHardSwitch(
                previousBlockSilent: previousBlockSilent,
                currentBlock: Array(UnsafeBufferPointer(start: data, count: min(frameCount, 1024))),
                boundaryJump: boundaryJump
            ) {
                let event = ArtifactEvent(
                    type: .silenceHardSwitch,
                    severity: .medium,
                    magnitude: boundaryJump,
                    positionMs: context.positionMs,
                    timestamp: Date(),
                    context: "silence_to_sound"
                )
                artifacts.append(event)
            }
        }

        if let event = detectSampleJump(data: data, frameCount: frameCount, context: context) {
            artifacts.append(event)
        }

        for event in artifacts {
            logArtifact(event: event)
        }

        previousSamples = Array(UnsafeBufferPointer(start: data, count: min(frameCount, 1024)))
        previousBlockSilent = isSilent
        hasPreviousBlock = true

        return artifacts
    }

    func resetContinuity(reason: String) {
        previousSamples.removeAll()
        previousBlockSilent = true
        hasPreviousBlock = false
        PlayerLogger.shared.log(category: "artifact", message: "Continuity reset: \(reason)")
    }

    func getArtifactCountTotal() -> UInt64 {
        return artifactCountTotal
    }

    func getArtifactCountByType() -> [String: UInt64] {
        return artifactCountByType
    }

    func getRecentEvents(limit: Int = 20) -> [ArtifactEvent] {
        return Array(recentArtifactEvents.suffix(limit))
    }

    // MARK: - Private Detection Methods

    private func calculateBlockMetrics(data: UnsafePointer<Float>, frameCount: Int) -> BlockMetrics {
        var peak: Double = 0.0
        var sumSquares: Double = 0.0

        for i in 0..<frameCount {
            let sample = Double(abs(data[i]))
            peak = max(peak, sample)
            sumSquares += sample * sample
        }

        let rms = frameCount > 0 ? sqrt(sumSquares / Double(frameCount)) : 0.0
        return BlockMetrics(peak: peak, rms: rms, frameCount: frameCount)
    }

    private func isSilentBlock(metrics: BlockMetrics) -> Bool {
        return metrics.peak < Thresholds.silentPeakThreshold &&
               metrics.rms < Thresholds.silentRmsThreshold
    }

    private func detectTransientSpike(
        data: UnsafePointer<Float>,
        frameCount: Int,
        context: PlaybackContext
    ) -> ArtifactEvent? {
        var peakMagnitude: Double = 0.0

        for i in 1..<(frameCount - 1) {
            let prev = Double(abs(data[i - 1]))
            let curr = Double(abs(data[i]))
            let next = Double(abs(data[i + 1]))

            if curr >= Thresholds.transientPeakThreshold &&
               prev <= Thresholds.transientNeighborThreshold &&
               next <= Thresholds.transientNeighborThreshold {
                peakMagnitude = max(peakMagnitude, curr)
            }
        }

        guard peakMagnitude > 0 else { return nil }

        let severity = classifySeverity(type: .transientSpike, magnitude: peakMagnitude)
        return ArtifactEvent(
            type: .transientSpike,
            severity: severity,
            magnitude: peakMagnitude,
            positionMs: context.positionMs,
            timestamp: Date(),
            context: "peak=\(String(format: "%.3f", peakMagnitude))"
        )
    }

    private func detectShortBurst(
        data: UnsafePointer<Float>,
        frameCount: Int,
        format: (sampleRate: Double, channelCount: Int, bitsPerSample: Int),
        blockRms: Double,
        context: PlaybackContext
    ) -> ArtifactEvent? {
        let windowMs: Double = 2.0
        let windowSamples = Int(format.sampleRate * windowMs / 1000.0)
        guard windowSamples > 0 else { return nil }

        let step = max(1, windowSamples / 2)
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

        guard maxPeak >= Thresholds.shortBurstPeakThreshold &&
              maxRms >= Thresholds.shortBurstRmsThreshold &&
              ratio >= 2.0 else { return nil }

        let severity = classifySeverity(type: .shortBurst, magnitude: maxPeak)
        return ArtifactEvent(
            type: .shortBurst,
            severity: severity,
            magnitude: maxPeak,
            positionMs: context.positionMs,
            timestamp: Date(),
            context: "peak=\(String(format: "%.3f", maxPeak)) rms=\(String(format: "%.3f", maxRms))"
        )
    }

    private func detectCrackleTexture(
        data: UnsafePointer<Float>,
        frameCount: Int,
        format: (sampleRate: Double, channelCount: Int, bitsPerSample: Int),
        context: PlaybackContext
    ) -> ArtifactEvent? {
        let windowMs: Double = 3.0
        let windowSamples = Int(format.sampleRate * windowMs / 1000.0)
        guard windowSamples > 0 else { return nil }

        let step = max(1, windowSamples / 2)
        let jumpThreshold = Thresholds.crackleJumpThreshold
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

        guard totalJumps >= Thresholds.crackleMinJumpCount else { return nil }

        let averageJump = sumJumps / Double(totalJumps)
        guard averageJump >= 0.30 else { return nil }

        let severity = classifySeverity(type: .crackleTexture, magnitude: maxJump)
        return ArtifactEvent(
            type: .crackleTexture,
            severity: severity,
            magnitude: maxJump,
            positionMs: context.positionMs,
            timestamp: Date(),
            context: "jumps=\(totalJumps) avg=\(String(format: "%.3f", averageJump))"
        )
    }

    private func detectBlockBoundary(previousBlock: [Float], currentBlock: [Float], channelCount: Int) -> Double {
        guard !previousBlock.isEmpty && !currentBlock.isEmpty else { return 0.0 }

        var maxJump: Double = 0.0
        for ch in 0..<channelCount {
            let prevIdx = previousBlock.count - channelCount + ch
            guard prevIdx >= 0 && prevIdx < previousBlock.count && ch < currentBlock.count else { continue }
            let prev = Double(previousBlock[prevIdx])
            let curr = Double(currentBlock[ch])
            maxJump = max(maxJump, abs(curr - prev))
        }

        return maxJump
    }

    private func detectSilenceHardSwitch(
        previousBlockSilent: Bool,
        currentBlock: [Float],
        boundaryJump: Double
    ) -> Bool {
        guard previousBlockSilent && !currentBlock.isEmpty else { return false }
        let openingPeak = Double(abs(currentBlock[0]))
        return openingPeak >= Thresholds.hardSwitchOpeningPeakThreshold &&
               boundaryJump >= Thresholds.hardSwitchJumpThreshold
    }

    private func detectSampleJump(
        data: UnsafePointer<Float>,
        frameCount: Int,
        context: PlaybackContext
    ) -> ArtifactEvent? {
        var maxJump: Double = 0.0

        for i in 1..<frameCount {
            let jump = Double(abs(data[i] - data[i - 1]))
            maxJump = max(maxJump, jump)
        }

        guard maxJump >= Thresholds.adjacentJumpThreshold else { return nil }

        let severity = classifySeverity(type: .sampleJump, magnitude: maxJump)
        return ArtifactEvent(
            type: .sampleJump,
            severity: severity,
            magnitude: maxJump,
            positionMs: context.positionMs,
            timestamp: Date(),
            context: "jump=\(String(format: "%.3f", maxJump))"
        )
    }

    private func classifySeverity(type: ArtifactType, magnitude: Double) -> ArtifactSeverity {
        switch type {
        case .sampleJump, .blockBoundary:
            if magnitude >= 1.50 { return .critical }
            if magnitude >= 1.00 { return .high }
            if magnitude >= 0.68 { return .medium }
            return .low

        case .silenceHardSwitch:
            if magnitude >= 0.85 { return .high }
            if magnitude >= 0.45 { return .medium }
            return .low

        case .shortBurst:
            if magnitude >= 0.60 { return .high }
            if magnitude >= 0.45 { return .medium }
            return .low

        case .crackleTexture:
            if magnitude >= 0.45 { return .high }
            if magnitude >= 0.30 { return .medium }
            return .low

        case .transientSpike:
            if magnitude >= 1.00 { return .high }
            if magnitude >= 0.68 { return .medium }
            return .low

        case .none:
            return .low
        }
    }

    private func logArtifact(event: ArtifactEvent) {
        artifactCountTotal += 1
        artifactCountByType[event.type.rawValue, default: 0] += 1
        recentArtifactEvents.append(event)

        if recentArtifactEvents.count > maxRecentEvents {
            recentArtifactEvents.removeFirst(recentArtifactEvents.count - maxRecentEvents)
        }

        PlayerLogger.shared.log(
            category: "artifact",
            level: event.severity == .critical || event.severity == .high ? .error : .warning,
            message: "\(event.type.rawValue) magnitude=\(String(format: "%.3f", event.magnitude)) position=\(event.positionMs)ms severity=\(event.severity.rawValue)"
        )
    }
}
