#ifndef FFmpegBridge_h
#define FFmpegBridge_h

#include <stdint.h>
#include <stddef.h>

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/opt.h>
#include <libavutil/channel_layout.h>

void ffmpeg_init(void);

int ffmpeg_open_file(const char *path, AVFormatContext **ctx);
void ffmpeg_close_file(AVFormatContext *ctx);

int ffmpeg_find_audio_stream(AVFormatContext *ctx);
AVCodecContext *ffmpeg_create_decoder(AVFormatContext *ctx, int stream_index);
void ffmpeg_free_decoder(AVCodecContext *ctx);

int ffmpeg_get_sample_rate(AVCodecContext *ctx);
int ffmpeg_get_channels(AVCodecContext *ctx);
int64_t ffmpeg_get_duration_ms(AVFormatContext *ctx);

int ffmpeg_read_frame(AVFormatContext *ctx, AVPacket *pkt);
int ffmpeg_send_packet(AVCodecContext *ctx, AVPacket *pkt);
int ffmpeg_receive_frame(AVCodecContext *ctx, AVFrame *frame);

AVPacket *ffmpeg_alloc_packet(void);
void ffmpeg_free_packet(AVPacket *pkt);
AVFrame *ffmpeg_alloc_frame(void);
void ffmpeg_free_frame(AVFrame *frame);

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

int ffmpeg_seek(AVFormatContext *ctx, int64_t timestamp_ms);
void ffmpeg_flush_buffers(AVCodecContext *ctx);

const char *ffmpeg_version(void);
const char *ffmpeg_error_string(int error_code);
int ffmpeg_get_frame_size(AVCodecContext *ctx);
int64_t ffmpeg_averror_eof(void);

// Remux an elementary audio stream (e.g. raw EAC3 .eb3/.eac3) into an MP4
// container without decoding.  Returns 0 on success, negative FFmpeg error on
// failure.  On success *out_duration_ms is set to the stream duration.
int ffmpeg_remux_to_mp4(const char *input_path,
                        const char *output_path,
                        int64_t *out_duration_ms);
#endif
