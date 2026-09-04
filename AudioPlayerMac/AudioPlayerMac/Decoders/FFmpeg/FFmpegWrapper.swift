import AVFoundation

class FFmpegWrapper {
    private var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var swrContext: OpaquePointer?
    private var audioStreamIndex: Int32 = -1
    private var isOpen = false

    init() {
        ffmpeg_init()
    }

    func open(url: URL) throws {
        var ctx: UnsafeMutablePointer<AVFormatContext>?
        let ret = ffmpeg_open_file(url.path, &ctx)
        guard ret == 0, let formatCtx = ctx else {
            throw FFmpegError.openFailed(code: Int(ret), message: String(cString: ffmpeg_error_string(ret)))
        }
        self.formatContext = formatCtx

        let streamIndex = ffmpeg_find_audio_stream(formatCtx)
        guard streamIndex >= 0 else {
            throw FFmpegError.noAudioStream
        }
        self.audioStreamIndex = streamIndex

        guard let decCtx = ffmpeg_create_decoder(formatCtx, streamIndex) else {
            throw FFmpegError.decoderCreationFailed
        }
        self.codecContext = decCtx

        guard let swr = ffmpeg_create_resampler(
            decCtx,
            Int32(AV_SAMPLE_FMT_FLT.rawValue),
            decCtx.pointee.sample_rate,
            2
        ) else {
            throw FFmpegError.resamplerCreationFailed
        }
        self.swrContext = swr

        isOpen = true
    }

    func decode() throws -> AVAudioPCMBuffer? {
        guard isOpen,
              let formatCtx = formatContext,
              let codecCtx = codecContext,
              let swr = swrContext else {
            throw FFmpegError.notOpened
        }

        let packet = ffmpeg_alloc_packet()
        let frame = ffmpeg_alloc_frame()
        defer {
            ffmpeg_free_packet(packet)
            ffmpeg_free_frame(frame)
        }

        while true {
            let readRet = ffmpeg_read_frame(formatCtx, packet)
            if readRet < 0 {
                if readRet == ffmpeg_averror_eof() {
                    return nil
                }
                throw FFmpegError.readFailed(code: Int(readRet), message: String(cString: ffmpeg_error_string(readRet)))
            }

            guard let pkt = packet, pkt.pointee.stream_index == audioStreamIndex else {
                if let pkt = packet { av_packet_unref(pkt) }
                continue
            }

            let sendRet = ffmpeg_send_packet(codecCtx, packet)
            av_packet_unref(packet)
            guard sendRet == 0 else {
                continue
            }

            let recvRet = ffmpeg_receive_frame(codecCtx, frame)
            guard recvRet == 0 else {
                continue
            }

            var outBuffer: UnsafeMutablePointer<UInt8>?
            var outSamples: Int32 = 0
            let resampleRet = ffmpeg_resample(swr, frame, &outBuffer, &outSamples)
            guard resampleRet == 0, let buffer = outBuffer else {
                throw FFmpegError.resampleFailed
            }

            let sampleRate = Double(codecCtx.pointee.sample_rate)
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: false
            )!

            let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(outSamples)
            )!

            pcmBuffer.frameLength = AVAudioFrameCount(outSamples)

            let channelData = pcmBuffer.floatChannelData!

            let interleaved = buffer.withMemoryRebound(to: Float.self, capacity: Int(outSamples) * 2) { ptr in
                return ptr
            }

            for i in 0..<Int(outSamples) {
                channelData[0][i] = interleaved[i * 2]
                channelData[1][i] = interleaved[i * 2 + 1]
            }

            free(buffer)

            return pcmBuffer
        }
    }

    func seek(to positionMs: Int64) throws {
        guard isOpen, let formatCtx = formatContext else {
            throw FFmpegError.notOpened
        }

        let ret = ffmpeg_seek(formatCtx, positionMs)
        guard ret == 0 else {
            throw FFmpegError.seekFailed(code: Int(ret), message: String(cString: ffmpeg_error_string(ret)))
        }

        if let codecCtx = codecContext {
            ffmpeg_flush_buffers(codecCtx)
        }
    }

    func getSampleRate() -> Int {
        guard let ctx = codecContext else { return 0 }
        return Int(ffmpeg_get_sample_rate(ctx))
    }

    func getChannels() -> Int {
        guard let ctx = codecContext else { return 0 }
        return Int(ffmpeg_get_channels(ctx))
    }

    func getDurationMs() -> Int64 {
        guard let ctx = formatContext else { return 0 }
        return ffmpeg_get_duration_ms(ctx)
    }

    func close() {
        if let swr = swrContext {
            ffmpeg_free_resampler(swr)
            swrContext = nil
        }
        if let codecCtx = codecContext {
            ffmpeg_free_decoder(codecCtx)
            codecContext = nil
        }
        if let formatCtx = formatContext {
            ffmpeg_close_file(formatCtx)
            formatContext = nil
        }
        audioStreamIndex = -1
        isOpen = false
    }

    deinit {
        close()
    }

    // MARK: - Static remux helper (no decoding, container copy only)

    /// Remux an elementary audio stream (raw EAC3, etc.) into an MP4 container.
    /// Returns the stream duration in milliseconds on success, nil on failure.
    static func remuxToMP4(inputPath: String, outputPath: String) -> Int64? {
        ffmpeg_init()
        var durationMs: Int64 = 0
        let ret = ffmpeg_remux_to_mp4(inputPath, outputPath, &durationMs)
        guard ret == 0 else {
            return nil
        }
        return durationMs
    }

}

enum FFmpegError: Error {
    case openFailed(code: Int, message: String)
    case noAudioStream
    case decoderCreationFailed
    case resamplerCreationFailed
    case notOpened
    case readFailed(code: Int, message: String)
    case resampleFailed
    case seekFailed(code: Int, message: String)
}
