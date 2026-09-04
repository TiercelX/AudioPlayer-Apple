import AVFoundation

class AVFoundationDecoder: AudioDecoder {
    private var audioFile: AVAudioFile?
    private var fileFormat: AVAudioFormat?
    private(set) var processingFormat: AVAudioFormat?
    private var framePosition: AVAudioFramePosition = 0

    func open(url: URL) throws {
        switch AudioFormatDetector().detect(url: url) {
        case .eac3, .ac3, .truehd, .mlp:
            throw DecoderError.unsupportedFormat("Compressed Dolby sources must remain compressed and use NativeFilePlayerBackend or an explicit unsupported result")
        default:
            break
        }

        audioFile = try AVAudioFile(forReading: url)
        fileFormat = audioFile?.fileFormat
        processingFormat = audioFile?.processingFormat
        framePosition = 0
    }

    func decode() throws -> AVAudioPCMBuffer? {
        guard let file = audioFile else {
            throw DecoderError.notOpened
        }

        let frameCount = AVAudioFrameCount(4096)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw DecoderError.bufferCreationFailed
        }

        do {
            try file.read(into: buffer)
        } catch {
            throw DecoderError.readFailed(error)
        }

        if buffer.frameLength == 0 {
            return nil
        }

        framePosition += AVAudioFramePosition(buffer.frameLength)
        return buffer
    }

    func seek(to positionMs: Int64) throws {
        guard let file = audioFile,
              let format = processingFormat else {
            throw DecoderError.notOpened
        }

        let sampleRate = format.sampleRate
        let framePos = AVAudioFramePosition(Double(positionMs) / 1000.0 * sampleRate)

        guard framePos >= 0 && framePos < file.length else {
            throw DecoderError.seekOutOfBounds
        }

        file.framePosition = framePos
        self.framePosition = framePos
    }

    func close() {
        audioFile = nil
        fileFormat = nil
        processingFormat = nil
        framePosition = 0
    }

    var currentPositionMs: Int64 {
        guard let format = processingFormat else { return 0 }
        return Int64(Double(framePosition) / format.sampleRate * 1000)
    }

    var durationMs: Int64 {
        guard let file = audioFile,
              let format = processingFormat else { return 0 }
        return Int64(Double(file.length) / format.sampleRate * 1000)
    }
}
