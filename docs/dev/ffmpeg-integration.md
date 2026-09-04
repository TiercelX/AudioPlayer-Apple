# FFmpeg libav Integration Guide

## Overview

AudioPlayerMac uses FFmpeg libav for decoding TrueHD and other complex formats. The integration uses a C bridge layer that wraps FFmpeg's C API and exposes it to Swift.

## Integration methods

### Option 1: Homebrew FFmpeg (Recommended for development)

Install FFmpeg via Homebrew:

```bash
brew install ffmpeg
```

Configure Xcode project:
1. Add Header Search Paths: `/opt/homebrew/include` (Apple Silicon) or `/usr/local/include` (Intel)
2. Add Library Search Paths: `/opt/homebrew/lib` (Apple Silicon) or `/usr/local/lib` (Intel)
3. Add linker flags: `-lavformat -lavcodec -lswresample -lavutil`

### Option 2: Manual FFmpeg build (Recommended for distribution)

Build FFmpeg statically for macOS:

```bash
# Download FFmpeg source
git clone https://git.ffmpeg.org/ffmpeg.git
cd ffmpeg

# Configure for macOS static build (Apple Silicon)
./configure \
    --prefix=/usr/local/ffmpeg-mac-arm64 \
    --enable-static \
    --disable-shared \
    --disable-programs \
    --disable-doc \
    --enable-cross-compile \
    --arch=arm64 \
    --target-os=darwin \
    --extra-cflags="-arch arm64" \
    --extra-ldflags="-arch arm64"

# Configure for macOS static build (Intel)
./configure \
    --prefix=/usr/local/ffmpeg-mac-x86_64 \
    --enable-static \
    --disable-shared \
    --disable-programs \
    --disable-doc \
    --enable-cross-compile \
    --arch=x86_64 \
    --target-os=darwin \
    --extra-cflags="-arch x86_64" \
    --extra-ldflags="-arch x86_64"

# Build and install
make -j$(sysctl -n hw.ncpu)
make install
```

### Option 3: Swift Package Manager (Future)

Create a Package.swift that wraps FFmpeg:

```swift
// This requires pre-built FFmpeg libraries
let package = Package(
    name: "FFmpegBridge",
    products: [
        .library(name: "FFmpegBridge", targets: ["FFmpegBridge"]),
    ],
    targets: [
        .target(
            name: "FFmpegBridge",
            path: "Sources/FFmpegBridge",
            linkerSettings: [
                .linkedLibrary("avformat"),
                .linkedLibrary("avcodec"),
                .linkedLibrary("swresample"),
                .linkedLibrary("avutil"),
            ]
        ),
    ]
)
```

## C Bridge Layer

### FFmpegBridge.h

```c
#ifndef FFmpegBridge_h
#define FFmpegBridge_h

#include <stdint.h>
#include <stddef.h>

// Opaque types
typedef struct AVFormatContext AVFormatContext;
typedef struct AVCodecContext AVCodecContext;
typedef struct AVFrame AVFrame;
typedef struct AVPacket AVPacket;
typedef struct SwrContext SwrContext;

// Initialization
void ffmpeg_init(void);

// Format context
int ffmpeg_open_file(const char *path, AVFormatContext **ctx);
void ffmpeg_close_file(AVFormatContext *ctx);

// Stream info
int ffmpeg_find_audio_stream(AVFormatContext *ctx);
AVCodecContext *ffmpeg_create_decoder(AVFormatContext *ctx, int stream_index);
void ffmpeg_free_decoder(AVCodecContext *ctx);

// Get stream info
int ffmpeg_get_sample_rate(AVCodecContext *ctx);
int ffmpeg_get_channels(AVCodecContext *ctx);
int64_t ffmpeg_get_duration_ms(AVFormatContext *ctx);

// Decoding
int ffmpeg_read_frame(AVFormatContext *ctx, AVPacket *pkt);
int ffmpeg_send_packet(AVCodecContext *ctx, AVPacket *pkt);
int ffmpeg_receive_frame(AVCodecContext *ctx, AVFrame *frame);

// Packet/frame management
AVPacket *ffmpeg_alloc_packet(void);
void ffmpeg_free_packet(AVPacket *pkt);
AVFrame *ffmpeg_alloc_frame(void);
void ffmpeg_free_frame(AVFrame *frame);

// Resampling
SwrContext *ffmpeg_create_resampler(
    AVCodecContext *decoder_ctx,
    int out_sample_fmt,
    int out_sample_rate,
    int out_channels
);
int ffmpeg_resample(
    SwrContext *swr_ctx,
    AVFrame *in_frame,
    uint8_t **out_buffer,
    int *out_samples
);
void ffmpeg_free_resampler(SwrContext *ctx);

// Seeking
int ffmpeg_seek(AVFormatContext *ctx, int64_t timestamp_ms);
void ffmpeg_flush_buffers(AVCodecContext *ctx);

// Utility
const char *ffmpeg_version(void);
const char *ffmpeg_error_string(int error_code);
int ffmpeg_get_frame_size(AVCodecContext *ctx);

#endif
```

