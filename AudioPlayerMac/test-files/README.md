# AudioPlayerMac Test Files

Place test audio files in this directory for smoke testing.

## Supported Formats

- **FLAC** - Free Lossless Audio Codec
- **MP3** - MPEG Audio Layer III
- **WAV** - Waveform Audio File Format
- **AAC** - Advanced Audio Coding (M4A container)
- **EAC3** - Dolby Digital Plus
- **AC3** - Dolby Digital
- **TrueHD** - Dolby TrueHD (requires FFmpeg)

## Test File Requirements

- Files should be short (5-30 seconds) for quick testing
- Include various sample rates (44.1kHz, 48kHz, 96kHz)
- Include various channel configurations (stereo, 5.1, 7.1)

## Running Tests

### Smoke Test
```bash
# From AudioPlayerMac/
./scripts/run-playback-smoke.sh

# With local media files
./scripts/run-playback-smoke.sh /path/to/media
```

### Generate test files
```bash
# Generate small test files for each format (requires ffmpeg)
./scripts/generate-test-files.sh
```

## Creating Test Files

You can create test files using FFmpeg:

```bash
# Generate a 10-second sine wave WAV file
ffmpeg -f lavfi -i "sine=frequency=440:duration=10" test-files/test-sine.wav

# Generate a 10-second MP3 file
ffmpeg -f lavfi -i "sine=frequency=440:duration=10" test-files/test-sine.mp3

# Generate a 10-second FLAC file
ffmpeg -f lavfi -i "sine=frequency=440:duration=10" test-files/test-sine.flac
```

## Expected Results

All test files should:
- Open without errors
- Play audio (if speakers are connected)
- Show correct duration
- Allow seeking
- Respond to play/pause/stop controls