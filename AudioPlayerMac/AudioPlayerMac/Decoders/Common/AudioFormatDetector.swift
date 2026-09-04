import Foundation
import AVFoundation

enum AudioFormat {
    case eac3
    case ac3
    case aac
    case alac
    case flac
    case wav
    case mp3
    case truehd
    case mlp
    case unknown
}

class AudioFormatDetector {
    func detect(url: URL) -> AudioFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "eac3", "eb3":
            return .eac3
        case "ac3":
            return .ac3
        case "alac":
            return .alac
        case "flac":
            return .flac
        case "wav":
            return .wav
        case "mp3":
            return .mp3
        case "truehd", "thd":
            return .truehd
        case "mlp":
            return .mlp
        default:
            break
        }

        let asset = AVURLAsset(url: url)
        if let format = detectFromAsset(asset) {
            return format
        }

        if ext == "aac" || ext == "m4a" {
            return .aac
        }

        return .unknown
    }

    private func detectFromAsset(_ asset: AVURLAsset) -> AudioFormat? {
        guard let track = asset.tracks(withMediaType: .audio).first else {
            return nil
        }

        let desc = track.formatDescriptions.first as! CMFormatDescription
        let codec = desc.audioStreamBasicDescription?.mFormatID

        switch codec {
        case kAudioFormatAC3:
            return .ac3
        case kAudioFormatEnhancedAC3:
            return .eac3
        case kAudioFormatMPEG4AAC:
            return .aac
        case kAudioFormatAppleLossless:
            return .alac
        case kAudioFormatLinearPCM:
            return .wav
        case kAudioFormatMPEGLayer3:
            return .mp3
        default:
            return nil
        }
    }
}