### FFmpegBridge.c

```c
#include "FFmpegBridge.h"

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/opt.h>
#include <libavutil/channel_layout.h>
#include <stdlib.h>
#include <string.h>

void ffmpeg_init(void) {
    // FFmpeg 4.0+ auto-registers codecs
    // No explicit registration needed
}

int ffmpeg_open_file(const char *path, AVFormatContext **ctx) {
    int ret = avformat_open_input(ctx, path, NULL, NULL);
    if (ret < 0) return ret;
    
    ret = avformat_find_stream_info(*ctx, NULL);
    if (ret < 0) {
        avformat_close_input(ctx);
        return ret;
    }
    
    return 0;
}

void ffmpeg_close_file(AVFormatContext *ctx) {
    if (ctx) {
        avformat_close_input(&ctx);
    }
}

int ffmpeg_find_audio_stream(AVFormatContext *ctx) {
    for (unsigned i = 0; i < ctx->nb_streams; i++) {
        if (ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            return (int)i;
        }
    }
    return -1;
}

AVCodecContext *ffmpeg_create_decoder(AVFormatContext *ctx, int stream_index) {
    AVCodecParameters *par = ctx->streams[stream_index]->codecpar;
    const AVCodec *codec = avcodec_find_decoder(par->codec_id);
    if (!codec) return NULL;
    
    AVCodecContext *dec_ctx = avcodec_alloc_context3(codec);
    if (!dec_ctx) return NULL;
    
    if (avcodec_parameters_to_context(dec_ctx, par) < 0) {
        avcodec_free_context(&dec_ctx);
        return NULL;
    }
    
    if (avcodec_open2(dec_ctx, codec, NULL) < 0) {
        avcodec_free_context(&dec_ctx);
        return NULL;
    }
    
    return dec_ctx;
}

void ffmpeg_free_decoder(AVCodecContext *ctx) {
    if (ctx) {
        avcodec_free_context(&ctx);
    }
}

int ffmpeg_get_sample_rate(AVCodecContext *ctx) {
    return ctx->sample_rate;
}

int ffmpeg_get_channels(AVCodecContext *ctx) {
    return ctx->ch_layout.nb_channels;
}

int64_t ffmpeg_get_duration_ms(AVFormatContext *ctx) {
    if (ctx->duration == AV_NOPTS_VALUE) {
        return 0;
    }
    return ctx->duration / (AV_TIME_BASE / 1000);
}

int ffmpeg_read_frame(AVFormatContext *ctx, AVPacket *pkt) {
    return av_read_frame(ctx, pkt);
}

int ffmpeg_send_packet(AVCodecContext *ctx, AVPacket *pkt) {
    return avcodec_send_packet(ctx, pkt);
}

int ffmpeg_receive_frame(AVCodecContext *ctx, AVFrame *frame) {
    return avcodec_receive_frame(ctx, frame);
}

AVPacket *ffmpeg_alloc_packet(void) {
    return av_packet_alloc();
}

void ffmpeg_free_packet(AVPacket *pkt) {
    if (pkt) {
        av_packet_free(&pkt);
    }
}

AVFrame *ffmpeg_alloc_frame(void) {
    return av_frame_alloc();
}

void ffmpeg_free_frame(AVFrame *frame) {
    if (frame) {
        av_frame_free(&frame);
    }
}

SwrContext *ffmpeg_create_resampler(
    AVCodecContext *decoder_ctx,
    int out_sample_fmt,
    int out_sample_rate,
    int out_channels
) {
    SwrContext *swr_ctx = swr_alloc();
    if (!swr_ctx) return NULL;
    
    // Set input options
    av_opt_set_chlayout(swr_ctx, "in_chlayout", &decoder_ctx->ch_layout, 0);
    av_opt_set_int(swr_ctx, "in_sample_rate", decoder_ctx->sample_rate, 0);
    av_opt_set_sample_fmt(swr_ctx, "in_sample_fmt", decoder_ctx->sample_fmt, 0);
    
    // Set output options
    AVChannelLayout out_layout = AV_CHANNEL_LAYOUT_STEREO;
    av_opt_set_chlayout(swr_ctx, "out_chlayout", &out_layout, 0);
    av_opt_set_int(swr_ctx, "out_sample_rate", out_sample_rate, 0);
    av_opt_set_sample_fmt(swr_ctx, "out_sample_fmt", (enum AVSampleFormat)out_sample_fmt, 0);
    
    if (swr_init(swr_ctx) < 0) {
        swr_free(&swr_ctx);
        return NULL;
    }
    
    return swr_ctx;
}

int ffmpeg_resample(
    SwrContext *swr_ctx,
    AVFrame *in_frame,
    uint8_t **out_buffer,
    int *out_samples
) {
    *out_samples = swr_get_out_samples(swr_ctx, in_frame->nb_samples);
    int bytes_per_sample = av_get_bytes_per_sample(AV_SAMPLE_FMT_FLT);
    int out_channels = 2; // Stereo output
    
    *out_buffer = (uint8_t *)malloc(*out_samples * out_channels * bytes_per_sample);
    if (!*out_buffer) return -1;
    
    int ret = swr_convert(
        swr_ctx,
        out_buffer,
        *out_samples,
        (const uint8_t **)in_frame->extended_data,
        in_frame->nb_samples
    );
    
    if (ret < 0) {
        free(*out_buffer);
        *out_buffer = NULL;
        return ret;
    }
    
    *out_samples = ret;
    return 0;
}

void ffmpeg_free_resampler(SwrContext *ctx) {
    if (ctx) {
        swr_free(&ctx);
    }
}

int ffmpeg_seek(AVFormatContext *ctx, int64_t timestamp_ms) {
    int64_t timestamp_av = timestamp_ms * (AV_TIME_BASE / 1000);
    return av_seek_frame(ctx, -1, timestamp_av, AVSEEK_FLAG_BACKWARD);
}

void ffmpeg_flush_buffers(AVCodecContext *ctx) {
    avcodec_flush_buffers(ctx);
}

const char *ffmpeg_version(void) {
    return av_version_info();
}

const char *ffmpeg_error_string(int error_code) {
    static char error_buffer[AV_ERROR_MAX_STRING_SIZE];
    return av_make_error_string(error_buffer, AV_ERROR_MAX_STRING_SIZE, error_code);
}

int ffmpeg_get_frame_size(AVCodecContext *ctx) {
    return ctx->frame_size;
}
```

