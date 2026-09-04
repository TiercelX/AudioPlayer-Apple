import Foundation
import AVFoundation

struct MediaInfo {
    let url: URL
    let fileName: String
    let fileExtension: String
    let fileSize: Int64
    let duration: TimeInterval
    let format: AudioFormat
    let codecName: String
    let sampleRate: Double
    let channelCount: Int
    let bitDepth: Int
    let isFloat: Bool
    let bitrate: Int
    let isDolby: Bool
    let isLossless: Bool

    /// Precise bit depth label, e.g. "32-bit float", "24-bit", "16-bit".
    var bitDepthFormatted: String {
        if isFloat {
            return "\(bitDepth)-bit float"
        }
        return "\(bitDepth)-bit int"
    }

    var durationFormatted: String {
        guard duration.isFinite && duration >= 0 else { return "00:00" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var sampleRateFormatted: String {
        if sampleRate >= 1000 {
            return String(format: "%.1f kHz", sampleRate / 1000)
        }
        return String(format: "%.0f Hz", sampleRate)
    }

    var bitrateFormatted: String {
        guard bitrate > 0 else { return "N/A" }
        if bitrate >= 1000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1000)
        }
        return "\(bitrate) kbps"
    }

    var fileSizeFormatted: String {
        let bytes = Double(fileSize)
        if bytes >= 1_073_741_824 {
            return String(format: "%.2f GB", bytes / 1_073_741_824)
        } else if bytes >= 1_048_576 {
            return String(format: "%.1f MB", bytes / 1_048_576)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", bytes / 1024)
        }
        return "\(fileSize) bytes"
    }

    static func from(url: URL) -> MediaInfo {
        let detector = AudioFormatDetector()
        let format = detector.detect(url: url)

        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension

        var fileSize: Int64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        }

        var duration: TimeInterval = 0
        var sampleRate: Double = 0
        var channelCount: Int = 2
        var bitDepth: Int = 16
        var isFloat: Bool = false
        var bitrate: Int = 0

        // Use AVAudioFile to read the decoded PCM format — this gives the
        // correct bit depth and sample rate for lossless formats like ALAC/FLAC
        // where AVURLAsset ASBD may report the compressed format descriptor.
        if let audioFile = try? AVAudioFile(forReading: url) {
            let fmt = audioFile.processingFormat
            let desc = fmt.streamDescription.pointee
            if desc.mSampleRate > 0 { sampleRate = desc.mSampleRate }
            if desc.mChannelsPerFrame > 0 { channelCount = Int(desc.mChannelsPerFrame) }
            if desc.mBitsPerChannel > 0 { bitDepth = Int(desc.mBitsPerChannel) }
            isFloat = (desc.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            if desc.mSampleRate > 0 {
                duration = Double(audioFile.length) / desc.mSampleRate
            }
        } else {
            let asset = AVURLAsset(url: url)
            let assetDuration = asset.duration.seconds
            if assetDuration.isFinite && assetDuration > 0 {
                duration = assetDuration
            }
        }

        // Estimate bitrate from file size and duration for lossy formats;
        // for lossless, derive from PCM parameters.
        if sampleRate > 0 && channelCount > 0 && bitDepth > 0 {
            bitrate = Int(sampleRate * Double(channelCount * bitDepth) / 1000)
        } else if fileSize > 0 && duration > 0 {
            bitrate = Int(Double(fileSize) * 8.0 / duration / 1000)
        }

        let codecName: String
        switch format {
        case .eac3: codecName = "E-AC-3 (Dolby Digital Plus)"
        case .ac3: codecName = "AC-3 (Dolby Digital)"
        case .aac: codecName = "AAC"
        case .alac: codecName = "Apple Lossless (ALAC)"
        case .flac: codecName = "FLAC"
        case .wav: codecName = "PCM (WAV)"
        case .mp3: codecName = "MP3"
        case .truehd: codecName = "TrueHD (Dolby)"
        case .mlp: codecName = "MLP (Meridian Lossless)"
        case .unknown: codecName = "Unknown"
        }

        let isDolby: Bool
        switch format {
        case .eac3, .ac3, .truehd, .mlp: isDolby = true
        default: isDolby = false
        }

        let isLossless: Bool
        switch format {
        case .flac, .alac, .wav, .truehd, .mlp: isLossless = true
        default: isLossless = false
        }

        return MediaInfo(
            url: url,
            fileName: fileName,
            fileExtension: fileExtension,
            fileSize: fileSize,
            duration: duration,
            format: format,
            codecName: codecName,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitDepth: bitDepth,
            isFloat: isFloat,
            bitrate: bitrate,
            isDolby: isDolby,
            isLossless: isLossless
        )
    }
}
