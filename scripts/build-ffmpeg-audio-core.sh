#!/bin/bash
set -euo pipefail

FFMPEG_VERSION="n8.1.1"
FFMPEG_REPO="https://github.com/FFmpeg/FFmpeg.git"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX_DIR="$PROJECT_ROOT/AudioPlayerMac/ffmpeg-audio-core"
SRC_DIR="$PREFIX_DIR/src"
JOBS="${JOBS:-$(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || nproc)}"
ARCH="${ARCH:-universal}"
FORCE=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build a minimal FFmpeg audio-core static library for AudioPlayerMac.

Options:
  --arch ARCH      Target architecture: universal (default), arm64, x86_64
  --jobs N         Parallel build jobs (default: performance cores count)
  --prefix DIR     Install prefix (default: AudioPlayerMac/ffmpeg-audio-core)
  --force          Force rebuild even if stamp matches
  --help           Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)   ARCH="$2"; shift 2 ;;
        --jobs)   JOBS="$2"; shift 2 ;;
        --prefix) PREFIX_DIR="$2"; SRC_DIR="$PREFIX_DIR/src"; shift 2 ;;
        --force)  FORCE=1; shift ;;
        --help)   usage; exit 0 ;;
        *)        echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

CONFIGURE_FLAGS_HASH=$(echo \
    "--disable-autodetect --disable-avdevice --disable-debug --disable-doc \
     --disable-everything --disable-network --disable-shared --enable-static \
     --enable-avcodec --enable-avformat --enable-swresample --enable-avutil \
     --enable-protocol=file,pipe \
     --enable-demuxer=aac,ac3,eac3,flac,matroska,mov,mp3,truehd,wav \
     --enable-muxer=mov,matroska,null,pcm_f32le,pcm_s16le,pcm_s32le,pcm_u8 \
     --enable-decoder=aac,ac3,alac,eac3,flac,mp3,mp3float,pcm_f32le,pcm_s16le,pcm_s24le,pcm_s32le,pcm_u8,truehd \
     --enable-encoder=pcm_f32le,pcm_s16le,pcm_s32le,pcm_u8 \
     --enable-filter=aformat,aresample,channelmap,pan \
     --enable-parser=aac,ac3,flac,mlp,mpegaudio" | shasum -a 256 | cut -d' ' -f1)

SCRIPT_HASH=$(shasum -a 256 "$0" | cut -d' ' -f1)
STAMP_FILE="$PREFIX_DIR/ffmpeg-audio-core.stamp"

check_stamp() {
    [[ $FORCE -eq 1 ]] && return 1
    [[ -f "$STAMP_FILE" ]] || return 1
    local expected="$FFMPEG_VERSION|$CONFIGURE_FLAGS_HASH|$SCRIPT_HASH"
    local actual
    actual=$(cat "$STAMP_FILE")
    [[ "$actual" == "$expected" ]]
}

clone_ffmpeg() {
    if [[ -d "$SRC_DIR/.git" ]]; then
        echo "FFmpeg source already present at $SRC_DIR"
        return
    fi
    echo "Cloning FFmpeg $FFMPEG_VERSION (shallow)..."
    git clone --depth 1 --branch "$FFMPEG_VERSION" "$FFMPEG_REPO" "$SRC_DIR"
}

