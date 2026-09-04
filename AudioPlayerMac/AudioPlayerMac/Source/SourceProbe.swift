import Foundation
import AVFoundation

struct SourceInfo {
    let url: URL
    let format: AudioFormat
    let mediaInfo: MediaInfo
    let needsRemux: Bool
    let backendKind: PlaybackBackendKind

    var isPlayable: Bool {
        return backendKind != .unsupported
    }
}

class SourceProbe {
    private let formatDetector = AudioFormatDetector()
    private let decoderRouter = DecoderRouter()

    func probe(url: URL) -> SourceInfo {
        let format = formatDetector.detect(url: url)
        let mediaInfo = MediaInfo.from(url: url)
        let route = try? decoderRouter.selectBackend(for: url)

        return SourceInfo(
            url: url,
            format: format,
            mediaInfo: mediaInfo,
            needsRemux: false,
            backendKind: route?.backendKind ?? .unsupported
        )
    }

    func probeDetailed(url: URL) async -> SourceInfo {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let info = self?.probe(url: url) ?? SourceInfo(
                    url: url,
                    format: .unknown,
                    mediaInfo: MediaInfo.from(url: url),
                    needsRemux: false,
                    backendKind: .unsupported
                )
                continuation.resume(returning: info)
            }
        }
    }

    func getStreamInfo(url: URL) -> [String: Any] {
        let info = probe(url: url)
        return [
            "fileName": info.mediaInfo.fileName,
            "format": String(describing: info.format),
            "codec": info.mediaInfo.codecName,
            "sampleRate": info.mediaInfo.sampleRate,
            "channelCount": info.mediaInfo.channelCount,
            "bitDepth": info.mediaInfo.bitDepth,
            "duration": info.mediaInfo.duration,
            "fileSize": info.mediaInfo.fileSize,
            "needsRemux": info.needsRemux,
            "backendKind": info.backendKind.rawValue
        ]
    }
}
