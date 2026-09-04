import Foundation

enum PlaybackBackendKind: String {
    case nativeFilePlayer = "NativeFilePlayerBackend"
    case pcmEngine = "PCMEngineBackend"
    case ffmpegFallback = "FFmpegFallbackBackend"
    case unsupported = "Unsupported"
}

enum PlaybackRoutingError: LocalizedError {
    case unsupportedFormat(AudioFormat, URL)
    case ffmpegFallbackReserved(AudioFormat)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format, let url):
            return "Unsupported audio format \(format) for \(url.lastPathComponent)"
        case .ffmpegFallbackReserved(let format):
            return "FFmpeg fallback is reserved for \(format) but is not enabled in this phase"
        }
    }
}

struct PlaybackRoute {
    let format: AudioFormat
    let extensionName: String
    let backendKind: PlaybackBackendKind
    let preservesCompressedSource: Bool

    var containerDescription: String {
        extensionName.isEmpty ? "unknown" : extensionName
    }
}

class DecoderRouter {
    private let detector = AudioFormatDetector()

    func selectBackend(for url: URL) throws -> PlaybackRoute {
        let format = detector.detect(url: url)
        let ext = url.pathExtension.lowercased()

        switch format {
        case .wav:
            return PlaybackRoute(
                format: format,
                extensionName: ext,
                backendKind: .pcmEngine,
                preservesCompressedSource: false
            )

        case .mp3, .aac, .alac, .flac, .ac3, .eac3:
            return PlaybackRoute(
                format: format,
                extensionName: ext,
                backendKind: .nativeFilePlayer,
                preservesCompressedSource: true
            )

        case .truehd, .mlp:
            throw PlaybackRoutingError.ffmpegFallbackReserved(format)

        case .unknown:
            if isLikelySystemPlayableExtension(ext) {
                return PlaybackRoute(
                    format: format,
                    extensionName: ext,
                    backendKind: .nativeFilePlayer,
                    preservesCompressedSource: true
                )
            }
            throw PlaybackRoutingError.unsupportedFormat(format, url)
        }
    }

    private func isLikelySystemPlayableExtension(_ ext: String) -> Bool {
        switch ext {
        case "m4a", "mp4", "caf", "aif", "aiff":
            return true
        default:
            return false
        }
    }
}
