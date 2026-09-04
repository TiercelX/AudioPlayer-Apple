# AudioPlayerMac

A native macOS audio player with Dolby Atmos support, built with Swift + AVFoundation + FFmpeg libav.

## Features

- **Native macOS app** with SwiftUI interface
- **Dolby Atmos support** (EAC3-JOC via AVFoundation)
- **Multiple format support**: FLAC, MP3, WAV, AAC, EAC3, AC3, TrueHD, MLP
- **Dual decoder architecture**: AVFoundation for common formats, FFmpeg for complex formats
- **Spatial audio** support for AirPods with head tracking
- **Output device selection** with automatic device detection
- **Audio artifact detection** for quality monitoring
- **Diagnostic reporting** for troubleshooting

## Requirements

- macOS 12.0 Monterey or later
- Xcode 15.0 or later
- FFmpeg (for TrueHD support)

## Installation

### 1. Install FFmpeg

```bash
brew install ffmpeg
```

### 2. Clone Repository

```bash
git clone <repository-url>
cd AudioPlayerMac
```

### 3. Build and Run

```bash
# Build
xcodebuild -scheme AudioPlayerMac -configuration Debug build

# Run
open build/Build/Products/Debug/AudioPlayerMac.app
```

## Project Structure

```
AudioPlayerMac/
├── AudioPlayerMac.xcodeproj/    # Xcode project
├── AudioPlayerMac/              # Source code
│   ├── App/                     # App entry point and state
│   ├── Core/                    # Audio engine, playback controller
│   ├── Decoders/                # AVFoundation and FFmpeg decoders
│   ├── UI/                      # SwiftUI views
│   ├── Source/                  # Media probing and preparation
│   ├── Diagnostics/             # Logging and artifact detection
│   └── Utilities/               # Helper functions
├── scripts/                     # Build and test scripts
├── test-files/                  # Test audio files
└── Tests/                       # Unit tests
```

## Usage

### Basic Playback

1. Launch the app
2. Click "Open" or drag and drop an audio file
3. Use playback controls (Play/Pause/Stop)
4. Adjust volume with the slider
5. Seek using the progress bar

### Keyboard Shortcuts

- **Space**: Play/Pause
- **⌘O**: Open file
- **⌘.**: Stop
- **⌘→**: Skip forward 10 seconds
- **⌘←**: Skip back 10 seconds
- **←→**: Seek forward/back 5 seconds

### Output Device Selection

Click the speaker icon in the toolbar to select audio output device.

## Supported Formats

| Format | Decoder | Notes |
|--------|---------|-------|
| FLAC | AVFoundation | Lossless |
| MP3 | AVFoundation | Lossy |
| WAV | AVFoundation | PCM |
| AAC | AVFoundation | Lossy |
| ALAC | AVFoundation | Apple Lossless |
| EAC3 | AVFoundation | Dolby Digital Plus |
| AC3 | AVFoundation | Dolby Digital |
| TrueHD | FFmpeg | Dolby TrueHD |
| MLP | FFmpeg | Meridian Lossless |

## Development

### Building

```bash
# Debug build
xcodebuild -scheme AudioPlayerMac -configuration Debug build

# Release build
xcodebuild -scheme AudioPlayerMac -configuration Release build

# Clean build
xcodebuild -scheme AudioPlayerMac -configuration Debug clean build
```

### Testing

```bash
# Run unit tests
xcodebuild -scheme AudioPlayerMac -configuration Debug test

# Run smoke test
./scripts/run-smoke-test.ps1
```

### Code Style

- Swift 5.9+
- SwiftUI for UI
- AVFoundation for audio
- FFmpeg for complex formats

## Architecture

The app follows a layered architecture:

1. **App Layer**: SwiftUI app entry point and state management
2. **UI Layer**: SwiftUI views for player interface
3. **Core Layer**: Audio engine, playback controller, output device management
4. **Decoder Layer**: AVFoundation and FFmpeg decoders with format detection
5. **Source Layer**: Media file probing and preparation
6. **Diagnostics Layer**: Logging, artifact detection, and reporting

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

Copyright © 2026. All rights reserved.

## Acknowledgments

- Apple for AVFoundation and SwiftUI
- FFmpeg team for libav libraries
- Dolby for Atmos specifications