## Swift Wrapper

```swift
// AudioPlayerMac/Decoders/FFmpeg/FFmpegWrapper.swift

import AVFoundation

class FFmpegWrapper {
    private var formatContext: UnsafeMutablePointer<AVFormatContext>?
    private var codecContext: UnsafeMutablePointer<AVCodecContext>?
    private var swrContext: UnsafeMutablePointer<SwrContext>?
    private var audioStreamIndex: Int32 = -1
    private var isOpen = false
    
    init() {
        ffmpeg_init()
    }
    
    func open(url: URL) throws {
        var ctx: UnsafeMutablePointer<AVFormatContext>?
        let ret = ffmpeg_open_file(url.path, &ctx)
        guard ret == 0, let formatCtx = ctx else {
            throw FFmpegError.openFailed(code: ret, message: String(cString: ffmpeg_error_string(ret)))
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
        
        // Create resampler for Float32 stereo output
        guard let swr = ffmpeg_create_resampler(
            decCtx,
            Int32(AV_SAMPLE_FMT_FLT.rawValue),
            Int32(decCtx.pointee.sample_rate),
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
                if readRet == AVERROR_EOF {
                    return nil // End of file
                }
                throw FFmpegError.readFailed(code: readRet, message: String(cString: ffmpeg_error_string(readRet)))
            }
            
            guard packet.pointee.stream_index == audioStreamIndex else {
                av_packet_unref(packet)
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
            
            // Resample
            var outBuffer: UnsafeMutablePointer<UInt8>?
            var outSamples: Int32 = 0
            let resampleRet = ffmpeg_resample(swr, frame, &outBuffer, &outSamples)
            guard resampleRet == 0, let buffer = outBuffer else {
                throw FFmpegError.resampleFailed
            }
            
            // Create AVAudioPCMBuffer
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
            
            // Copy data to non-interleaved format
            let channelData = pcmBuffer.floatChannelData!
            let bytesPerChannel = Int(outSamples) * MemoryLayout<Float>.size
            
            // Input is interleaved stereo: L R L R ...
            // Output should be non-interleaved: L L L ... R R R ...
            let interleaved = buffer.withMemoryRebound(to: Float.self, capacity: Int(outSamples) * 2) { ptr in
                return ptr
            }
            
            for i in 0..<Int(outSamples) {
                channelData[0][i] = interleaved[i * 2]      // Left
                channelData[1][i] = interleaved[i * 2 + 1]  // Right
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
            throw FFmpegError.seekFailed(code: ret, message: String(cString: ffmpeg_error_string(ret)))
        }
        
        // Flush decoder buffers
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
```

