import Foundation

enum SourceMode {
    case direct
    case remuxed
    case cached
}

enum DecoderType {
    case nativeFilePlayer
    case pcmEngine
    case unsupported
}

struct PlaybackPlan {
    let sourceURL: URL
    let playingURL: URL
    let decoderType: DecoderType
    let sourceMode: SourceMode
    let format: AudioFormat
    let mediaInfo: MediaInfo
    let estimatedMemoryMB: Double

    var isReady: Bool {
        return FileManager.default.fileExists(atPath: playingURL.path)
    }

    var description: String {
        return """
        PlaybackPlan:
          Source: \(sourceURL.lastPathComponent)
          Playing: \(playingURL.lastPathComponent)
          Decoder: \(decoderType)
          Mode: \(sourceMode)
          Format: \(format)
          Duration: \(mediaInfo.durationFormatted)
          Sample Rate: \(mediaInfo.sampleRateFormatted)
          Channels: \(mediaInfo.channelCount)
          Bit Depth: \(mediaInfo.bitDepth)-bit
          Est. Memory: \(String(format: "%.1f", estimatedMemoryMB)) MB
        """
    }
}

class PlaybackPlanBuilder {
    private let probe = SourceProbe()

    func buildPlan(for url: URL) throws -> PlaybackPlan {
        let sourceInfo = probe.probe(url: url)

        guard sourceInfo.isPlayable else {
            throw PlaybackPlanError.unsupportedFormat(sourceInfo.format)
        }

        let sourceMode: SourceMode = .direct
        let playingURL = url

        let memoryEstimate = estimateMemoryUsage(
            duration: sourceInfo.mediaInfo.duration,
            sampleRate: sourceInfo.mediaInfo.sampleRate,
            channelCount: sourceInfo.mediaInfo.channelCount,
            bitDepth: sourceInfo.mediaInfo.bitDepth
        )

        return PlaybackPlan(
            sourceURL: url,
            playingURL: playingURL,
            decoderType: decoderType(for: sourceInfo.backendKind),
            sourceMode: sourceMode,
            format: sourceInfo.format,
            mediaInfo: sourceInfo.mediaInfo,
            estimatedMemoryMB: memoryEstimate
        )
    }

    private func estimateMemoryUsage(
        duration: TimeInterval,
        sampleRate: Double,
        channelCount: Int,
        bitDepth: Int
    ) -> Double {
        let bytesPerSample = Double(bitDepth / 8)
        let totalSamples = duration * sampleRate * Double(channelCount)
        let totalBytes = totalSamples * bytesPerSample
        return totalBytes / 1_048_576
    }

    private func decoderType(for backendKind: PlaybackBackendKind) -> DecoderType {
        switch backendKind {
        case .nativeFilePlayer:
            return .nativeFilePlayer
        case .pcmEngine:
            return .pcmEngine
        case .ffmpegFallback, .unsupported:
            return .unsupported
        }
    }
}

enum PlaybackPlanError: Error {
    case unsupportedFormat(AudioFormat)
    case fileNotFound
    case preparationFailed(Error)

    var localizedDescription: String {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported audio format: \(format)"
        case .fileNotFound:
            return "File not found"
        case .preparationFailed(let error):
            return "Preparation failed: \(error.localizedDescription)"
        }
    }
}
