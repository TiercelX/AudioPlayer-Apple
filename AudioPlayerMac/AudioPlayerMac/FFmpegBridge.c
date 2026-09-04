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

int64_t ffmpeg_averror_eof(void) {
    return AVERROR_EOF;
}
int ffmpeg_remux_to_mp4(const char *input_path,
                        const char *output_path,
                        int64_t *out_duration_ms) {
    AVFormatContext *ifmt_ctx = NULL;
    AVFormatContext *ofmt_ctx = NULL;
    AVPacket *pkt = NULL;
    int ret = 0;
    int audio_stream_idx = -1;
    int out_stream_idx = -1;
    int64_t pts_offset = 0;

    // Open input
    ret = avformat_open_input(&ifmt_ctx, input_path, NULL, NULL);
    if (ret < 0) goto cleanup;

    ret = avformat_find_stream_info(ifmt_ctx, NULL);
    if (ret < 0) goto cleanup;

    // Find audio stream
    audio_stream_idx = ffmpeg_find_audio_stream(ifmt_ctx);
    if (audio_stream_idx < 0) {
        ret = -1;
        goto cleanup;
    }

    // Open output
    ret = avformat_alloc_output_context2(&ofmt_ctx, NULL, "mov", output_path);
    if (ret < 0) goto cleanup;

    // Create output stream (copy codec parameters)
    AVStream *in_stream = ifmt_ctx->streams[audio_stream_idx];
    AVStream *out_stream = avformat_new_stream(ofmt_ctx, NULL);
    if (!out_stream) {
        ret = -1;
        goto cleanup;
    }
    out_stream_idx = out_stream->index;

    ret = avcodec_parameters_copy(out_stream->codecpar, in_stream->codecpar);
    if (ret < 0) goto cleanup;
    out_stream->codecpar->codec_tag = 0;

    // Open output file
    if (!(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
        ret = avio_open(&ofmt_ctx->pb, output_path, AVIO_FLAG_WRITE);
        if (ret < 0) goto cleanup;
    }

    // Write header
    ret = avformat_write_header(ofmt_ctx, NULL);
    if (ret < 0) goto cleanup;

    // Record start PTS offset so the output starts at 0
    pts_offset = in_stream->start_time != AV_NOPTS_VALUE
                     ? in_stream->start_time : 0;

    // Copy packets
    pkt = av_packet_alloc();
    if (!pkt) { ret = -1; goto cleanup; }

    while (av_read_frame(ifmt_ctx, pkt) >= 0) {
        if (pkt->stream_index != audio_stream_idx) {
            av_packet_unref(pkt);
            continue;
        }

        AVStream *in_s  = ifmt_ctx->streams[audio_stream_idx];
        AVStream *out_s = ofmt_ctx->streams[out_stream_idx];

        // Rescale PTS/DTS/Duration
        pkt->pts  = av_rescale_q_rnd(pkt->pts  - pts_offset,
                                     in_s->time_base, out_s->time_base,
                                     AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);
        pkt->dts  = av_rescale_q_rnd(pkt->dts  - pts_offset,
                                     in_s->time_base, out_s->time_base,
                                     AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);
        pkt->duration = av_rescale_q(pkt->duration,
                                     in_s->time_base, out_s->time_base);
        pkt->pos = -1;
        pkt->stream_index = out_stream_idx;

        ret = av_interleaved_write_frame(ofmt_ctx, pkt);
        av_packet_unref(pkt);
        if (ret < 0) goto cleanup;
    }

    // Write trailer
    av_write_trailer(ofmt_ctx);

    // Compute duration
    if (out_duration_ms) {
        int64_t dur_us = ofmt_ctx->duration;  // already in AV_TIME_BASE (µs)
        if (dur_us > 0) {
            *out_duration_ms = dur_us / 1000;
        } else {
            *out_duration_ms = 0;
        }
    }

cleanup:
    av_packet_free(&pkt);
    if (ofmt_ctx) {
        if (ofmt_ctx->pb && !(ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
            avio_closep(&ofmt_ctx->pb);
        }
        avformat_free_context(ofmt_ctx);
    }
    if (ifmt_ctx) {
        avformat_close_input(&ifmt_ctx);
    }
    return ret;
}