## Xcode Project Setup

### Build Settings

1. **Header Search Paths**:
   - `/opt/homebrew/include` (Apple Silicon)
   - `/usr/local/include` (Intel)
   - Or path to your custom FFmpeg build

2. **Library Search Paths**:
   - `/opt/homebrew/lib` (Apple Silicon)
   - `/usr/local/lib` (Intel)
   - Or path to your custom FFmpeg build

3. **Other Linker Flags**:
   ```
   -lavformat -lavcodec -lswresample -lavutil -lz -lbz2
   ```

4. **Swift Bridging Header**:
   Create `AudioPlayerMac-Bridging-Header.h`:
   ```c
   #include "FFmpegBridge.h"
   ```

### Info.plist

Add to Info.plist for audio file access:
```xml
<key>NSAppleMusicUsageDescription</key>
<string>This app needs access to play audio files.</string>
```

## Testing

Test FFmpeg integration:

```bash
# Build
xcodebuild -scheme AudioPlayerMac -configuration Debug build

# Test with TrueHD file
# Create a simple test that opens and decodes a TrueHD file
```

## Troubleshooting

### Common issues

1. **Library not found**: Check Library Search Paths
2. **Undefined symbols**: Check Other Linker Flags
3. **Header not found**: Check Header Search Paths
4. **Linker errors**: Ensure all required libraries are linked

### Debug tips

1. Use `ffmpeg_version()` to verify FFmpeg is loaded
2. Check error codes with `ffmpeg_error_string()`
3. Enable FFmpeg logging for detailed errors

## See also

- Decoder path selection rules: `docs/dev/decoder-paths.md`
- Architecture overview: `docs/dev/architecture.md`