configure_and_build() {
    local arch=$1
    local build_dir="$PREFIX_DIR/$arch"
    local prefix="$build_dir"
    local host_arch
    host_arch=$(uname -m)
    local sdk_path
    sdk_path=$(xcrun --show-sdk-path 2>/dev/null || echo "")

    echo "=== Configuring FFmpeg for $arch (host=$host_arch) ==="
    cd "$SRC_DIR"
    make distclean 2>/dev/null || true

    local cross_flags=()
    if [[ "$arch" != "$host_arch" ]]; then
        cross_flags=(--enable-cross-compile --target-os=darwin)
        if [[ -n "$sdk_path" ]]; then
            cross_flags+=(--sysroot="$sdk_path")
        fi
    fi

    local configure_args=(
        --prefix="$prefix"
        --arch="$arch"
        --cc=clang
        --extra-cflags="-arch $arch -mmacosx-version-min=12.0"
        --extra-ldflags="-arch $arch -mmacosx-version-min=12.0"
        --disable-autodetect
        --disable-avdevice
        --disable-debug
        --disable-doc
        --disable-everything
        --disable-network
        --disable-shared
        --enable-static
        --enable-avcodec
        --enable-avformat
        --enable-swresample
        --enable-avutil
        --enable-protocol=file,pipe
        --enable-demuxer=aac,ac3,eac3,flac,matroska,mov,mp3,truehd,wav
        --enable-muxer=mov,matroska,null,pcm_f32le,pcm_s16le,pcm_s32le,pcm_u8
        --enable-decoder=aac,ac3,alac,eac3,flac,mp3,mp3float,pcm_f32le,pcm_s16le,pcm_s24le,pcm_s32le,pcm_u8,truehd
        --enable-encoder=pcm_f32le,pcm_s16le,pcm_s32le,pcm_u8
        --enable-filter=aformat,aresample,channelmap,pan
        --enable-parser=aac,ac3,flac,mlp,mpegaudio
    )
    if [[ ${#cross_flags[@]} -gt 0 ]]; then
        configure_args+=("${cross_flags[@]}")
    fi

    ./configure "${configure_args[@]}"

    echo "=== Building FFmpeg for $arch ($JOBS jobs) ==="
    make -j"$JOBS"
    make install
}

create_universal() {
    echo "=== Creating universal binaries ==="
    local uni_dir="$PREFIX_DIR/universal"
    rm -rf "$uni_dir"
    mkdir -p "$uni_dir/lib" "$uni_dir/include"

    cp -R "$PREFIX_DIR/arm64/include/" "$uni_dir/include/"

    for lib in "$PREFIX_DIR/arm64/lib/"*.a; do
        local name
        name=$(basename "$lib")
        lipo -create \
            "$PREFIX_DIR/arm64/lib/$name" \
            "$PREFIX_DIR/x86_64/lib/$name" \
            -output "$uni_dir/lib/$name"
    done
}

validate() {
    echo "=== Validating build ==="
    local uni_dir="$PREFIX_DIR/universal"
    local target_dir="$uni_dir"
    if [[ "$ARCH" != "universal" ]]; then
        target_dir="$PREFIX_DIR/$ARCH"
    fi

    local ok=1
    for f in \
        "$target_dir/lib/libavformat.a" \
        "$target_dir/lib/libavcodec.a" \
        "$target_dir/lib/libswresample.a" \
        "$target_dir/lib/libavutil.a" \
        "$target_dir/include/libavformat/avformat.h" \
        "$target_dir/include/libavcodec/avcodec.h"; do
        if [[ -f "$f" ]]; then
            echo "  OK   $f"
        else
            echo "  FAIL $f"
            ok=0
        fi
    done

    if [[ $ok -eq 0 ]]; then
        echo "Validation FAILED"
        exit 1
    fi
    echo "Validation PASSED"
}

write_stamp() {
    echo "$FFMPEG_VERSION|$CONFIGURE_FLAGS_HASH|$SCRIPT_HASH" > "$STAMP_FILE"
    echo "Stamp written to $STAMP_FILE"
}

print_summary() {
    echo ""
    echo "========================================"
    echo " FFmpeg audio-core build complete"
    echo "========================================"
    echo "Version:  $FFMPEG_VERSION"
    echo "Arch:     $ARCH"
    echo "Prefix:   $PREFIX_DIR/$ARCH"
    if [[ "$ARCH" == "universal" ]]; then
        echo "Prefix:   $PREFIX_DIR/universal"
    fi
    echo ""
    echo "Static libraries:"
    local lib_dir="$PREFIX_DIR/$ARCH/lib"
    if [[ "$ARCH" == "universal" ]]; then
        lib_dir="$PREFIX_DIR/universal/lib"
    fi
    for lib in "$lib_dir"/lib*.a; do
        [[ -f "$lib" ]] && echo "  $(basename "$lib")  $(du -h "$lib" | cut -f1)"
    done
    echo ""
    echo "Architectures:"
    if [[ "$ARCH" == "universal" ]]; then
        lipo -info "$lib_dir/libavformat.a"
    else
        echo "  $ARCH"
    fi
}

mkdir -p "$PREFIX_DIR"

if check_stamp; then
    echo "Build up-to-date (stamp matches). Use --force to rebuild."
    validate
    print_summary
    exit 0
fi

clone_ffmpeg

if [[ "$ARCH" == "universal" ]]; then
    configure_and_build arm64
    configure_and_build x86_64
    create_universal
else
    configure_and_build "$ARCH"
fi

validate
write_stamp
print_summary
